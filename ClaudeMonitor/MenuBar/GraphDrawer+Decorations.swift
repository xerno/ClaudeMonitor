import AppKit

extension GraphDrawer {
    func drawNowMarker(in rect: NSRect, timeRange: ClosedRange<Date>, now: Date) {
        let xNow = xPosition(for: now, in: rect, timeRange: timeRange)
        let path = NSBezierPath()
        path.lineWidth = 0.5
        NSColor.labelColor.withAlphaComponent(Layout.nowMarkerAlpha).setStroke()
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
        str.draw(at: NSPoint(x: labelX, y: rect.maxY - strSize.height - Layout.nowLabelBottomGap))
    }

    func drawCurrentDot(in rect: NSRect, timeRange: ClosedRange<Date>, now: Date, currentUtil: Double) {
        let x = xPosition(for: now, in: rect, timeRange: timeRange)
        let y = yPosition(for: currentUtil, in: rect)
        let radius = Layout.currentDotRadius
        let dotRect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        let dot = NSBezierPath(ovalIn: dotRect)
        NSColor.labelColor.setFill()
        dot.fill()
    }

    func drawYAxisLabels(in rect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 10),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        let bgColor = NSColor.windowBackgroundColor
        for (pct, label) in [(0.0, "0%"), (50.0, "50%"), (100.0, "100%")] {
            let str = NSAttributedString(string: label, attributes: attrs)
            let size = str.size()
            let x = rect.minX + Layout.yAxisLabelInset
            let y = yPosition(for: pct, in: rect) - size.height / 2
            let bgRect = NSRect(
                x: x - Layout.yAxisLabelBgPadding,
                y: y - Layout.yAxisLabelBgPadding,
                width: size.width + Layout.yAxisLabelBgPadding * 2,
                height: size.height + Layout.yAxisLabelBgPadding * 2
            )
            bgColor.setFill()
            bgRect.fill()
            str.draw(at: NSPoint(x: x, y: y))
        }
    }
}
