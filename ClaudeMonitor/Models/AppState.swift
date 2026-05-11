import Foundation

struct PollingState: Sendable, Equatable {
    let isOnline: Bool
    let hasRecentFailure: Bool
    let lastFailedAt: Date?
    let isAnyServiceStale: Bool
    let currentPollInterval: TimeInterval?
    let isUsageDataExpired: Bool

    init(
        isOnline: Bool = true,
        hasRecentFailure: Bool = false,
        lastFailedAt: Date? = nil,
        isAnyServiceStale: Bool = false,
        currentPollInterval: TimeInterval? = nil,
        isUsageDataExpired: Bool = false
    ) {
        self.isOnline = isOnline
        self.hasRecentFailure = hasRecentFailure
        self.lastFailedAt = lastFailedAt
        self.isAnyServiceStale = isAnyServiceStale
        self.currentPollInterval = currentPollInterval
        self.isUsageDataExpired = isUsageDataExpired
    }
}

struct UsageSnapshot: Sendable, Equatable {
    let currentUsage: UsageResponse?
    let usageError: String?
    let windowAnalyses: [WindowAnalysis]

    init(
        currentUsage: UsageResponse? = nil,
        usageError: String? = nil,
        windowAnalyses: [WindowAnalysis] = []
    ) {
        self.currentUsage = currentUsage
        self.usageError = usageError
        self.windowAnalyses = windowAnalyses
    }
}

struct ServiceHealth: Sendable, Equatable {
    let currentStatus: StatusSummary?
    let statusError: String?

    init(
        currentStatus: StatusSummary? = nil,
        statusError: String? = nil
    ) {
        self.currentStatus = currentStatus
        self.statusError = statusError
    }
}

struct MonitorState: Sendable, Equatable {
    let usage: UsageSnapshot
    let service: ServiceHealth
    let polling: PollingState
    let lastRefreshed: Date?
    let hasCredentials: Bool

    init(
        usage: UsageSnapshot = UsageSnapshot(),
        service: ServiceHealth = ServiceHealth(),
        polling: PollingState = PollingState(),
        lastRefreshed: Date? = nil,
        hasCredentials: Bool = false
    ) {
        self.usage = usage
        self.service = service
        self.polling = polling
        self.lastRefreshed = lastRefreshed
        self.hasCredentials = hasCredentials
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
