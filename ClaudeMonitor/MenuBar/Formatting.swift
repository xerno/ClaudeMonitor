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

    static func blockingLimit(_ usage: UsageResponse?) -> Date? {
        guard let usage else { return nil }
        return usage.allWindows
            .filter { $0.utilization >= 100 }
            .compactMap(\.resetsAt)
            .max()
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

        // Snap to just before zone transitions (25h = days↔hours, 2m = minutes↔seconds)
        if intervalSize == 3600 && nextCenter < 25 * 3600 {
            nextCenter = 25 * 3600 - 30
        } else if intervalSize == 60 && nextCenter < 2 * 60 {
            nextCenter = 2 * 60 - 0.5
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

    struct UsageStyle {
        let color: NSColor
        let isBold: Bool
        let isCritical: Bool
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
            return UsageStyle(color: color, isBold: isBold, isCritical: isRed)
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

        return UsageStyle(color: color, isBold: isBold, isCritical: isRed)
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
        return Double(utilization) > timeElapsedPercent
    }

    static func detectCriticalReset(previous: UsageResponse, current: UsageResponse) -> Bool {
        for currEntry in current.entries {
            guard let prevEntry = previous.entries.first(where: { $0.key == currEntry.key }) else { continue }
            let prev = prevEntry.window
            let curr = currEntry.window
            guard let prevReset = prev.resetsAt, let currReset = curr.resetsAt else { continue }
            guard currReset.timeIntervalSince(prevReset) > currEntry.duration / 2 else { continue }
            if usageStyle(
                utilization: prev.utilization,
                resetsAt: prev.resetsAt,
                windowDuration: currEntry.duration
            ).isCritical {
                return true
            }
        }
        return false
    }

    static func hasAnyCriticalWindow(_ usage: UsageResponse) -> Bool {
        usage.entries.contains { entry in
            usageStyle(
                utilization: entry.window.utilization,
                resetsAt: entry.window.resetsAt,
                windowDuration: entry.duration
            ).isCritical
        }
    }

    static func buildTooltip(state: MonitorState) -> String {
        var sections: [[String]] = []

        var usageLines: [String] = []
        if !state.hasCredentials {
            usageLines.append(String(localized: "tooltip.usage.configure", bundle: .module))
        } else if let error = state.usageError {
            usageLines.append(String(format: String(localized: "tooltip.usage.error", bundle: .module), error))
        } else if let usage = state.currentUsage {
            for entry in usage.entries {
                let label = Formatting.displayLabel(for: entry, in: usage)
                let w = entry.window
                if let resetsAt = w.resetsAt {
                    usageLines.append(String(
                        format: String(localized: "tooltip.window.resets", bundle: .module),
                        label, w.utilization, timeUntil(resetsAt)
                    ))
                } else {
                    usageLines.append(String(
                        format: String(localized: "tooltip.window", bundle: .module),
                        label, w.utilization
                    ))
                }
            }
        } else {
            usageLines.append(String(localized: "tooltip.usage.loading", bundle: .module))
        }
        sections.append(usageLines)

        var statusLines: [String] = []
        if let error = state.statusError {
            statusLines.append(String(format: String(localized: "tooltip.status.error", bundle: .module), error))
        } else if let status = state.currentStatus {
            let affected = status.components.filter { $0.status >= .degradedPerformance }
            for c in affected {
                statusLines.append("\(c.status.dot) \(c.name): \(c.status.label)")
            }
            for incident in status.incidents {
                statusLines.append("⚠ \(incident.name)")
            }
            if affected.isEmpty && status.incidents.isEmpty {
                statusLines.append(String(localized: "tooltip.status.ok", bundle: .module))
            }
        } else {
            statusLines.append(String(localized: "tooltip.status.loading", bundle: .module))
        }
        sections.append(statusLines)

        if let date = state.lastRefreshed {
            var lines = [String(format: String(localized: "tooltip.updated", bundle: .module),
                                date.formatted(.dateTime.hour().minute().second()))]
            if let interval = state.currentPollInterval {
                lines.append(String(format: String(localized: "menu.interval", bundle: .module),
                                    Formatting.formatInterval(interval)))
                let nextDate = date.addingTimeInterval(interval)
                lines.append(String(format: String(localized: "menu.next", bundle: .module),
                                    nextDate.formatted(.dateTime.hour().minute().second())))
            }
            sections.append(lines)
        }

        return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }
}
