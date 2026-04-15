import Foundation

extension Formatting {
    enum UsageLevel: Int, Sendable, Equatable, Comparable {
        case normal = 0
        case warning = 1
        case critical = 2

        static func < (lhs: UsageLevel, rhs: UsageLevel) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    struct UsageStyle: Sendable, Equatable, Comparable {
        let level: UsageLevel
        let isBold: Bool
        var isCritical: Bool { level == .critical }

        static func < (lhs: UsageStyle, rhs: UsageStyle) -> Bool {
            if lhs.level != rhs.level { return lhs.level < rhs.level }
            return !lhs.isBold && rhs.isBold
        }
    }

    // MARK: - usageStyle (original signature, projection-based logic)

    static func usageStyle(
        utilization: Int,
        resetsAt: Date?,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> UsageStyle {
        if utilization >= Constants.Projection.blockedUtilization {
            return UsageStyle(level: .critical, isBold: true)
        }
        guard let resetsAt else {
            return usageStyleFallback(utilization: utilization)
        }
        let timeRemaining = max(resetsAt.timeIntervalSince(now), 0)
        if timeRemaining <= 0 {
            return UsageStyle(level: .normal, isBold: false)
        }
        let timeElapsed = windowDuration - timeRemaining
        let impliedRate = timeElapsed > 0 ? Double(utilization) / timeElapsed : 0
        let projectedAtReset = Double(utilization) + impliedRate * timeRemaining
        return usageStyle(projectedAtReset: projectedAtReset, utilization: utilization, resetsAt: resetsAt, timeRemaining: timeRemaining)
    }

    // MARK: - usageStyle overload accepting pre-computed projection

    static func usageStyle(
        projectedAtReset: Double,
        utilization: Int,
        resetsAt: Date?,
        timeRemaining: TimeInterval
    ) -> UsageStyle {
        if utilization >= Constants.Projection.blockedUtilization {
            return UsageStyle(level: .critical, isBold: true)
        }
        guard resetsAt != nil else {
            return usageStyleFallback(utilization: utilization)
        }
        if timeRemaining <= 0 {
            return UsageStyle(level: .normal, isBold: false)
        }
        if projectedAtReset >= Constants.Projection.criticalThreshold {
            return UsageStyle(level: .critical, isBold: true)
        }
        if projectedAtReset >= Constants.Projection.warningThreshold {
            return UsageStyle(level: .warning, isBold: true)
        }
        if projectedAtReset >= Constants.Projection.boldThreshold {
            return UsageStyle(level: .normal, isBold: true)
        }
        return UsageStyle(level: .normal, isBold: false)
    }

    private static func usageStyleFallback(utilization: Int) -> UsageStyle {
        if utilization >= Constants.Projection.fallbackCriticalThreshold {
            return UsageStyle(level: .critical, isBold: true)
        }
        if utilization >= Constants.Projection.fallbackWarningThreshold {
            return UsageStyle(level: .warning, isBold: true)
        }
        if utilization >= Constants.Projection.fallbackBoldThreshold {
            return UsageStyle(level: .normal, isBold: true)
        }
        return UsageStyle(level: .normal, isBold: false)
    }

    // MARK: - shouldShowInMenuBar (original signature, projection-based logic)

    static func shouldShowInMenuBar(
        utilization: Int,
        resetsAt: Date?,
        windowDuration: TimeInterval,
        now: Date = Date()
    ) -> Bool {
        guard let resetsAt else { return false }
        let timeRemaining = max(resetsAt.timeIntervalSince(now), 0)
        if timeRemaining <= 0 { return false }
        let timeElapsed = windowDuration - timeRemaining
        let impliedRate = timeElapsed > 0 ? Double(utilization) / timeElapsed : 0
        let projectedAtReset = Double(utilization) + impliedRate * timeRemaining
        return shouldShowInMenuBar(projectedAtReset: projectedAtReset)
    }

    // MARK: - shouldShowInMenuBar overload accepting pre-computed projection

    static func shouldShowInMenuBar(projectedAtReset: Double) -> Bool {
        projectedAtReset >= Constants.Projection.boldThreshold
    }

    // MARK: - Unchanged functions

    static func blockingLimit(_ usage: UsageResponse?) -> Date? {
        guard let usage else { return nil }
        return usage.entries
            .filter { $0.window.utilization >= 100 }
            .compactMap(\.window.resetsAt)
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
