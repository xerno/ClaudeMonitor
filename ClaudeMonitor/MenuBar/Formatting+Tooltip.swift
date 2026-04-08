import Foundation

extension Formatting {
    static func buildTooltip(state: MonitorState) -> String {
        var sections: [[String]] = []
        sections.append(tooltipUsageLines(state: state))
        sections.append(tooltipStatusLines(state: state))
        if let lines = tooltipTimestampLines(state: state) {
            sections.append(lines)
        }
        return sections.map { $0.joined(separator: "\n") }.joined(separator: "\n\n")
    }

    private static func tooltipUsageLines(state: MonitorState) -> [String] {
        if !state.hasCredentials {
            return [String(localized: "tooltip.usage.configure", bundle: .module)]
        }
        if let error = state.usageError {
            return [String(format: String(localized: "tooltip.usage.error", bundle: .module), error)]
        }
        guard let usage = state.currentUsage else {
            return [String(localized: "tooltip.usage.loading", bundle: .module)]
        }
        return usage.entries.map { entry in
            let label = Formatting.displayLabel(for: entry, in: usage)
            let w = entry.window
            if let resetsAt = w.resetsAt {
                return String(
                    format: String(localized: "tooltip.window.resets", bundle: .module),
                    label, w.utilization, timeUntil(resetsAt)
                )
            } else {
                return String(
                    format: String(localized: "tooltip.window", bundle: .module),
                    label, w.utilization
                )
            }
        }
    }

    private static func tooltipStatusLines(state: MonitorState) -> [String] {
        if let error = state.statusError {
            return [String(format: String(localized: "tooltip.status.error", bundle: .module), error)]
        }
        guard let status = state.currentStatus else {
            return [String(localized: "tooltip.status.loading", bundle: .module)]
        }
        var lines: [String] = []
        let affected = status.components.filter { $0.status >= .degradedPerformance }
        for c in affected {
            lines.append("\(c.status.dot) \(c.name): \(c.status.label)")
        }
        for incident in status.incidents {
            lines.append("⚠ \(incident.name)")
        }
        if affected.isEmpty && status.incidents.isEmpty {
            lines.append(String(localized: "tooltip.status.ok", bundle: .module))
        }
        return lines
    }

    private static func tooltipTimestampLines(state: MonitorState) -> [String]? {
        guard let date = state.lastRefreshed else { return nil }
        var lines = [String(format: String(localized: "tooltip.updated", bundle: .module),
                            date.formatted(.dateTime.hour().minute().second()))]
        if let interval = state.currentPollInterval {
            lines.append(String(format: String(localized: "menu.interval", bundle: .module),
                                Formatting.formatInterval(interval)))
            let nextDate = date.addingTimeInterval(interval)
            lines.append(String(format: String(localized: "menu.next", bundle: .module),
                                nextDate.formatted(.dateTime.hour().minute().second())))
        }
        return lines
    }
}
