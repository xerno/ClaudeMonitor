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

struct WindowEntry: Sendable, Equatable, Hashable, Comparable {
    let key: String
    let duration: TimeInterval
    let durationLabel: String
    let modelScope: String?
    let window: UsageWindow

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.duration != rhs.duration { return lhs.duration < rhs.duration }
        if lhs.modelScope == nil && rhs.modelScope != nil { return true }
        if lhs.modelScope != nil && rhs.modelScope == nil { return false }
        return (lhs.modelScope ?? "") < (rhs.modelScope ?? "")
    }

    static func make(key: String, utilization: Int, resetsAt: Date?) -> WindowEntry {
        guard let parsed = WindowKeyParser.parse(key) else {
            preconditionFailure("Invalid window key: \(key)")
        }
        return WindowEntry(
            key: key, duration: parsed.duration, durationLabel: parsed.durationLabel,
            modelScope: parsed.modelScope,
            window: UsageWindow(utilization: utilization, resetsAt: resetsAt)
        )
    }
}

enum WindowKeyParser {
    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20, "thirty": 30,
    ]

    private static let compoundTens: [String: Int] = [
        "twenty": 20, "thirty": 30,
    ]

    private static let timeUnits: [String: (seconds: TimeInterval, suffix: String)] = [
        "minute": (60, "m"), "hour": (3600, "h"), "day": (86_400, "d"), "week": (604_800, "w"),
    ]

    struct Parsed {
        let duration: TimeInterval
        let durationLabel: String
        let modelScope: String?
    }

    static func parse(_ key: String) -> Parsed? {
        let parts = key.split(separator: "_").map(String.init)
        guard parts.count >= 2 else { return nil }

        var numberValue: Int?
        var consumed = 0

        // Try two-word compound number first (e.g., "twenty_four")
        if parts.count >= 3, let tens = compoundTens[parts[0]], let ones = numberWords[parts[1]], ones < 10 {
            numberValue = tens + ones
            consumed = 2
        }
        if numberValue == nil, let n = numberWords[parts[0]] {
            numberValue = n
            consumed = 1
        }
        guard let number = numberValue, consumed < parts.count else { return nil }

        guard let unit = timeUnits[parts[consumed]] else { return nil }
        consumed += 1

        let scopeParts = Array(parts[consumed...])
        let modelScope: String? = scopeParts.isEmpty ? nil :
            scopeParts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")

        return Parsed(
            duration: TimeInterval(number) * unit.seconds,
            durationLabel: "\(number)\(unit.suffix)",
            modelScope: modelScope
        )
    }
}

struct UsageResponse: Sendable, Equatable, Hashable {
    let entries: [WindowEntry]

    var allWindows: [UsageWindow] { entries.map(\.window) }
}

extension UsageResponse: Decodable {
    private struct DynamicKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        var parsed: [WindowEntry] = []
        for key in container.allKeys {
            guard let info = WindowKeyParser.parse(key.stringValue),
                  let window = try? container.decode(UsageWindow.self, forKey: key) else { continue }
            parsed.append(WindowEntry(
                key: key.stringValue, duration: info.duration,
                durationLabel: info.durationLabel, modelScope: info.modelScope,
                window: window
            ))
        }
        self.init(entries: parsed.sorted())
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
