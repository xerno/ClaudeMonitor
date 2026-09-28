import AppKit

extension GraphDrawer {
    /// Computed apart from drawing so it can be tested without a screen.
    struct CreditMarker: Equatable {
        let x: CGFloat
        let yFrom: CGFloat
        let yTo: CGFloat
    }

    /// Events outside `timeRange` are dropped, not clamped to an edge: clamping would misplace the credit in time.
    func visibleCreditMarkers(in rect: NSRect, timeRange: ClosedRange<Date>) -> [CreditMarker] {
        events.filter { timeRange.contains($0.at) }.map { event in
            CreditMarker(
                x: xPosition(for: event.at, in: rect, timeRange: timeRange),
                yFrom: yPosition(for: Double(event.from), in: rect),
                yTo: yPosition(for: Double(event.to), in: rect)
            )
        }
    }

    func drawCreditEvents(in rect: NSRect, timeRange: ClosedRange<Date>) {
        for marker in visibleCreditMarkers(in: rect, timeRange: timeRange) {
            drawCreditLine(at: marker.x, in: rect)
            drawCreditStep(at: marker.x, yFrom: marker.yFrom, yTo: marker.yTo)
            drawCreditMarker(at: marker.x, y: marker.yTo)
        }
    }

    private func drawCreditLine(at x: CGFloat, in rect: NSRect) {
        let path = NSBezierPath()
        path.lineWidth = Layout.creditLineWidth
        path.setLineDash(Layout.creditLineDashPattern, count: Layout.creditLineDashPattern.count, phase: 0)
        Layout.creditColor.withAlphaComponent(Layout.creditLineAlpha).setStroke()
        path.move(to: NSPoint(x: x, y: rect.minY))
        path.line(to: NSPoint(x: x, y: rect.maxY))
        path.stroke()
    }

    /// A vertical step kept out of the interpolated curve, so the drop can't read as gradual reduction.
    private func drawCreditStep(at x: CGFloat, yFrom: CGFloat, yTo: CGFloat) {
        guard yFrom != yTo else { return }
        let path = NSBezierPath()
        path.lineWidth = Layout.creditStepWidth
        Layout.creditColor.setStroke()
        path.move(to: NSPoint(x: x, y: yFrom))
        path.line(to: NSPoint(x: x, y: yTo))
        path.stroke()
    }

    private func drawCreditMarker(at x: CGFloat, y: CGFloat) {
        let radius = Layout.creditDotRadius
        let dotRect = NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)
        let dot = NSBezierPath(ovalIn: dotRect)
        Layout.creditColor.setFill()
        dot.fill()
    }
}
