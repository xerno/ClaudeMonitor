import AppKit

struct GraphDrawer {
    let analyses: [WindowAnalysis]
    let selectedIndex: Int
    let graphRect: CGRect
    let now: Date

    init(analyses: [WindowAnalysis], selectedIndex: Int, graphRect: CGRect, now: Date) {
        self.analyses = analyses
        self.selectedIndex = selectedIndex
        self.graphRect = graphRect
        self.now = now
    }

    var events: [UsageEvent] {
        guard selectedIndex < analyses.count else { return [] }
        return analyses[selectedIndex].events
    }

    enum Layout {
        static let graphHeight: CGFloat = 280
        static let statsHeight: CGFloat = 20
        static let topPadding: CGFloat = 14
        /// The graph's own labels sit 1-2 pt from its bottom edge, so a small gap reads as two colliding lines.
        static let graphStatsGap: CGFloat = 14
        /// Keeps the stats row off the separator that follows it.
        static let bottomPadding: CGFloat = 4
        static let sidePadding: CGFloat = 12
        static let defaultWidth: CGFloat = 280
        /// Initial width, before a reading exists to measure; `UsageGraphView.layoutStatsRow` then fits it.
        static let energyLabelWidth: CGFloat = 84
        /// Stops a long reading from swallowing the stats text.
        static let energyLabelMaxWidth: CGFloat = 110
        static let statsEnergyGap: CGFloat = 6
        static let totalHeight: CGFloat = topPadding + graphHeight + graphStatsGap + statsHeight + bottomPadding
        static let noDataHeight: CGFloat = 0
        static let currentDotRadius: CGFloat = 2.5
        /// Percent of the font size, not points.
        static let labelHaloStrokeWidth: CGFloat = 30
        static let yAxisLabelInset: CGFloat = 2
        static let nowLabelBottomGap: CGFloat = 1
        static let projectionLabelOffset: CGFloat = 3
        static let projectionLabelFontSize: CGFloat = 11
        static let trackedFillAlpha: CGFloat = 0.15
        static let trackedStrokeAlpha: CGFloat = 0.7
        static let trackedStrokeWidth: CGFloat = 1.5
        static let inferredFillAlpha: CGFloat = 0.07
        static let inferredStrokeAlpha: CGFloat = 0.5
        static let inferredStrokeWidth: CGFloat = 1.5
        static let inferredDashPattern: [CGFloat] = [2, 2]
        static let projectionDashPattern: [CGFloat] = [4, 3]
        static let projectionStrokeWidth: CGFloat = 1.5
        static let projectionFillAlpha: CGFloat = 0.06
        static let blockedZoneFillAlpha: CGFloat = 0.08
        static let limitLineAlpha: CGFloat = 0.4
        static let sustainablePaceAlpha: CGFloat = 0.3
        static let sustainablePaceDashPattern: [CGFloat] = [3, 3]
        static let gridLineAlpha: CGFloat = 0.1
        static let nowMarkerAlpha: CGFloat = 0.4
        static let gapHatchAlpha: CGFloat = 0.15
        static let gapHatchSpacing: CGFloat = 6
        static let gapDashPattern: [CGFloat] = [4, 3]

        // MARK: - Credit events
        // Dash pattern and colour are used by no other decoration, so a credit can't be mistaken for a
        // window boundary, gap, projection or threshold line.
        static let creditColor: NSColor = .systemPurple
        static let creditLineDashPattern: [CGFloat] = [1, 2]
        static let creditLineWidth: CGFloat = 1
        static let creditLineAlpha: CGFloat = 0.6
        static let creditStepWidth: CGFloat = 2
        static let creditDotRadius: CGFloat = 3
    }

    /// The window's own duration ending at `resetsAt`. Never widened to fit out-of-window samples:
    /// a stray pre-window sample would stretch the axis backwards and misplace "now".
    nonisolated static func timeRange(resetsAt: Date, duration: TimeInterval) -> ClosedRange<Date> {
        resetsAt.addingTimeInterval(-duration)...resetsAt
    }

