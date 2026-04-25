import Foundation

struct MonitorState: Sendable, Equatable {
    let currentUsage: UsageResponse?
    let currentStatus: StatusSummary?
    let usageError: String?
    let statusError: String?
    let lastRefreshed: Date?
    let hasCredentials: Bool
    let currentPollInterval: TimeInterval?
    let windowAnalyses: [WindowAnalysis]
    let isUsageStale: Bool
    let isOnline: Bool
    let hasRecentFailure: Bool
    let lastFailedAt: Date?
    let isStale: Bool

    init(
        currentUsage: UsageResponse?,
        currentStatus: StatusSummary?,
        usageError: String?,
        statusError: String?,
        lastRefreshed: Date?,
        hasCredentials: Bool,
        currentPollInterval: TimeInterval?,
        windowAnalyses: [WindowAnalysis] = [],
        isUsageStale: Bool = false,
        isOnline: Bool = true,
        hasRecentFailure: Bool = false,
        lastFailedAt: Date? = nil,
        isStale: Bool = false
    ) {
        self.currentUsage = currentUsage
        self.currentStatus = currentStatus
        self.usageError = usageError
        self.statusError = statusError
        self.lastRefreshed = lastRefreshed
        self.hasCredentials = hasCredentials
        self.currentPollInterval = currentPollInterval
        self.windowAnalyses = windowAnalyses
        self.isUsageStale = isUsageStale
        self.isOnline = isOnline
        self.hasRecentFailure = hasRecentFailure
        self.lastFailedAt = lastFailedAt
        self.isStale = isStale
    }
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
