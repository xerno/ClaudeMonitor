import Foundation

struct PollingScheduler {
    private(set) var statusState = ServiceState()
    private(set) var usageState = ServiceState()
    private(set) var effectivePollingInterval: TimeInterval = Constants.Polling.baseInterval
    private(set) var isAwayMode: Bool = false

    var hasRefreshWarning: Bool {
        statusState.consecutiveFailures >= Constants.Retry.failureThreshold
            || usageState.consecutiveFailures >= Constants.Retry.failureThreshold
    }

    var isUsageStale: Bool {
        guard let last = usageState.lastSuccess else { return false }
        return Date().timeIntervalSince(last) > Constants.Retry.staleDataMaxAge
    }

    func nextPollInterval(usage: UsageResponse?) -> TimeInterval {
        if statusState.consecutiveFailures >= Constants.Retry.failureThreshold
            || usageState.consecutiveFailures >= Constants.Retry.failureThreshold {
            let statusRetry = retryInterval(for: statusState)
            let usageRetry = retryInterval(for: usageState)
            // When both failures are non-retryable (e.g. authFailure/permanent), both retry
            // intervals are nil AND both services are at the failure threshold. In that case,
            // avoid polling faster than baseInterval, regardless of any aggressive
            // effectivePollingInterval set before the failures began.
            // Note: retryInterval(for:) also returns nil when a service is below the threshold
            // (healthy), so we must check consecutiveFailures explicitly to avoid conflating a
            // healthy service with a non-retryable failure.
            let statusNonRetryable = statusState.consecutiveFailures >= Constants.Retry.failureThreshold && statusRetry == nil
            let usageNonRetryable = usageState.consecutiveFailures >= Constants.Retry.failureThreshold && usageRetry == nil
            if statusNonRetryable && usageNonRetryable {
                return max(effectivePollingInterval, Constants.Polling.baseInterval)
            }
            return min(
                statusRetry ?? effectivePollingInterval,
                usageRetry ?? effectivePollingInterval
            )
        }

        if let usage {
            let now = Date()
            let resetDates = usage.entries.compactMap(\.window.resetsAt)
            let nearest = resetDates
                .map { $0.timeIntervalSince(now) }
                .filter { $0 > 0 && $0 < effectivePollingInterval }
                .min()
            if let nearestReset = nearest {
                let resetPadding: TimeInterval = 1
                return nearestReset + resetPadding
            }
        }

        return effectivePollingInterval
    }

    mutating func adjustPollingRate(windowAnalyses: [WindowAnalysis], systemIdleTime: TimeInterval = 0) {
        guard !windowAnalyses.isEmpty else {
            effectivePollingInterval = Constants.Polling.baseInterval
            isAwayMode = false
            return
        }

        // Priority 1: Approaching limit (any window < 10 min to limit)
        let timesToLimit = windowAnalyses.compactMap(\.timeToLimit)
        if let nearest = timesToLimit.filter({ $0 < 600 }).min() {
            effectivePollingInterval = max(Constants.Polling.minInterval, nearest / 5)
            isAwayMode = false
            return
        }

        // Priority 2: Significantly outpacing (projected >= 120%)
        if windowAnalyses.contains(where: { $0.projectedAtReset >= Constants.Projection.criticalThreshold }) {
            effectivePollingInterval = max(Constants.Polling.minInterval, Constants.Polling.baseInterval / 2)
            isAwayMode = false
            return
        }

        // Priority 3: Mildly outpacing (projected 100-120%)
        if windowAnalyses.contains(where: { $0.projectedAtReset >= Constants.Projection.warningThreshold }) {
            effectivePollingInterval = Constants.Polling.baseInterval
            isAwayMode = false
            return
        }

        // From here: no ramp-up condition. Determine cooldown.
        let minTimeSinceChange = windowAnalyses.compactMap(\.timeSinceLastChange).min()

        // Recent activity → baseline
        guard let tslc = minTimeSinceChange, tslc >= Constants.Polling.cooldownStart else {
            effectivePollingInterval = Constants.Polling.baseInterval
            isAwayMode = false
            return
        }

        // Severity dampener: worst style across windows slows cooldown
        let cooldownSpeed = Self.cooldownSpeed(for: windowAnalyses)
        let effectiveTslc = tslc * cooldownSpeed

        // Idle at desk interpolation: 60s → 300s over effectiveTslc 5min → 60min
        let t = min(max((effectiveTslc - Constants.Polling.cooldownStart) / (Constants.Polling.cooldownEnd - Constants.Polling.cooldownStart), 0), 1)
        let idleInterval = Constants.Polling.baseInterval + t * (Constants.Polling.maxIdleInterval - Constants.Polling.baseInterval)

        // Away detection: only when idle interval reached cap AND system is idle
        if idleInterval >= Constants.Polling.maxIdleInterval && systemIdleTime > Constants.Polling.awayThreshold {
            isAwayMode = true
            let awayT = min(max((systemIdleTime - Constants.Polling.awayThreshold) / (Constants.Polling.awayRampEnd - Constants.Polling.awayThreshold), 0), 1)
            effectivePollingInterval = Constants.Polling.maxIdleInterval + awayT * (Constants.Polling.maxAwayInterval - Constants.Polling.maxIdleInterval)
        } else {
            isAwayMode = false
            effectivePollingInterval = idleInterval
        }
    }

    // MARK: - Error Recording

    mutating func recordStatusSuccess() {
        statusState.recordSuccess()
    }

    mutating func recordStatusFailure(category: RetryCategory) {
        statusState.recordFailure(category: category)
    }

    mutating func recordUsageSuccess() {
        usageState.recordSuccess()
    }

    mutating func recordUsageFailure(category: RetryCategory) {
        usageState.recordFailure(category: category)
    }

    mutating func reset() {
        statusState = ServiceState()
        usageState = ServiceState()
        effectivePollingInterval = Constants.Polling.baseInterval
        isAwayMode = false
    }

    // MARK: - Private

    private static func cooldownSpeed(for windowAnalyses: [WindowAnalysis]) -> Double {
        guard let worst = windowAnalyses.map(\.style).max() else { return 1.0 }
        switch worst.level {
        case .critical, .warning:
            return 0.4  // shouldn't normally reach here (ramp-up catches), but safe fallback
        case .normal:
            return worst.isBold ? 0.7 : 1.0
        }
    }

    private func retryInterval(for state: ServiceState) -> TimeInterval? {
        guard state.consecutiveFailures >= Constants.Retry.failureThreshold else { return nil }
        switch state.lastError {
        case .authFailure, .permanent, nil:
            return nil
        case .transient, .rateLimited:
            return state.currentBackoff
        }
    }
}
