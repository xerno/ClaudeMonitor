import AppKit

extension GraphDrawer {
    func drawGrid(in rect: NSRect) {
        let color = NSColor.secondaryLabelColor.withAlphaComponent(Layout.gridLineAlpha)
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

    func drawLimitLine(in rect: NSRect) {
        let y = yPosition(for: 100, in: rect)
        let path = NSBezierPath()
        path.lineWidth = 1
        NSColor.systemRed.withAlphaComponent(Layout.limitLineAlpha).setStroke()
        path.move(to: NSPoint(x: rect.minX, y: y))
        path.line(to: NSPoint(x: rect.maxX, y: y))
        path.stroke()
    }

    func drawSustainablePaceLine(
        in rect: NSRect,
        timeRange: ClosedRange<Date>,
        now: Date,
        resetsAt: Date,
        currentUtil: Double
    ) {
        guard currentUtil < 100 else { return }
        let xNow = xPosition(for: now, in: rect, timeRange: timeRange)
        let xReset = xPosition(for: resetsAt, in: rect, timeRange: timeRange)
        let yNow = yPosition(for: currentUtil, in: rect)
        let yReset = yPosition(for: 100, in: rect)

        let path = NSBezierPath()
        path.lineWidth = 1
        path.setLineDash(Layout.sustainablePaceDashPattern, count: Layout.sustainablePaceDashPattern.count, phase: 0)
        NSColor.secondaryLabelColor.withAlphaComponent(Layout.sustainablePaceAlpha).setStroke()
        path.move(to: NSPoint(x: xNow, y: yNow))
        path.line(to: NSPoint(x: xReset, y: yReset))
        path.stroke()
    }
}
