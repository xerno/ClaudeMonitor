import AppKit

extension GraphDrawer {
    func drawSegments(segments: [SampleSegment], in rect: NSRect, timeRange: ClosedRange<Date>, now: Date, currentUtil: Double) {
        for (index, segment) in segments.enumerated() {
            let isLastSegment = index == segments.count - 1
            switch segment.kind {
            case .tracked:
                var samples = segment.samples
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

    private func buildSegmentPaths(
        _ samples: [UtilizationSample],
        in rect: NSRect,
        timeRange: ClosedRange<Date>
    ) -> (fill: NSBezierPath, stroke: NSBezierPath) {
        guard samples.count >= 2 else { return (NSBezierPath(), NSBezierPath()) }
        let first = samples[0]
        let firstX = xPosition(for: first.timestamp, in: rect, timeRange: timeRange)
        let firstY = yPosition(for: Double(first.utilization), in: rect)

        let fillPath = NSBezierPath()
        fillPath.move(to: NSPoint(x: firstX, y: rect.maxY))
        fillPath.line(to: NSPoint(x: firstX, y: firstY))

        let strokePath = NSBezierPath()
        strokePath.move(to: NSPoint(x: firstX, y: firstY))

        for sample in samples.dropFirst() {
            let x = xPosition(for: sample.timestamp, in: rect, timeRange: timeRange)
            let y = yPosition(for: Double(sample.utilization), in: rect)
            fillPath.line(to: NSPoint(x: x, y: y))
            strokePath.line(to: NSPoint(x: x, y: y))
        }
        fillPath.line(to: NSPoint(x: xPosition(for: samples.last!.timestamp, in: rect, timeRange: timeRange), y: rect.maxY))
        fillPath.close()

        return (fillPath, strokePath)
    }

    private func drawTrackedSegment(_ samples: [UtilizationSample], in rect: NSRect, timeRange: ClosedRange<Date>) {
        let (fillPath, strokePath) = buildSegmentPaths(samples, in: rect, timeRange: timeRange)

        NSColor.systemBlue.withAlphaComponent(Layout.trackedFillAlpha).setFill()
        fillPath.fill()

        strokePath.lineWidth = Layout.trackedStrokeWidth
        NSColor.systemBlue.withAlphaComponent(Layout.trackedStrokeAlpha).setStroke()
        strokePath.stroke()
    }

    private func drawInferredSegment(_ samples: [UtilizationSample], in rect: NSRect, timeRange: ClosedRange<Date>) {
        let (fillPath, strokePath) = buildSegmentPaths(samples, in: rect, timeRange: timeRange)

        NSColor.systemBlue.withAlphaComponent(Layout.inferredFillAlpha).setFill()
        fillPath.fill()

        strokePath.lineWidth = Layout.inferredStrokeWidth
        strokePath.setLineDash(Layout.inferredDashPattern, count: Layout.inferredDashPattern.count, phase: 0)
        NSColor.systemBlue.withAlphaComponent(Layout.inferredStrokeAlpha).setStroke()
        strokePath.stroke()
    }

    private func drawGapSegment(_ samples: [UtilizationSample], in rect: NSRect, timeRange: ClosedRange<Date>) {
        guard samples.count >= 2 else { return }
        let before = samples[0], after = samples[1]
        let x0 = xPosition(for: before.timestamp, in: rect, timeRange: timeRange)
        let x1 = xPosition(for: after.timestamp, in: rect, timeRange: timeRange)
        let gapRect = NSRect(x: x0, y: rect.minY, width: x1 - x0, height: rect.height)
        drawGapHatch(in: gapRect)
        drawGapDashedLine(
            from: NSPoint(x: x0, y: yPosition(for: Double(before.utilization), in: rect)),
            to: NSPoint(x: x1, y: yPosition(for: Double(after.utilization), in: rect))
        )
    }

    private func drawGapHatch(in gapRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: gapRect).addClip()
        NSColor.systemGray.withAlphaComponent(Layout.gapHatchAlpha).setStroke()
        let diagonal = gapRect.width + gapRect.height
        var offset: CGFloat = -diagonal
        while offset < diagonal {
            let path = NSBezierPath()
            path.lineWidth = 1
            path.move(to: NSPoint(x: gapRect.minX + offset, y: gapRect.minY))
            path.line(to: NSPoint(x: gapRect.minX + offset + gapRect.height, y: gapRect.maxY))
            path.stroke()
            offset += Layout.gapHatchSpacing
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    private func drawGapDashedLine(from start: NSPoint, to end: NSPoint) {
        let linePath = NSBezierPath()
        linePath.lineWidth = 1
        linePath.setLineDash(Layout.gapDashPattern, count: Layout.gapDashPattern.count, phase: 0)
        linePath.move(to: start)
        linePath.line(to: end)
        NSColor.secondaryLabelColor.withAlphaComponent(Layout.inferredStrokeAlpha).setStroke()
        linePath.stroke()
    }
}
