import AppKit

enum Formatting {
    static func timeUntil(_ date: Date, now: Date = Date()) -> String {
        let diff = max(date.timeIntervalSince(now), 0)
        let totalMinutes = Int(diff / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours >= 24 { return "in \(hours / 24)d \(hours % 24)h" }
        if hours > 0 { return "in \(hours)h \(minutes)m" }
        return "in \(minutes)m"
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
        resetsAt: Date,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> UsageStyle {
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
        resetsAt: Date,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> Bool {
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
            usageLines.append("Usage: configure credentials in Preferences")
        } else if let error = state.usageError {
            usageLines.append("⚠ Usage: \(error)")
        } else if let usage = state.currentUsage {
            if let w = usage.fiveHour {
                usageLines.append("5h window: \(w.utilization)% (resets \(timeUntil(w.resetsAt)))")
            }
            if let w = usage.sevenDay {
                usageLines.append("7d window: \(w.utilization)% (resets \(timeUntil(w.resetsAt)))")
            }
            if let w = usage.sevenDaySonnet {
                usageLines.append("7d Sonnet: \(w.utilization)% (resets \(timeUntil(w.resetsAt)))")
            }
        } else {
            usageLines.append("Usage: loading…")
        }
        sections.append(usageLines)

        var statusLines: [String] = []
        if let error = state.statusError {
            statusLines.append("⚠ Status: \(error)")
        } else if let status = state.currentStatus {
            let affected = status.components.filter { $0.status >= .degradedPerformance }
            for c in affected {
                statusLines.append("\(c.status.dot) \(c.name): \(c.status.label)")
            }
            for incident in status.incidents {
                statusLines.append("⚠ \(incident.name)")
            }
            if affected.isEmpty && status.incidents.isEmpty {
                statusLines.append("✓ All systems operational")
            }
        } else {
            statusLines.append("Status: loading…")
        }
        sections.append(statusLines)

        if let date = state.lastRefreshed {
            sections.append(["Updated: \(date.formatted(.dateTime.hour().minute().second()))"])
        }

        return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}
