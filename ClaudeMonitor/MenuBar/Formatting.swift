import Foundation

enum Formatting {
    static func timeUntil(_ date: Date, now: Date = Date()) -> String {
        let diff = max(date.timeIntervalSince(now), 0)
        let totalSeconds = Int(diff)

        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let totalMinutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if totalMinutes < 2 {
            return "\(totalMinutes)m \(seconds)s"
        }
        if totalMinutes < 60 {
            return "\(totalMinutes)m"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours < 25 {
            return "\(hours)h \(minutes)m"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return "\(days)d \(remainingHours)h"
    }

    static func formatInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(interval, 0))
        if totalSeconds < 60 { return "\(totalSeconds)s" }
        let totalMinutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if totalMinutes < 60 {
            return seconds == 0 ? "\(totalMinutes)m" : "\(totalMinutes)m \(seconds)s"
        }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    static func nextTickTarget(resetTimes: [Date], now: Date) -> Date? {
        resetTimes.compactMap { nextTickTargetSingle(resetTime: $0, now: now) }.min()
    }

    static func nextTickTargetSingle(resetTime: Date, now: Date) -> Date? {
        let remaining = resetTime.timeIntervalSince(now)
        guard remaining > 0 else { return nil }

        let totalSeconds = Int(remaining)
        guard totalSeconds > 0 else { return nil }

        let totalMinutes = totalSeconds / 60
        let totalHours = totalMinutes / 60

        let intervalStart: TimeInterval
        let intervalSize: TimeInterval

        if totalHours >= 25 {
            intervalStart = TimeInterval(totalHours) * 3600
            intervalSize = 3600
        } else if totalMinutes >= 2 {
            intervalStart = TimeInterval(totalMinutes) * 60
            intervalSize = 60
        } else {
            intervalStart = TimeInterval(totalSeconds)
            intervalSize = 1
        }

        var nextCenter = intervalStart - intervalSize / 2

        // Snap to just before zone transitions (match display tiers in timeUntil)
        let daysToHoursThreshold: TimeInterval = 25 * 3600
        let minutesToSecondsThreshold: TimeInterval = 2 * 60
        if intervalSize == 3600 && nextCenter < daysToHoursThreshold {
            nextCenter = daysToHoursThreshold - 30
        } else if intervalSize == 60 && nextCenter < minutesToSecondsThreshold {
            nextCenter = minutesToSecondsThreshold - 0.5
        }

        guard nextCenter > 0 else {
            return resetTime.addingTimeInterval(-0.5)
        }
        return resetTime.addingTimeInterval(-nextCenter)
    }

    static func displayLabel(for entry: WindowEntry, in usage: UsageResponse) -> String {
        if let scope = entry.modelScope {
            return "\(entry.durationLabel) \(scope)"
        }
        let hasAnyModelSpecific = usage.entries.contains { $0.modelScope != nil }
        return hasAnyModelSpecific
            ? "\(entry.durationLabel) \(String(localized: "window.scope.all", bundle: .module))"
            : entry.durationLabel
    }

    static func progressBar(percent: Int, width: Int = 10) -> String {
        let clamped = min(max(percent, 0), 100)
        let filled = Int(round(Double(clamped) / 100.0 * Double(width)))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }
}
