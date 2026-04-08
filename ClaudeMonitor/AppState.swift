import Foundation

struct MonitorState: Sendable, Equatable {
    let currentUsage: UsageResponse?
    let currentStatus: StatusSummary?
    let usageError: String?
    let statusError: String?
    let lastRefreshed: Date?
    let hasCredentials: Bool
    let currentPollInterval: TimeInterval?
}

struct ServiceState: Sendable {
    private(set) var consecutiveFailures = 0
    private(set) var lastError: RetryCategory?
    private(set) var lastSuccess: Date?
    private(set) var currentBackoff: TimeInterval = Constants.Retry.initialBackoff

    mutating func recordSuccess() {
        consecutiveFailures = 0
        lastError = nil
        lastSuccess = Date()
        currentBackoff = Constants.Retry.initialBackoff
    }

    mutating func recordFailure(category: RetryCategory) {
        consecutiveFailures += 1
        lastError = category
        if category == .transient || category == .rateLimited {
            currentBackoff = min(currentBackoff * 2, Constants.Retry.maxBackoff)
        }
    }
}
