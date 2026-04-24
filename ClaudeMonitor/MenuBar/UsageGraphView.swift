import AppKit

// MARK: - UsageRowView

/// A custom NSView used as an NSMenuItem's view for usage rows.
/// Because `.view` is set on the menu item, NSMenu does NOT auto-close on click.
final class UsageRowView: NSView {
    private let textField: NSTextField
    var onClick: (() -> Void)?
    private var isHighlighted = false
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    private static let selectionBarWidth: CGFloat = 3
    private static let leftPadding: CGFloat = 17  // standard menu item left margin
    private static let rightPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 3

    init(attributedTitle: NSAttributedString) {
        textField = NSTextField(labelWithAttributedString: attributedTitle)
        textField.isSelectable = false
        let textSize = attributedTitle.size()
        let height = textSize.height + UsageRowView.verticalPadding * 2
        let width = textSize.width + UsageRowView.leftPadding + UsageRowView.rightPadding + UsageRowView.selectionBarWidth
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textField.frame = NSRect(
            x: UsageRowView.leftPadding + UsageRowView.selectionBarWidth,
            y: UsageRowView.verticalPadding,
            width: textSize.width + UsageRowView.rightPadding,
            height: textSize.height
        )
        addSubview(textField)
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) { isHighlighted = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHighlighted = false; needsDisplay = true }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    func updateTitle(_ attributedTitle: NSAttributedString) {
        textField.attributedStringValue = attributedTitle
        let textSize = attributedTitle.size()
        textField.frame.size.width = textSize.width + UsageRowView.rightPadding
    }

    /// Returns the current attributed title of the row.
    var currentAttributedTitle: NSAttributedString { textField.attributedStringValue }

    /// Returns the plain string content of the row (for testing).
    var textContent: String { textField.attributedStringValue.string }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).setFill()
            dirtyRect.fill()
        }
        if isSelected {
            NSColor.controlAccentColor.setFill()
            NSRect(x: UsageRowView.leftPadding, y: 0,
                   width: UsageRowView.selectionBarWidth, height: bounds.height).fill()
        }
    }
}

// MARK: - UsageGraphView

@MainActor
final class UsageGraphView: NSView {
    private var analyses: [WindowAnalysis] = []
    private var selectedIndex: Int = 0
    private var userSelectedIndex: Bool = false
    private let statsLabel = NSTextField(labelWithString: "")

    private enum Layout {
        static let graphHeight: CGFloat = 280
        static let statsHeight: CGFloat = 20
        static let topPadding: CGFloat = 14
        static let graphStatsGap: CGFloat = 6
        static let bottomPadding: CGFloat = 0
        static let sidePadding: CGFloat = 12
        static let defaultWidth: CGFloat = 280
        static let totalHeight: CGFloat = topPadding + graphHeight + graphStatsGap + statsHeight + bottomPadding
        static let noDataHeight: CGFloat = 0
    }

