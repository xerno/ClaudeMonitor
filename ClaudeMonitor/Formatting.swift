import AppKit

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

    static func blockingLimit(_ usage: UsageResponse?) -> Date? {
        guard let usage else { return nil }
        let windows: [UsageWindow?] = [usage.fiveHour, usage.sevenDay, usage.sevenDaySonnet]
        let blockedResets = windows.compactMap { w -> Date? in
            guard let w, w.utilization >= 100, let resetsAt = w.resetsAt else { return nil }
            return resetsAt
        }
        return blockedResets.max()
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

        if intervalSize == 3600 && nextCenter < 90000 {
            nextCenter = 90000 - 30
        } else if intervalSize == 60 && nextCenter < 120 {
            nextCenter = 120 - 0.5
        }

        guard nextCenter > 0 else {
            return resetTime.addingTimeInterval(-0.5)
        }
        return resetTime.addingTimeInterval(-nextCenter)
    }

    static func progressBar(percent: Int, width: Int = 10) -> String {
        let clamped = min(max(percent, 0), 100)
        let filled = Int(round(Double(clamped) / 100.0 * Double(width)))
        return String(repeating: "█", count: filled) + String(repeating: "░", count: width - filled)
    }

    struct UsageStyle {
        let color: NSColor
        let isBold: Bool
    }

    static func usageStyle(
        utilization: Int,
        resetsAt: Date?,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> UsageStyle {
        guard let resetsAt else {
            let isRed = utilization >= 80
            let isOrange = utilization >= 70
            let isBold = utilization >= 50
            let color: NSColor
            if isRed { color = .systemRed }
            else if isOrange { color = .systemOrange }
            else { color = .labelColor }
            return UsageStyle(color: color, isBold: isBold)
        }

        let timeRemaining = max(resetsAt.timeIntervalSince(now), 0)
        let timeElapsedPercent = (1 - timeRemaining / windowDuration) * 100

        let isRed = utilization >= 80 || Double(utilization) > timeElapsedPercent + 35
        let isOrange = utilization >= 70 || Double(utilization) > timeElapsedPercent + 20
        let isBold = utilization >= 50 || Double(utilization) > timeElapsedPercent

        let color: NSColor
        if isRed { color = .systemRed }
        else if isOrange { color = .systemOrange }
        else { color = .labelColor }

        return UsageStyle(color: color, isBold: isBold)
    }

    static func shouldShowInMenuBar(
        utilization: Int,
        resetsAt: Date?,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard let resetsAt else { return false }
        let timeRemaining = max(resetsAt.timeIntervalSince(now), 0)
        let timeElapsedPercent = (1 - timeRemaining / windowDuration) * 100
        let hasFormatting = usageStyle(
            utilization: utilization, resetsAt: resetsAt,
            windowDuration: windowDuration, now: now
        ).isBold
        return hasFormatting && Double(utilization) > timeElapsedPercent
    }

    static func hasAnyCriticalWindow(_ usage: UsageResponse) -> Bool {
        func isCritical(_ window: UsageWindow?, duration: TimeInterval) -> Bool {
            guard let w = window else { return false }
            return usageStyle(
                utilization: w.utilization, resetsAt: w.resetsAt, windowDuration: duration
            ).color == .systemRed
        }
        return isCritical(usage.fiveHour, duration: Constants.UsageWindows.fiveHourDuration)
            || isCritical(usage.sevenDay, duration: Constants.UsageWindows.sevenDayDuration)
            || isCritical(usage.sevenDaySonnet, duration: Constants.UsageWindows.sevenDayDuration)
    }

    static func buildTooltip(state: MonitorState) -> String {
        var sections: [[String]] = []

        var usageLines: [String] = []
        if !state.hasCredentials {
            usageLines.append(String(localized: "tooltip.usage.configure"))
        } else if let error = state.usageError {
            usageLines.append(String(format: String(localized: "tooltip.usage.error"), error))
        } else if let usage = state.currentUsage {
            if let w = usage.fiveHour {
                if let resetsAt = w.resetsAt {
                    usageLines.append(String(format: String(localized: "tooltip.window.5h.resets"), w.utilization, timeUntil(resetsAt)))
                } else {
                    usageLines.append(String(format: String(localized: "tooltip.window.5h"), w.utilization))
                }
            }
            if let w = usage.sevenDay {
                if let resetsAt = w.resetsAt {
                    usageLines.append(String(format: String(localized: "tooltip.window.7d.resets"), w.utilization, timeUntil(resetsAt)))
                } else {
                    usageLines.append(String(format: String(localized: "tooltip.window.7d"), w.utilization))
                }
            }
            if let w = usage.sevenDaySonnet {
                if let resetsAt = w.resetsAt {
                    usageLines.append(String(format: String(localized: "tooltip.window.sonnet.resets"), w.utilization, timeUntil(resetsAt)))
                } else {
                    usageLines.append(String(format: String(localized: "tooltip.window.sonnet"), w.utilization))
                }
            }
        } else {
            usageLines.append(String(localized: "tooltip.usage.loading"))
        }
        sections.append(usageLines)

        var statusLines: [String] = []
        if let error = state.statusError {
            statusLines.append(String(format: String(localized: "tooltip.status.error"), error))
        } else if let status = state.currentStatus {
            let affected = status.components.filter { $0.status >= .degradedPerformance }
            for c in affected {
                statusLines.append("\(c.status.dot) \(c.name): \(c.status.label)")
            }
            for incident in status.incidents {
                statusLines.append("⚠ \(incident.name)")
            }
            if affected.isEmpty && status.incidents.isEmpty {
                statusLines.append(String(localized: "tooltip.status.ok"))
            }
        } else {
            statusLines.append(String(localized: "tooltip.status.loading"))
        }
        sections.append(statusLines)

        if let date = state.lastRefreshed {
            sections.append([String(format: String(localized: "tooltip.updated"),
                                    date.formatted(.dateTime.hour().minute().second()))])
        }

        return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}
