import AppKit

extension GraphDrawer {
    func drawProjection(
        in rect: NSRect,
        timeRange: ClosedRange<Date>,
        now: Date,
        resetsAt: Date,
        currentUtil: Double,
        analysis: WindowAnalysis
    ) {
        let xNow = xPosition(for: now, in: rect, timeRange: timeRange)
        let xReset = xPosition(for: resetsAt, in: rect, timeRange: timeRange)
        let yLimit = yPosition(for: 100, in: rect)

        if currentUtil >= 100 {
            drawBlockedZone(fromX: xNow, in: rect, yLimit: yLimit, xReset: xReset)
            return
        }

        let projectionColor = color(for: analysis.style)
        let yNow = yPosition(for: currentUtil, in: rect)
        let timeRemaining = max(0, resetsAt.timeIntervalSince(now))

        let crossingDate: Date?
        let endDate: Date
        let endUtil: Double
        if let ttl = analysis.timeToLimit, ttl <= timeRemaining {
            crossingDate = now.addingTimeInterval(ttl)
            endDate = crossingDate!
            endUtil = 100
        } else {
            crossingDate = nil
            endDate = resetsAt
            endUtil = min(analysis.projectedAtReset, 100)
        }

        let xEnd = xPosition(for: endDate, in: rect, timeRange: timeRange)
        let yEnd = yPosition(for: endUtil, in: rect)

        drawProjectionFill(from: NSPoint(x: xNow, y: yNow), to: NSPoint(x: xEnd, y: yEnd), in: rect, color: projectionColor)

        if let crossing = crossingDate {
            let xCrossing = xPosition(for: crossing, in: rect, timeRange: timeRange)
            drawBlockedZone(fromX: xCrossing, in: rect, yLimit: yLimit, xReset: xReset)
        }

        drawProjectionLine(from: NSPoint(x: xNow, y: yNow), to: NSPoint(x: xEnd, y: yEnd), color: projectionColor)

        let labelText = crossingDate != nil ? "~100%" : "~\(Int(analysis.projectedAtReset.rounded()))%"
        drawProjectionLabel(labelText, at: NSPoint(x: xEnd, y: yEnd), in: rect, color: projectionColor)
    }

    private func drawProjectionFill(from start: NSPoint, to end: NSPoint, in rect: NSRect, color: NSColor) {
        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: start.x, y: rect.maxY))
        fillPath.line(to: start)
        fillPath.line(to: end)
        fillPath.line(to: NSPoint(x: end.x, y: rect.maxY))
        fillPath.close()
        color.withAlphaComponent(Layout.projectionFillAlpha).setFill()
        fillPath.fill()
    }

    private func drawProjectionLine(from start: NSPoint, to end: NSPoint, color: NSColor) {
        let linePath = NSBezierPath()
        linePath.lineWidth = Layout.projectionStrokeWidth
        linePath.setLineDash(Layout.projectionDashPattern, count: Layout.projectionDashPattern.count, phase: 0)
        color.setStroke()
        linePath.move(to: start)
        linePath.line(to: end)
        linePath.stroke()
    }

    private func drawProjectionLabel(_ text: String, at point: NSPoint, in rect: NSRect, color: NSColor) {
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: Layout.projectionLabelFontSize),
            .foregroundColor: color
        ]
        let labelStr = NSAttributedString(string: text, attributes: labelAttrs)
        let labelSize = labelStr.size()
        var labelX = point.x + Layout.projectionLabelOffset
        let labelY = point.y - labelSize.height / 2
        if labelX + labelSize.width > rect.maxX {
            labelX = point.x - labelSize.width - Layout.projectionLabelOffset
        }
        labelStr.draw(at: NSPoint(x: labelX, y: labelY))
    }

    private func drawBlockedZone(fromX: CGFloat, in rect: NSRect, yLimit: CGFloat, xReset: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: fromX, y: rect.maxY))
        path.line(to: NSPoint(x: fromX, y: yLimit))
        path.line(to: NSPoint(x: xReset, y: yLimit))
        path.line(to: NSPoint(x: xReset, y: rect.maxY))
        path.close()
        NSColor.systemRed.withAlphaComponent(Layout.blockedZoneFillAlpha).setFill()
        path.fill()
    }
}
