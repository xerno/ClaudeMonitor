import Foundation

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
    private static let internalWindowMarkers = ["omelette"]

    static func isInternalWindow(_ key: String) -> Bool {
        internalWindowMarkers.contains { key.contains($0) }
    }

    private static let numberWords: [String: Int] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10,
        "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
        "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
        "nineteen": 19, "twenty": 20, "thirty": 30, "forty": 40,
        "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
    ]

    private static let compoundTens: [String: Int] = numberWords.filter { $0.value >= 20 && $0.value % 10 == 0 }

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
    let hasAnyModelSpecific: Bool

    init(entries: [WindowEntry]) {
        self.entries = entries
        self.hasAnyModelSpecific = entries.contains { $0.modelScope != nil }
    }

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
            guard !WindowKeyParser.isInternalWindow(key.stringValue),
                  let info = WindowKeyParser.parse(key.stringValue),
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
