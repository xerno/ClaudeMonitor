import Foundation

struct PollingScheduler {
    private(set) var statusState = ServiceState()
    private(set) var usageState = ServiceState()
    private var effectivePollingInterval: TimeInterval = Constants.Polling.baseInterval
    private var consecutiveNoChange: Int = 0

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

    mutating func adjustPollingRate(windowAnalyses: [WindowAnalysis]) {
        guard !windowAnalyses.isEmpty else {
            effectivePollingInterval = Constants.Polling.baseInterval
            consecutiveNoChange = 0
            return
        }

        // Priority 1: Approaching limit (any window < 10 min to limit)
        let timesToLimit = windowAnalyses.compactMap(\.timeToLimit)
        if let nearest = timesToLimit.filter({ $0 < 600 }).min() {
            effectivePollingInterval = max(Constants.Polling.minInterval, nearest / 5)
            consecutiveNoChange = 0
            return
        }

        // Priority 2: Significantly outpacing (projected >= 120%)
        if windowAnalyses.contains(where: { $0.projectedAtReset >= Constants.Projection.criticalThreshold }) {
            effectivePollingInterval = max(Constants.Polling.minInterval, Constants.Polling.baseInterval / 2)
            consecutiveNoChange = 0
            return
        }

        // Priority 3: Mildly outpacing (projected 100–120%)
        if windowAnalyses.contains(where: { $0.projectedAtReset >= Constants.Projection.warningThreshold }) {
            effectivePollingInterval = Constants.Polling.baseInterval
            consecutiveNoChange = 0
            return
        }

        // Priority 4: Active consumption (any rate > 0, all projected < 100%)
        if windowAnalyses.contains(where: { $0.consumptionRate > 0 }) {
            effectivePollingInterval = Constants.Polling.baseInterval
            consecutiveNoChange = 0
            return
        }

        // Priority 5: Idle — gradually extend but cap at 300s
        applyCooldown()
    }

    private mutating func applyCooldown() {
        consecutiveNoChange += 1
        if consecutiveNoChange >= Constants.Polling.cooldownCycles {
            let slower = ceil(effectivePollingInterval / Constants.Polling.speedupFactor)
            if effectivePollingInterval < Constants.Polling.baseInterval && slower >= Constants.Polling.baseInterval {
                effectivePollingInterval = Constants.Polling.baseInterval
                consecutiveNoChange = 0
            } else {
                effectivePollingInterval = min(slower, Constants.Retry.maxBackoff)
            }
        }
    }

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
        consecutiveNoChange = 0
    }

    // MARK: - Private

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
