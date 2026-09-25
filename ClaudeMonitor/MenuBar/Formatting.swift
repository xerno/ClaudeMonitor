import AppKit
import Foundation

enum Formatting {
    enum AbsoluteTimeStyle {
        case hourMinute
        case hourMinuteSecond
        case weekdayHourMinute
    }

    /// `Date.FormatStyle` (`.formatted(...)`) returns an EMPTY string under region-override
    /// locales such as `en_CA@rg=czzzzz` (language English-Canada, region Czechia) — a common
    /// macOS setup. `DateFormatter` with `setLocalizedDateFormatFromTemplate` does not have this
    /// bug and correctly honours the region override. Do not "modernise" this back to
    /// `Date.FormatStyle` — it will silently blank out every absolute time shown to the user.
    nonisolated static func absoluteTime(_ date: Date, _ style: AbsoluteTimeStyle) -> String {
        let template: String
        switch style {
        case .hourMinute: template = "jmm"
        case .hourMinuteSecond: template = "jmmss"
        // Weekday and time, no date and deliberately no year. Usage windows run at most seven
        // days, so the year was never information, and with it the stats row overflowed its width in
        // every locale tested (cs 187 pt, de 212 pt, en 230 pt against 166 pt available).
        case .weekdayHourMinute: template = "Ejmm"
        }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

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

    /// When `analysis.events` is non-empty, the most recent credit's description is appended
    /// so the row explains why the graph shows a drop that is not a window boundary.
    static func statsLabelText(analysis: WindowAnalysis, now: Date) -> String {
        let base = statsLabelTextCore(analysis: analysis, now: now)
        guard let mostRecent = analysis.events.max(by: { $0.at < $1.at }) else { return base }
        let credit = creditDescription(for: mostRecent)
        return base.isEmpty ? credit : "\(base) · \(credit)"
    }

    /// Factual, short description of a single usage-credit event — e.g. "usage credit: 32% →
    /// 0%" — never invents a reason Anthropic granted it.
    static func creditDescription(for event: UsageEvent) -> String {
        String(format: String(localized: "graph.credit.description", bundle: .module), event.from, event.to)
    }

    private static func statsLabelTextCore(analysis: WindowAnalysis, now: Date) -> String {
        let util = analysis.entry.window.utilization
        guard let resetsAt = analysis.entry.window.resetsAt else { return "" }

        if util >= 100 {
            let isToday = Calendar.current.isDateInToday(resetsAt)
            let key = isToday ? "graph.stats.blocked" : "graph.stats.blocked_date"
            let timeStr = absoluteTime(resetsAt, isToday ? .hourMinute : .weekdayHourMinute)
            return String(format: String(localized: String.LocalizationValue(key), bundle: .module), timeStr)
        }

        guard analysis.rateSource != .insufficient else {
            return String(localized: "graph.stats.collecting", bundle: .module)
        }

        guard analysis.consumptionRate != 0 else {
            return String(format: String(localized: "graph.stats.idle", bundle: .module), 100 - util)
        }

        let rateStr = Formatting.formatRate(analysis.consumptionRate)

        guard analysis.projectedAtReset >= 100 else {
            return String(format: String(localized: "graph.stats.projected", bundle: .module), rateStr, Int(analysis.projectedAtReset.rounded()))
        }

        guard let ttl = analysis.timeToLimit else {
            return String(format: String(localized: "graph.stats.limit_unknown", bundle: .module), rateStr)
        }

        // The clock time the limit is reached, and nothing else. The previous wording — "hits limit
        // ~9h 2m before reset (at 17:44)" — was both too long for the row and misleading twice over:
        // the duration was the margin ahead of the reset rather than the time remaining, and the
        // bracketed time reads as the reset when it is actually when the limit lands. How long the
        // window has left is already on screen in the usage rows above.
        let limitHitAt = now.addingTimeInterval(ttl)
        let isToday = Calendar.current.isDateInToday(limitHitAt)
        let key = isToday ? "graph.stats.limit_at" : "graph.stats.limit_at_date"
        let timeStr = absoluteTime(limitHitAt, isToday ? .hourMinute : .weekdayHourMinute)
        return String(format: String(localized: String.LocalizationValue(key), bundle: .module), rateStr, timeStr)
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
