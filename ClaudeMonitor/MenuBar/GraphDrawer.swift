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

    /// Mid-window usage credit events for the selected window (see `UsageEvent`) — carried by
    /// the selected `WindowAnalysis` itself.
    var events: [UsageEvent] {
        guard selectedIndex < analyses.count else { return [] }
        return analyses[selectedIndex].events
    }

    enum Layout {
        static let graphHeight: CGFloat = 280
        static let statsHeight: CGFloat = 20
        static let topPadding: CGFloat = 14
        /// Space between the graph and the stats row below it. The graph draws its own labels flush
        /// against its bottom edge — "now" sits 1 pt from it and the 0% axis label 2 pt — so a small
        /// gap here left roughly 8 pt between two lines of live text and read as a collision rather
        /// than as two separate rows.
        static let graphStatsGap: CGFloat = 14
        /// Keeps the stats row off the separator that follows it.
        static let bottomPadding: CGFloat = 4
        static let sidePadding: CGFloat = 12
        static let defaultWidth: CGFloat = 280
        /// Width the energy label starts with, before there is a reading to measure. Once a reading
        /// exists the label shrinks to fit it exactly and hands the slack to the stats text — see
        /// `UsageGraphView.layoutStatsRow`. A fixed reserve was the wrong shape here: it has to be
        /// sized for the widest reading in the widest language, and every point of it is taken from
        /// the stats text, which is the part that actually runs long (Croatian overflowed by 1.8 pt
        /// with an 84 pt reserve).
        static let energyLabelWidth: CGFloat = 84
        /// Ceiling on the energy label, so an absurd reading can never swallow the stats text.
        static let energyLabelMaxWidth: CGFloat = 110
        /// Gap between the stats text and the energy estimate, so a long stats line stops short of
        /// the number rather than running into it.
        static let statsEnergyGap: CGFloat = 6
        static let totalHeight: CGFloat = topPadding + graphHeight + graphStatsGap + statsHeight + bottomPadding
        static let noDataHeight: CGFloat = 0
        static let currentDotRadius: CGFloat = 2.5
        static let yAxisLabelBgPadding: CGFloat = 2
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
        // A distinct dash pattern (finer/denser than inferred [2,2], projection/gap [4,3],
        // and sustainable-pace [3,3]) plus a dedicated color (systemPurple — unused by any
        // other decoration) so a mid-window usage credit can never be mistaken for a window
        // boundary, a gap, or a projection/threshold line. systemPurple is a dynamic system
        // catalog color, matching the existing pattern (systemBlue/systemRed/systemOrange)
        // for automatic light/dark appearance adaptation.
        static let creditColor: NSColor = .systemPurple
        static let creditLineDashPattern: [CGFloat] = [1, 2]
        static let creditLineWidth: CGFloat = 1
        static let creditLineAlpha: CGFloat = 0.6
        static let creditStepWidth: CGFloat = 2
        static let creditDotRadius: CGFloat = 3
    }

    /// The graph's x-axis domain: exactly the window's own duration, ending at `resetsAt`.
    ///
    /// Deliberately does NOT widen to include samples that fall outside the window — a stored
    /// sample predating `resetsAt - duration` (a data-layer window-boundary-detection question,
    /// tracked separately) must never stretch the axis backwards. Doing so was the reported
    /// defect: a 5-hour window's axis measured 7.5 hours because of a single pre-window sample,
    /// which misplaced "now" at 40% of the axis instead of the correct 10%.
    nonisolated static func timeRange(resetsAt: Date, duration: TimeInterval) -> ClosedRange<Date> {
        resetsAt.addingTimeInterval(-duration)...resetsAt
    }

    /// Filters a tracked/inferred segment's samples down to the ones that actually fall inside
    /// `timeRange`. `xPosition`/`yPosition` saturate at the rect edges, so plotting an
    /// out-of-domain sample unfiltered does not extend the curve off-screen — it silently
    /// relocates that sample's real value onto `rect.minX`/`rect.maxX` as though it had been
    /// observed at the window's own start. On the user's real data this produced a false
    /// anchor point at 0% glued to `windowStart` (from samples recorded hours earlier, while
    /// idle, before the window existed), dragging a curve down to it that the user never
    /// actually experienced inside the window; with more varied pre-window values it would
    /// instead stack multiple distinct utilizations onto that same edge x-coordinate. Filtering
    /// first means a segment straddling the domain boundary simply starts (or ends) at its
    /// first (or last) genuinely in-window sample — never fabricated, never collapsed onto an
    /// edge. `buildSegmentPaths` already degrades safely (empty paths) when fewer than 2
    /// samples remain.
    nonisolated static func plottableSamples(_ samples: [UtilizationSample], in timeRange: ClosedRange<Date>) -> [UtilizationSample] {
        samples.filter { timeRange.contains($0.timestamp) }
    }

    /// A gap segment (`SampleSegment.kind == .gap`) clipped to `timeRange`. `hatchStart`/
    /// `hatchEnd` are always in-domain and always present when the gap is visible at all —
    /// a gap means "the app was not running," and that remains true up to the window's own
    /// edge even when the recorded `before`/`after` sample lies outside it, so the hatch is
    /// drawn from the domain edge. `line` is the sloped dashed marker connecting the two real
    /// sample values, and is present ONLY when both samples are themselves inside the domain:
    /// drawing it from an edge would plot an out-of-domain sample's utilization as though it
    /// had been observed at `windowStart`/`resetsAt`, which it was not. This deliberately does
    /// NOT fabricate a sample at the edge to anchor the line — the project's rule is that a
    /// gap is a discontinuity, never an interpolation.
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

    /// Returns `nil` when the gap is entirely outside `timeRange` (nothing to draw); otherwise
    /// the clipped hatch bounds and, when both endpoints are in-domain, the dashed line.
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
