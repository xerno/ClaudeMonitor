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
        drawWithHalo(str, at: NSPoint(x: labelX, y: rect.maxY - strSize.height - Layout.nowLabelBottomGap))
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
        // Locale-aware, replacing hardcoded "0%"/"50%"/"100%" — those literals forced the percent
        // sign to trail the number and used Western-Arabic numerals in every locale, including
        // ones that lead with the sign or use a different numbering system. Built once per axis
        // draw rather than as a shared static: this method is nonisolated and `NumberFormatter`
        // is not `Sendable`, so a stored instance would need an unsafe opt-out to be reachable.
        let percentFormatter = NumberFormatter()
        percentFormatter.numberStyle = .percent
        percentFormatter.locale = .autoupdatingCurrent
        percentFormatter.maximumFractionDigits = 0

        for pct in [0.0, 50.0, 100.0] {
            // `.percent` multiplies by 100, so the fraction is what goes in.
            let label = percentFormatter.string(from: NSNumber(value: pct / 100)) ?? "\(Int(pct))%"
            let str = NSAttributedString(string: label, attributes: attrs)
            let point = NSPoint(
                x: rect.minX + Layout.yAxisLabelInset,
                y: yPosition(for: pct, in: rect) - str.size().height / 2
            )
            drawWithHalo(str, at: point)
        }
    }

    func drawWithHalo(_ text: NSAttributedString, at point: NSPoint) {
        let halo = NSMutableAttributedString(attributedString: text)
        halo.addAttributes(
            [.strokeColor: NSColor.windowBackgroundColor, .strokeWidth: Layout.labelHaloStrokeWidth],
            range: NSRange(location: 0, length: halo.length)
        )
        halo.draw(at: point)
        text.draw(at: point)
    }
}