    var currentSelectedIndex: Int { selectedIndex }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: Layout.defaultWidth, height: Layout.totalHeight))
        autoresizingMask = .width
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        statsLabel.font = NSFont.systemFont(ofSize: 12)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.alignment = .center
        statsLabel.autoresizingMask = .width
        statsLabel.frame = NSRect(
            x: Layout.sidePadding,
            y: Layout.topPadding + Layout.graphHeight + Layout.graphStatsGap,
            width: bounds.width - Layout.sidePadding * 2,
            height: Layout.statsHeight
        )
        addSubview(statsLabel)
    }

    // NSView uses non-flipped coordinates (y=0 at bottom) by default on macOS.
    // We override isFlipped to make it flipped (y=0 at top) so layout math is
    // simpler for subview positioning, but we handle graph drawing manually.
    override var isFlipped: Bool { true }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    func selectWindow(at index: Int) {
        guard !analyses.isEmpty else { return }
        selectedIndex = max(0, min(index, analyses.count - 1))
        userSelectedIndex = true
        updateFrameHeight()
        updateStatsLabel()
        needsDisplay = true
    }

    func update(analyses: [WindowAnalysis]) {
        let countChanged = analyses.count != self.analyses.count
        self.analyses = analyses

        if countChanged {
            userSelectedIndex = false
        }

        // Default selected: highest warning level. On tie, first (shortest duration).
        // Only auto-select if user hasn't manually chosen.
        if !userSelectedIndex {
            selectedIndex = highestWarningIndex(analyses: analyses)
        } else {
            // Clamp in case count decreased
            selectedIndex = max(0, min(selectedIndex, analyses.count - 1))
        }

        updateFrameHeight()
        updateStatsLabel()
        needsDisplay = true
    }

    private func highestWarningIndex(analyses: [WindowAnalysis]) -> Int {
        guard !analyses.isEmpty else { return 0 }
        var best = 0
        var bestScore = levelScore(analyses[0].style)
        for (i, a) in analyses.enumerated().dropFirst() {
            let score = levelScore(a.style)
            if score > bestScore {
                bestScore = score
                best = i
            }
        }
        return best
    }

    private func levelScore(_ style: Formatting.UsageStyle) -> Int {
        switch style.level {
        case .normal: return style.isBold ? 1 : 0
        case .warning: return 2
        case .critical: return 3
        }
    }

    // MARK: - Frame Height

    private var selectedHasData: Bool {
        guard selectedIndex < analyses.count else { return false }
        return analyses[selectedIndex].entry.window.resetsAt != nil
    }

    private func updateFrameHeight() {
        let targetHeight = selectedHasData ? Layout.totalHeight : Layout.noDataHeight
        guard frame.height != targetHeight else { return }
        frame.size.height = targetHeight
        statsLabel.isHidden = !selectedHasData
        if selectedHasData {
            statsLabel.frame.origin.y = targetHeight - Layout.statsHeight - Layout.bottomPadding
        }
        updateTrackingAreas()
    }

    // MARK: - Graph Rect Helper

    private func currentGraphRect() -> NSRect {
        let graphWidth = bounds.width - Layout.sidePadding * 2
        return NSRect(
            x: Layout.sidePadding,
            y: Layout.topPadding,
            width: graphWidth,
            height: Layout.graphHeight
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard selectedIndex < analyses.count else { return }
        let analysis = analyses[selectedIndex]

        let graphRect = currentGraphRect()

        let now = Date()
        guard let resetsAt = analysis.entry.window.resetsAt else { return }

        // Time range: oldest sample (or window start) to resetsAt
        let windowStart = resetsAt.addingTimeInterval(-analysis.entry.duration)
        let earliestSample = analysis.samples.first?.timestamp ?? windowStart
        let rangeStart = min(earliestSample, windowStart)
        let timeRange = rangeStart...resetsAt

        let currentUtil = Double(analysis.entry.window.utilization)

        // Draw back to front
        drawGrid(in: graphRect)
        drawLimitLine(in: graphRect)
        drawSustainablePaceLine(in: graphRect, timeRange: timeRange, now: now, resetsAt: resetsAt, currentUtil: currentUtil, analysis: analysis)
        drawSegments(segments: analysis.segments, in: graphRect, timeRange: timeRange, now: now, currentUtil: currentUtil)
        drawProjection(in: graphRect, timeRange: timeRange, now: now, resetsAt: resetsAt, currentUtil: currentUtil, analysis: analysis)
        drawNowMarker(in: graphRect, timeRange: timeRange, now: now)
        drawCurrentDot(in: graphRect, timeRange: timeRange, now: now, currentUtil: currentUtil)
        drawYAxisLabels(in: graphRect)
    }

    // MARK: - Coordinate Helpers

    // x increases left to right; timeRange maps to graphRect horizontally.
    // In flipped view, y=0 is top. We want y=0% at bottom of graph, so we invert.
    private func xPosition(for date: Date, in rect: NSRect, timeRange: ClosedRange<Date>) -> CGFloat {
        let total = timeRange.upperBound.timeIntervalSince(timeRange.lowerBound)
        guard total > 0 else { return rect.minX }
        let elapsed = date.timeIntervalSince(timeRange.lowerBound)
        let fraction = max(0, min(1, elapsed / total))
        return rect.minX + fraction * rect.width
    }

    // y for utilization (0-100). In flipped coords, y=0 at top of view.
    // We want 0% at bottom of graph (rect.maxY in flipped) and 100% at top (rect.minY in flipped).
    private func yPosition(for utilization: Double, in rect: NSRect) -> CGFloat {
        let fraction = max(0, min(1, utilization / 100.0))
        return rect.maxY - fraction * rect.height
    }

    // MARK: - Graph Components

    private func drawGrid(in rect: NSRect) {
        let color = NSColor.secondaryLabelColor.withAlphaComponent(0.1)
        color.setStroke()
        for pct in [25.0, 50.0, 75.0] {
            let y = yPosition(for: pct, in: rect)
            let path = NSBezierPath()
            path.lineWidth = 0.5
            path.move(to: NSPoint(x: rect.minX, y: y))
            path.line(to: NSPoint(x: rect.maxX, y: y))
            path.stroke()
        }
    }

    private func drawLimitLine(in rect: NSRect) {
        let y = yPosition(for: 100, in: rect)
        let path = NSBezierPath()
        path.lineWidth = 1
        NSColor.systemRed.withAlphaComponent(0.4).setStroke()
        path.move(to: NSPoint(x: rect.minX, y: y))
        path.line(to: NSPoint(x: rect.maxX, y: y))
        path.stroke()
    }

    private func drawSustainablePaceLine(
        in rect: NSRect,
        timeRange: ClosedRange<Date>,
        now: Date,
        resetsAt: Date,
        currentUtil: Double,
        analysis: WindowAnalysis
    ) {
        guard currentUtil < 100 else { return }
        let xNow = xPosition(for: now, in: rect, timeRange: timeRange)
        let xReset = xPosition(for: resetsAt, in: rect, timeRange: timeRange)
        let yNow = yPosition(for: currentUtil, in: rect)
        let yReset = yPosition(for: 100, in: rect)

        let path = NSBezierPath()
        path.lineWidth = 1
        let dashes: [CGFloat] = [3, 3]
        path.setLineDash(dashes, count: 2, phase: 0)
        NSColor.secondaryLabelColor.withAlphaComponent(0.3).setStroke()
        path.move(to: NSPoint(x: xNow, y: yNow))
        path.line(to: NSPoint(x: xReset, y: yReset))
        path.stroke()
    }

    // MARK: - Segment Drawing

    private func drawSegments(segments: [SampleSegment], in rect: NSRect, timeRange: ClosedRange<Date>, now: Date, currentUtil: Double) {
        for (index, segment) in segments.enumerated() {
            let isLastSegment = index == segments.count - 1
            switch segment.kind {
            case .tracked:
                var samples = segment.samples
                // Connect last tracked segment to current position so there's no gap before "now"
                if isLastSegment {
                    samples.append(UtilizationSample(utilization: Int(currentUtil), timestamp: now))
                }
                drawTrackedSegment(samples, in: rect, timeRange: timeRange)
            case .inferred:
                drawInferredSegment(segment.samples, in: rect, timeRange: timeRange)
            case .gap:
                drawGapSegment(segment.samples, in: rect, timeRange: timeRange)
            }
        }
    }

    private func drawTrackedSegment(_ samples: [UtilizationSample], in rect: NSRect, timeRange: ClosedRange<Date>) {
        guard samples.count >= 2 else { return }
        // samples are pre-sorted by segmentSamples

        // Filled area
        let fillPath = NSBezierPath()
        let first = samples[0]
        let firstX = xPosition(for: first.timestamp, in: rect, timeRange: timeRange)
        let firstY = yPosition(for: Double(first.utilization), in: rect)
        fillPath.move(to: NSPoint(x: firstX, y: rect.maxY))
        fillPath.line(to: NSPoint(x: firstX, y: firstY))
        for sample in samples.dropFirst() {
            let x = xPosition(for: sample.timestamp, in: rect, timeRange: timeRange)
            let y = yPosition(for: Double(sample.utilization), in: rect)
            fillPath.line(to: NSPoint(x: x, y: y))
        }
        let lastX = xPosition(for: samples.last!.timestamp, in: rect, timeRange: timeRange)
        fillPath.line(to: NSPoint(x: lastX, y: rect.maxY))
        fillPath.close()
        NSColor.systemBlue.withAlphaComponent(0.15).setFill()
        fillPath.fill()

        // Stroke top edge
        let strokePath = NSBezierPath()
        strokePath.lineWidth = 1.5
        strokePath.move(to: NSPoint(x: firstX, y: firstY))
        for sample in samples.dropFirst() {
            let x = xPosition(for: sample.timestamp, in: rect, timeRange: timeRange)
            let y = yPosition(for: Double(sample.utilization), in: rect)
            strokePath.line(to: NSPoint(x: x, y: y))
        }
        NSColor.systemBlue.withAlphaComponent(0.7).setStroke()
        strokePath.stroke()
    }

    private func drawInferredSegment(_ samples: [UtilizationSample], in rect: NSRect, timeRange: ClosedRange<Date>) {
        guard samples.count >= 2 else { return }
        let first = samples[0]
        let last = samples[1]
        let x0 = xPosition(for: first.timestamp, in: rect, timeRange: timeRange)
        let y0 = yPosition(for: Double(first.utilization), in: rect)
        let x1 = xPosition(for: last.timestamp, in: rect, timeRange: timeRange)
        let y1 = yPosition(for: Double(last.utilization), in: rect)

        // Light filled area
        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: x0, y: rect.maxY))
        fillPath.line(to: NSPoint(x: x0, y: y0))
        fillPath.line(to: NSPoint(x: x1, y: y1))
        fillPath.line(to: NSPoint(x: x1, y: rect.maxY))
        fillPath.close()
        NSColor.systemBlue.withAlphaComponent(0.07).setFill()
        fillPath.fill()

        // Dashed stroke (2pt dash, 2pt gap)
        let strokePath = NSBezierPath()
        strokePath.lineWidth = 1.5
        let dashes: [CGFloat] = [2, 2]
        strokePath.setLineDash(dashes, count: 2, phase: 0)
        strokePath.move(to: NSPoint(x: x0, y: y0))
        strokePath.line(to: NSPoint(x: x1, y: y1))
        NSColor.systemBlue.withAlphaComponent(0.5).setStroke()
        strokePath.stroke()
    }

    private func drawGapSegment(_ samples: [UtilizationSample], in rect: NSRect, timeRange: ClosedRange<Date>) {
        guard samples.count >= 2 else { return }
        let before = samples[0]
        let after = samples[1]
        let x0 = xPosition(for: before.timestamp, in: rect, timeRange: timeRange)
        let x1 = xPosition(for: after.timestamp, in: rect, timeRange: timeRange)
        let gapRect = NSRect(x: x0, y: rect.minY, width: x1 - x0, height: rect.height)

        // Diagonal hatching: clip to gap rect, then draw diagonal lines at 45°, spaced 6pt
        NSGraphicsContext.saveGraphicsState()
        let clipPath = NSBezierPath(rect: gapRect)
        clipPath.addClip()

        let hatchColor = NSColor.systemGray.withAlphaComponent(0.15)
        hatchColor.setStroke()
        let spacing: CGFloat = 6
        let diagonal = gapRect.width + gapRect.height
        var offset: CGFloat = -diagonal
        while offset < diagonal {
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: gapRect.minX + offset, y: gapRect.minY))
            path.line(to: NSPoint(x: gapRect.minX + offset + gapRect.height, y: gapRect.maxY))
            path.stroke()
            offset += spacing
        }
        NSGraphicsContext.restoreGraphicsState()

        // Dashed line across the gap at the utilization level
        let y0 = yPosition(for: Double(before.utilization), in: rect)
        let y1 = yPosition(for: Double(after.utilization), in: rect)
        let linePath = NSBezierPath()
        linePath.lineWidth = 1
        let dashes: [CGFloat] = [4, 3]
        linePath.setLineDash(dashes, count: 2, phase: 0)
        linePath.move(to: NSPoint(x: x0, y: y0))
        linePath.line(to: NSPoint(x: x1, y: y1))
        NSColor.secondaryLabelColor.withAlphaComponent(0.5).setStroke()
        linePath.stroke()
    }

    private func drawProjection(
        in rect: NSRect,
        timeRange: ClosedRange<Date>,
        now: Date,
        resetsAt: Date,
        currentUtil: Double,
        analysis: WindowAnalysis
    ) {
        let projectionColor = color(for: analysis.style)
        let xNow = xPosition(for: now, in: rect, timeRange: timeRange)
        let yNow = yPosition(for: currentUtil, in: rect)

        let timeRemaining = max(0, resetsAt.timeIntervalSince(now))
        let projectedAtReset = analysis.projectedAtReset

        // Endpoint: if projected >= 100, find crossing time; otherwise end at reset
        let endDate: Date
        let endUtil: Double
        var crossingDate: Date? = nil

        if let ttl = analysis.timeToLimit, ttl <= timeRemaining {
            crossingDate = now.addingTimeInterval(ttl)
            endDate = crossingDate!
            endUtil = 100
        } else {
            endDate = resetsAt
            endUtil = min(projectedAtReset, 100)
        }

        let xEnd = xPosition(for: endDate, in: rect, timeRange: timeRange)
        let yEnd = yPosition(for: endUtil, in: rect)

        // Fill under projection
        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: xNow, y: rect.maxY))
        fillPath.line(to: NSPoint(x: xNow, y: yNow))
        fillPath.line(to: NSPoint(x: xEnd, y: yEnd))
        fillPath.line(to: NSPoint(x: xEnd, y: rect.maxY))
        fillPath.close()
        projectionColor.withAlphaComponent(0.06).setFill()
        fillPath.fill()

        // "Blocked zone" fill if projection crosses 100%
        if let crossing = crossingDate {
            let xCrossing = xPosition(for: crossing, in: rect, timeRange: timeRange)
            let xReset = xPosition(for: resetsAt, in: rect, timeRange: timeRange)
            let yLimit = yPosition(for: 100, in: rect)
            let blockedPath = NSBezierPath()
            blockedPath.move(to: NSPoint(x: xCrossing, y: rect.maxY))
            blockedPath.line(to: NSPoint(x: xCrossing, y: yLimit))
            blockedPath.line(to: NSPoint(x: xReset, y: yLimit))
            blockedPath.line(to: NSPoint(x: xReset, y: rect.maxY))
            blockedPath.close()
            NSColor.systemRed.withAlphaComponent(0.08).setFill()
            blockedPath.fill()
        }

        // Projection line (dashed)
        let linePath = NSBezierPath()
        linePath.lineWidth = 1.5
        let dashes: [CGFloat] = [4, 3]
        linePath.setLineDash(dashes, count: 2, phase: 0)
        projectionColor.setStroke()
        linePath.move(to: NSPoint(x: xNow, y: yNow))
        linePath.line(to: NSPoint(x: xEnd, y: yEnd))
        linePath.stroke()

        // Projected value label at end of projection line
        let labelText = crossingDate != nil ? "~100%" : "~\(Int(projectedAtReset.rounded()))%"
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 11),
            .foregroundColor: projectionColor
        ]
        let labelStr = NSAttributedString(string: labelText, attributes: labelAttrs)
        let labelSize = labelStr.size()
        var labelX = xEnd + 3
        let labelY = yEnd - labelSize.height / 2
        if labelX + labelSize.width > rect.maxX {
            labelX = xEnd - labelSize.width - 3
        }
        labelStr.draw(at: NSPoint(x: labelX, y: labelY))
    }

    private func drawNowMarker(in rect: NSRect, timeRange: ClosedRange<Date>, now: Date) {
        let xNow = xPosition(for: now, in: rect, timeRange: timeRange)
        let path = NSBezierPath()
        path.lineWidth = 0.5
        NSColor.labelColor.withAlphaComponent(0.4).setStroke()
        path.move(to: NSPoint(x: xNow, y: rect.minY))
        path.line(to: NSPoint(x: xNow, y: rect.maxY))
        path.stroke()

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let str = NSAttributedString(string: String(localized: "graph.now", bundle: .module), attributes: attrs)
        let strSize = str.size()
        var labelX = xNow - strSize.width / 2
        labelX = max(rect.minX, min(labelX, rect.maxX - strSize.width))
        str.draw(at: NSPoint(x: labelX, y: rect.maxY - strSize.height - 1))
    }

    private func drawCurrentDot(in rect: NSRect, timeRange: ClosedRange<Date>, now: Date, currentUtil: Double) {
        let x = xPosition(for: now, in: rect, timeRange: timeRange)
        let y = yPosition(for: currentUtil, in: rect)
        let radius: CGFloat = 2.5
        let dotRect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        let dot = NSBezierPath(ovalIn: dotRect)
        NSColor.labelColor.setFill()
        dot.fill()
    }

    private func drawYAxisLabels(in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let bgColor = NSColor.windowBackgroundColor
        let bgPadding: CGFloat = 2
        for (pct, label) in [(0.0, "0%"), (50.0, "50%"), (100.0, "100%")] {
            let str = NSAttributedString(string: label, attributes: attrs)
            let size = str.size()
            let x = rect.minX + 2
            let y = yPosition(for: pct, in: rect) - size.height / 2
            let bgRect = NSRect(
                x: x - bgPadding,
                y: y - bgPadding,
                width: size.width + bgPadding * 2,
                height: size.height + bgPadding * 2
            )
            bgColor.setFill()
            bgRect.fill()
            str.draw(at: NSPoint(x: x, y: y))
        }
    }

    // MARK: - Color Helper

    private func color(for style: Formatting.UsageStyle) -> NSColor {
        switch style.level {
        case .normal: return style.isBold ? .labelColor : .systemGreen
        case .warning: return .systemOrange
        case .critical: return .systemRed
        }
    }

    // MARK: - Stats Label

    private func updateStatsLabel(now: Date = Date()) {
        guard selectedIndex < analyses.count else {
            statsLabel.stringValue = ""
            return
        }
        let analysis = analyses[selectedIndex]
        let util = analysis.entry.window.utilization
        let resetsAt = analysis.entry.window.resetsAt

        guard let resetsAt else {
            statsLabel.stringValue = ""
            return
        }

        if util >= 100 {
            let timeStr = Formatting.timeUntil(resetsAt)
            statsLabel.stringValue = String(format: String(localized: "graph.stats.blocked", bundle: .module), timeStr)
            return
        }

        if analysis.rateSource == .insufficient {
            statsLabel.stringValue = String(localized: "graph.stats.collecting", bundle: .module)
            return
        }

        if analysis.consumptionRate == 0 {
            let headroom = 100 - util
            statsLabel.stringValue = String(format: String(localized: "graph.stats.idle", bundle: .module), headroom)
            return
        }

        let rateStr = Formatting.formatRate(analysis.consumptionRate)

        if analysis.projectedAtReset >= 100 {
            if let ttl = analysis.timeToLimit {
                let beforeReset = max(0, resetsAt.timeIntervalSince(now) - ttl)
                let beforeResetStr = Formatting.timeUntil(beforeReset)
                statsLabel.stringValue = String(format: String(localized: "graph.stats.limit_soon", bundle: .module), rateStr, beforeResetStr)
            } else {
                statsLabel.stringValue = String(format: String(localized: "graph.stats.limit_unknown", bundle: .module), rateStr)
            }
        } else {
            let proj = Int(analysis.projectedAtReset.rounded())
            statsLabel.stringValue = String(format: String(localized: "graph.stats.projected", bundle: .module), rateStr, proj)
        }
    }
}
