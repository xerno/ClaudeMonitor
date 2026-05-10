import AppKit
import Foundation

enum Formatting {
    static func timeUntil(_ date: Date, now: Date = Date()) -> String {
        timeUntil(date.timeIntervalSince(now))
    }

    static func timeUntil(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(max(interval, 0))
        if totalSeconds < 60 { return "\(totalSeconds)s" }
        let totalMinutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if totalMinutes < 2 {
            return seconds == 0 ? "\(totalMinutes)m" : "\(totalMinutes)m \(seconds)s"
        }
        if totalMinutes < 60 { return "\(totalMinutes)m" }
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours < Constants.Time.daysHoursTierThreshold {
            return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
        }
        let days = hours / 24
        let remainingHours = hours % 24
        return remainingHours == 0 ? "\(days)d" : "\(days)d \(remainingHours)h"
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

        if totalHours >= Constants.Time.daysHoursTierThreshold {
            intervalStart = TimeInterval(totalHours) * Constants.Time.secondsPerHour
            intervalSize = Constants.Time.secondsPerHour
        } else if totalMinutes >= 2 {
            intervalStart = TimeInterval(totalMinutes) * 60
            intervalSize = 60
        } else {
            intervalStart = TimeInterval(totalSeconds)
            intervalSize = 1
        }

        var nextCenter = intervalStart - intervalSize / 2

        // Snap to just before zone transitions (match display tiers in timeUntil)
        let daysToHoursThreshold: TimeInterval = TimeInterval(Constants.Time.daysHoursTierThreshold) * Constants.Time.secondsPerHour
        let minutesToSecondsThreshold: TimeInterval = 2 * 60
        if intervalSize == Constants.Time.secondsPerHour && nextCenter < daysToHoursThreshold {
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
        return usage.hasAnyModelSpecific
            ? "\(entry.durationLabel) \(String(localized: "window.scope.all", bundle: .module))"
            : entry.durationLabel
    }

    static func formatRate(_ consumptionRate: Double) -> String {
        let perHour = consumptionRate * Constants.Time.secondsPerHour
        if perHour >= 0.5 {
            return "\(Int(perHour.rounded()))%/h"
        }
        let perDay = consumptionRate * Constants.Time.secondsPerDay
        if perDay >= 0.5 {
            return "\(Int(perDay.rounded()))%/d"
        }
        return "< 1%/d"
    }

    static let barImageWidth: CGFloat = 120
    static let barImageWidthWide: CGFloat = 150
    static let barImageHeight: CGFloat = 12

    static func progressBarImage(percent: Int, width: CGFloat = barImageWidth) -> NSImage {
        let clamped = max(0, min(100, percent))
        return NSImage(size: NSSize(width: width, height: barImageHeight), flipped: false) { rect in
            NSColor.tertiaryLabelColor.setFill()
            let bgPath = NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2)
            bgPath.fill()
            let filledWidth = rect.width * CGFloat(clamped) / 100
            if filledWidth > 0 {
                NSColor.labelColor.setFill()
                let fgPath = NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: filledWidth, height: rect.height),
                                          xRadius: rect.height / 2, yRadius: rect.height / 2)
                fgPath.fill()
            }
            return true
        }
    }
}
