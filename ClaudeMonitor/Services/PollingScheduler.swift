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
                return nearestReset + Constants.Polling.resetPadding
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

        let tslc = windowAnalyses.compactMap(\.timeSinceLastChange).min()
        let factor = Self.activityFactor(timeSinceLastChange: tslc)
        let maxRate = windowAnalyses.compactMap(\.recentRate).max() ?? 0
        let effectiveRate = maxRate * factor
        let desired: TimeInterval = effectiveRate > 0
            ? Constants.Polling.resolutionPerPoll / effectiveRate
            : .infinity

        let baseCooldown = Self.cooldownInterval(timeSinceLastChange: tslc)
        isAwayMode = baseCooldown >= Constants.Polling.maxIdleInterval
            && systemIdleTime > Constants.Polling.awayThreshold

        let upperBound = Self.upperBound(
            baseCooldown: baseCooldown,
            awayMode: isAwayMode,
            systemIdleTime: systemIdleTime,
            windowAnalyses: windowAnalyses
        )

        effectivePollingInterval = max(Constants.Polling.minInterval, min(desired, upperBound))
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

    private static func activityFactor(timeSinceLastChange tslc: TimeInterval?) -> Double {
        guard let tslc else { return 1.0 }
        if tslc <= Constants.Polling.activityGrace { return 1.0 }
        let afterGrace = tslc - Constants.Polling.activityGrace
        if afterGrace >= Constants.Polling.activityDecay { return 0.0 }
        return 1.0 - (afterGrace / Constants.Polling.activityDecay)
    }

    private static func cooldownInterval(timeSinceLastChange tslc: TimeInterval?) -> TimeInterval {
        guard let tslc, tslc >= Constants.Polling.cooldownStart else {
            return Constants.Polling.baseInterval
        }
        let t = min(max((tslc - Constants.Polling.cooldownStart) / Constants.Polling.cooldownRamp, 0), 1)
        let spread = Constants.Polling.maxIdleInterval - Constants.Polling.baseInterval
        return Constants.Polling.baseInterval + t * spread
    }

    private static func awayInterval(systemIdleTime: TimeInterval) -> TimeInterval {
        let span = Constants.Polling.awayRampEnd - Constants.Polling.awayThreshold
        let t = min(max((systemIdleTime - Constants.Polling.awayThreshold) / span, 0), 1)
        let spread = Constants.Polling.maxAwayInterval - Constants.Polling.maxIdleInterval
        return Constants.Polling.maxIdleInterval + t * spread
    }

    private static func upperBound(
        baseCooldown: TimeInterval,
        awayMode: Bool,
        systemIdleTime: TimeInterval,
        windowAnalyses: [WindowAnalysis]
    ) -> TimeInterval {
        if awayMode {
            return awayInterval(systemIdleTime: systemIdleTime)
        }
        let nearLimit = windowAnalyses.contains {
            Double($0.entry.window.utilization) >= Constants.Projection.boldThreshold
        }
        return nearLimit
            ? min(baseCooldown, Constants.Polling.nearLimitCooldownCap)
            : baseCooldown
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
