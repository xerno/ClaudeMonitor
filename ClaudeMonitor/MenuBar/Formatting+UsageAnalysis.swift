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
        guard let projection = computeProjection(
            utilization: utilization,
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            now: now
        ) else {
            return UsageStyle(level: .normal, isBold: false)
        }
        return usageStyle(projectedAtReset: projection.projectedAtReset, utilization: utilization, resetsAt: resetsAt, timeRemaining: projection.timeRemaining)
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

    private static func computeProjection(
        utilization: Int,
        resetsAt: Date,
        windowDuration: TimeInterval,
        now: Date
    ) -> (projectedAtReset: Double, timeRemaining: TimeInterval)? {
        let timeRemaining = max(resetsAt.timeIntervalSince(now), 0)
        guard timeRemaining > 0 else { return nil }
        let timeElapsed = windowDuration - timeRemaining
        let impliedRate = timeElapsed > 0 ? Double(utilization) / timeElapsed : 0
        let projectedAtReset = Double(utilization) + impliedRate * timeRemaining
        return (projectedAtReset, timeRemaining)
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
        guard let projection = computeProjection(
            utilization: utilization,
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            now: now
        ) else { return false }
        return shouldShowInMenuBar(projectedAtReset: projection.projectedAtReset)
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

    static func detectCriticalReset(previous: UsageResponse, current: UsageResponse, now: Date = Date()) -> Bool {
        let previousByKey = Dictionary(uniqueKeysWithValues: previous.entries.map { ($0.key, $0) })
        for currEntry in current.entries {
            guard let prevEntry = previousByKey[currEntry.key] else { continue }
            let prev = prevEntry.window
            let curr = currEntry.window
            guard let prevReset = prev.resetsAt, let currReset = curr.resetsAt else { continue }
            guard currReset.timeIntervalSince(prevReset) > currEntry.duration / 2 else { continue }
            if usageStyle(
                utilization: prev.utilization,
                resetsAt: prev.resetsAt,
                windowDuration: currEntry.duration,
                now: now
            ).isCritical {
                return true
            }
        }
        return false
    }

}
