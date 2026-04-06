import Foundation

struct StatusSummary: Decodable, Sendable, Equatable, Hashable {
    let components: [StatusComponent]
    let incidents: [Incident]
    let status: PageStatus
}

struct StatusComponent: Decodable, Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let status: ComponentStatus
}

enum ComponentStatus: String, Decodable, Sendable, Comparable, Hashable {
    case operational
    case degradedPerformance = "degraded_performance"
    case partialOutage = "partial_outage"
    case majorOutage = "major_outage"
    case underMaintenance = "under_maintenance"
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        self = ComponentStatus(rawValue: raw) ?? .unknown
    }

    var severity: Int {
        switch self {
        case .unknown: return -1
        case .operational: return 0
        case .underMaintenance: return 1
        case .degradedPerformance: return 2
        case .partialOutage: return 3
        case .majorOutage: return 4
        }
    }

    static func < (lhs: ComponentStatus, rhs: ComponentStatus) -> Bool {
        lhs.severity < rhs.severity
    }

    var label: String {
        switch self {
        case .operational: return String(localized: "status.operational", bundle: .module)
        case .degradedPerformance: return String(localized: "status.degraded", bundle: .module)
        case .partialOutage: return String(localized: "status.partial_outage", bundle: .module)
        case .majorOutage: return String(localized: "status.major_outage", bundle: .module)
        case .underMaintenance: return String(localized: "status.maintenance", bundle: .module)
        case .unknown: return String(localized: "status.unknown", bundle: .module)
        }
    }

    var dot: String {
        switch self {
        case .operational: return "🟢"
        case .degradedPerformance: return "🟡"
        case .partialOutage: return "🟠"
        case .majorOutage: return "🔴"
        case .underMaintenance: return "🔵"
        case .unknown: return "⚪"
        }
    }

}

struct Incident: Decodable, Sendable, Equatable, Hashable, Identifiable {
    let id: String
    let name: String
    let status: String
    let impact: String
    let shortlink: String
}

struct PageStatus: Decodable, Sendable, Equatable, Hashable {
    let indicator: String
    let description: String
}

struct UsageResponse: Decodable, Sendable, Equatable, Hashable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDaySonnet: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

struct UsageWindow: Decodable, Sendable, Equatable, Hashable {
    let utilization: Int
    let resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

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
    var consecutiveFailures = 0
    var lastError: RetryCategory?
    var lastSuccess: Date?
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
