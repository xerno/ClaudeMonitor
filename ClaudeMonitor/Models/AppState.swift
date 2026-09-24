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

/// Mirrors `UsageHistory`'s persistence-failure and quarantine-count state (Defect 5/4) into
/// the value-type state pipeline, so the menu layer can surface it without reaching into
/// `usageHistory` directly.
struct HistoryHealth: Sendable, Equatable {
    let lastSaveSucceeded: Bool
    let persistenceFailingSince: Date?
    let quarantinedFileCount: Int

    init(
        lastSaveSucceeded: Bool = true,
        persistenceFailingSince: Date? = nil,
        quarantinedFileCount: Int = 0
    ) {
        self.lastSaveSucceeded = lastSaveSucceeded
        self.persistenceFailingSince = persistenceFailingSince
        self.quarantinedFileCount = quarantinedFileCount
    }
}

struct ProfileSnapshot: Sendable, Equatable {
    let profiles: [Profile]
    let activeId: String?

    init(profiles: [Profile] = [], activeId: String? = nil) {
        self.profiles = profiles
        self.activeId = activeId
    }
}

struct MonitorState: Sendable, Equatable {
    let usage: UsageSnapshot
    let service: ServiceHealth
    let polling: PollingState
    let history: HistoryHealth
    let profiles: ProfileSnapshot
    let lastRefreshed: Date?
    let hasCredentials: Bool
    let showGraph: Bool
    let compactServices: Bool

    init(
        usage: UsageSnapshot = UsageSnapshot(),
        service: ServiceHealth = ServiceHealth(),
        polling: PollingState = PollingState(),
        history: HistoryHealth = HistoryHealth(),
        profiles: ProfileSnapshot = ProfileSnapshot(),
        lastRefreshed: Date? = nil,
        hasCredentials: Bool = false,
        showGraph: Bool = true,
        compactServices: Bool = true
    ) {
        self.usage = usage
        self.service = service
        self.polling = polling
        self.history = history
        self.profiles = profiles
        self.lastRefreshed = lastRefreshed
        self.hasCredentials = hasCredentials
        self.showGraph = showGraph
        self.compactServices = compactServices
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
