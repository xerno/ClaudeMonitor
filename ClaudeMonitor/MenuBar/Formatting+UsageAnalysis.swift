import AppKit

extension Formatting {
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
            return UsageStyle(color: colorForThresholds(isRed: isRed, isOrange: isOrange), isBold: isBold, isCritical: isRed)
        }

        let timeRemaining = max(resetsAt.timeIntervalSince(now), 0)
        let timeElapsedPercent = (1 - timeRemaining / windowDuration) * 100

        let isRed = utilization >= 80 || Double(utilization) > timeElapsedPercent + 35
        let isOrange = utilization >= 70 || Double(utilization) > timeElapsedPercent + 20
        let isBold = utilization >= 50 || Double(utilization) > timeElapsedPercent

        return UsageStyle(color: colorForThresholds(isRed: isRed, isOrange: isOrange), isBold: isBold, isCritical: isRed)
    }

    private static func colorForThresholds(isRed: Bool, isOrange: Bool) -> NSColor {
        if isRed { return .systemRed }
        if isOrange { return .systemOrange }
        return .labelColor
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

    static func blockingLimit(_ usage: UsageResponse?) -> Date? {
        guard let usage else { return nil }
        return usage.allWindows
            .filter { $0.utilization >= 100 }
            .compactMap(\.resetsAt)
            .max()
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
}
