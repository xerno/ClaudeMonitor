import Foundation

struct PollingScheduler {
    private(set) var statusState = ServiceState()
    private(set) var usageState = ServiceState()
    private var effectivePollingInterval: TimeInterval = Constants.Polling.baseInterval
    private var previousMaxUtil: Int?
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

    mutating func adjustPollingRate(usage: UsageResponse?, isCritical: Bool) {
        let currentUtil = usage?.entries.map(\.window.utilization).max()
        defer { previousMaxUtil = currentUtil }

        guard let current = currentUtil, let previous = previousMaxUtil else {
            effectivePollingInterval = Constants.Polling.baseInterval
            consecutiveNoChange = 0
            return
        }

        let delta = current - previous
        if delta > 0 {
            applySpeedup()
        } else if delta < 0 {
            applyDeceleration()
        } else {
            applyCooldown()
        }

        let isHighUtil = current >= Constants.Polling.highUtilizationThreshold
        if isCritical || isHighUtil {
            effectivePollingInterval = min(effectivePollingInterval, Constants.Polling.criticalFloor)
        }
    }

    private mutating func applySpeedup() {
        consecutiveNoChange = 0
        if effectivePollingInterval > Constants.Polling.baseInterval {
            effectivePollingInterval = Constants.Polling.baseInterval
        } else {
            effectivePollingInterval = max(
                floor(effectivePollingInterval * Constants.Polling.speedupFactor),
                Constants.Polling.minInterval
            )
        }
    }

    private mutating func applyDeceleration() {
        if effectivePollingInterval > Constants.Polling.baseInterval {
            effectivePollingInterval = Constants.Polling.baseInterval
            consecutiveNoChange = 0
        }
        // fast mode (≤ base): cooldown counter continues uninterrupted
    }

    private mutating func applyCooldown() {
        consecutiveNoChange += 1
        if consecutiveNoChange >= Constants.Polling.cooldownCycles {
            let slower = ceil(effectivePollingInterval / Constants.Polling.speedupFactor)
            if effectivePollingInterval < Constants.Polling.baseInterval && slower >= Constants.Polling.baseInterval {
                effectivePollingInterval = Constants.Polling.baseInterval
                consecutiveNoChange = 0
            } else {
                effectivePollingInterval = min(slower, Constants.Polling.maxInterval)
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
        previousMaxUtil = nil
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
