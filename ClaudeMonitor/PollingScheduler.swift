import Foundation

struct PollingScheduler {
    private(set) var statusState = ServiceState()
    private(set) var usageState = ServiceState()
    private var effectivePollingInterval: TimeInterval = Constants.Polling.baseInterval
    private var previousFiveHourUtil: Int?

    var hasRefreshWarning: Bool {
        statusState.consecutiveFailures >= Constants.Retry.failureThreshold
            || usageState.consecutiveFailures >= Constants.Retry.failureThreshold
    }

    var isUsageStale: Bool {
        guard let last = usageState.lastSuccess else { return false }
        return Date().timeIntervalSince(last) > Constants.Retry.staleDataMaxAge
    }

    func nextPollInterval(usage: UsageResponse?) -> TimeInterval {
        if statusState.lastError != nil || usageState.lastError != nil {
            let statusRetry = retryInterval(for: statusState)
            let usageRetry = retryInterval(for: usageState)
            return min(
                statusRetry ?? effectivePollingInterval,
                usageRetry ?? effectivePollingInterval
            )
        }

        if let usage {
            let now = Date()
            if let nearestReset = [usage.fiveHour?.resetsAt, usage.sevenDay?.resetsAt, usage.sevenDaySonnet?.resetsAt]
                .compactMap({ $0 })
                .map({ $0.timeIntervalSince(now) })
                .filter({ $0 > 0 && $0 < effectivePollingInterval })
                .min() {
                return nearestReset + 1
            }
        }

        return effectivePollingInterval
    }

    mutating func adjustPollingRate(usage: UsageResponse?, isCritical: Bool) {
        let currentUtil = usage?.fiveHour?.utilization
        defer { previousFiveHourUtil = currentUtil }

        guard let current = currentUtil, let previous = previousFiveHourUtil else {
            effectivePollingInterval = Constants.Polling.baseInterval
            return
        }

        let delta = current - previous

        if delta > 0 {
            effectivePollingInterval = max(
                effectivePollingInterval * 0.7, Constants.Polling.minInterval
            )
        } else if delta < -10 {
            effectivePollingInterval = Constants.Polling.baseInterval
        } else {
            effectivePollingInterval = min(
                effectivePollingInterval * 1.3, Constants.Polling.maxInterval
            )
        }

        if isCritical {
            effectivePollingInterval = max(
                effectivePollingInterval, Constants.Polling.criticalFloor
            )
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
        previousFiveHourUtil = nil
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