    /// `xPosition` clamps to the rect edges, so an out-of-domain sample would be plotted on the edge
    /// as though observed at the window's start or reset. Filter first.
    nonisolated static func plottableSamples(_ samples: [UtilizationSample], in timeRange: ClosedRange<Date>) -> [UtilizationSample] {
        samples.filter { timeRange.contains($0.timestamp) }
    }

    /// `line` exists only when both samples are in-domain: anchoring it at an edge would plot an
    /// out-of-domain value as observed there. No edge sample is fabricated; a gap is a discontinuity.
    struct ClippedGap: Equatable {
        let hatchStart: Date
        let hatchEnd: Date
        let line: (before: UtilizationSample, after: UtilizationSample)?

        static func == (lhs: ClippedGap, rhs: ClippedGap) -> Bool {
            guard lhs.hatchStart == rhs.hatchStart, lhs.hatchEnd == rhs.hatchEnd else { return false }
            switch (lhs.line, rhs.line) {
            case (nil, nil): return true
            case let (l?, r?): return l.before == r.before && l.after == r.after
            default: return false
            }
        }
    }

    nonisolated static func clipGapSegment(
        before: UtilizationSample, after: UtilizationSample, in timeRange: ClosedRange<Date>
    ) -> ClippedGap? {
        guard after.timestamp > timeRange.lowerBound, before.timestamp < timeRange.upperBound else { return nil }
        let beforeInDomain = timeRange.contains(before.timestamp)
        let afterInDomain = timeRange.contains(after.timestamp)
        let hatchStart = beforeInDomain ? before.timestamp : timeRange.lowerBound
        let hatchEnd = afterInDomain ? after.timestamp : timeRange.upperBound
        let line = (beforeInDomain && afterInDomain) ? (before, after) : nil
        return ClippedGap(hatchStart: hatchStart, hatchEnd: hatchEnd, line: line)
    }

    func draw() {
        guard selectedIndex < analyses.count else { return }
        let analysis = analyses[selectedIndex]
        guard let resetsAt = analysis.entry.window.resetsAt else { return }

        let timeRange = Self.timeRange(resetsAt: resetsAt, duration: analysis.entry.duration)

        let currentUtil = Double(analysis.entry.window.utilization)

        drawGrid(in: graphRect)
        drawLimitLine(in: graphRect)
        drawSustainablePaceLine(in: graphRect, timeRange: timeRange, now: now, resetsAt: resetsAt, currentUtil: currentUtil)
        drawSegments(segments: analysis.segments, in: graphRect, timeRange: timeRange, now: now, currentUtil: currentUtil)
        drawProjection(in: graphRect, timeRange: timeRange, now: now, resetsAt: resetsAt, currentUtil: currentUtil, analysis: analysis)
        drawCreditEvents(in: graphRect, timeRange: timeRange)
        drawNowMarker(in: graphRect, timeRange: timeRange, now: now)
        drawCurrentDot(in: graphRect, timeRange: timeRange, now: now, currentUtil: currentUtil)
        drawYAxisLabels(in: graphRect)
    }

    // MARK: - Coordinate Helpers

    func xPosition(for date: Date, in rect: NSRect, timeRange: ClosedRange<Date>) -> CGFloat {
        let total = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound)
        guard total > 0 else { return rect.minX }
        let elapsed = date.timeIntervalSince(timeRange.lowerBound)
        let fraction = max(0, min(1, elapsed / total))
        return rect.minX + fraction * rect.width
    }

    func yPosition(for utilization: Double, in rect: NSRect) -> CGFloat {
        let fraction = max(0, min(1, utilization / 100.0))
        return rect.maxY - fraction * rect.height
    }

    // MARK: - Color Helper

    func color(for style: Formatting.UsageStyle) -> NSColor {
        switch style.level {
        case .normal: return style.isBold ? .labelColor : .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }
}
