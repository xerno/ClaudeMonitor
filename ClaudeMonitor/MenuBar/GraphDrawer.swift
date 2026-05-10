import AppKit

struct GraphDrawer {
    let analyses: [WindowAnalysis]
    let selectedIndex: Int
    let graphRect: CGRect
    let now: Date

    enum Layout {
        static let graphHeight: CGFloat = 280
        static let statsHeight: CGFloat = 20
        static let topPadding: CGFloat = 14
        static let graphStatsGap: CGFloat = 6
        static let bottomPadding: CGFloat = 0
        static let sidePadding: CGFloat = 12
        static let defaultWidth: CGFloat = 280
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
    }

    func draw() {
        guard selectedIndex < analyses.count else { return }
        let analysis = analyses[selectedIndex]
        guard let resetsAt = analysis.entry.window.resetsAt else { return }

        let windowStart = resetsAt.addingTimeInterval(-analysis.entry.duration)
        let earliestSample = analysis.samples.first?.timestamp ?? windowStart
        let rangeStart = min(earliestSample, windowStart)
        let timeRange = rangeStart...resetsAt

        let currentUtil = Double(analysis.entry.window.utilization)

        drawGrid(in: graphRect)
        drawLimitLine(in: graphRect)
        drawSustainablePaceLine(in: graphRect, timeRange: timeRange, now: now, resetsAt: resetsAt, currentUtil: currentUtil)
        drawSegments(segments: analysis.segments, in: graphRect, timeRange: timeRange, now: now, currentUtil: currentUtil)
        drawProjection(in: graphRect, timeRange: timeRange, now: now, resetsAt: resetsAt, currentUtil: currentUtil, analysis: analysis)
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
