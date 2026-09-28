import Testing
import Foundation
import AppKit
@testable import ClaudeMonitor

/// The axis domain is the window itself: a sample stored before the window start must not stretch it,
/// or "now" lands too far right.
struct GraphTimeRangeTests {
    private let fiveHours: TimeInterval = 5 * 60 * 60
    private let sevenDays: TimeInterval = 7 * 24 * 60 * 60

    @Test func axisSpansExactlyFiveHourWindowDuration() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)
        #expect(range.upperBound.timeIntervalSince(range.lowerBound) == fiveHours)
    }

    @Test func axisSpansExactlySevenDayWindowDuration() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: sevenDays)
        #expect(range.upperBound.timeIntervalSince(range.lowerBound) == sevenDays)
    }

    @Test func preWindowSampleDoesNotWidenTheAxis() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let windowStart = resetsAt.addingTimeInterval(-fiveHours)
        let preWindowSampleTime = windowStart.addingTimeInterval(-2.5 * 60 * 60)
        #expect(preWindowSampleTime < windowStart)

        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)
        #expect(range.lowerBound == windowStart)
        #expect(range.upperBound.timeIntervalSince(range.lowerBound) == fiveHours)
    }

    @Test func nowSitsOneTenthAlongTheAxisWithFourAndHalfHoursRemaining() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let now = resetsAt.addingTimeInterval(-4.5 * 60 * 60)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)

        let elapsedFraction = now.timeIntervalSince(range.lowerBound) / range.upperBound.timeIntervalSince(range.lowerBound)
        #expect(abs(elapsedFraction - 0.1) < 0.0001)
    }

    @Test func xPositionMapsDomainBoundsOntoRectEdges() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)
        let rect = NSRect(x: 0, y: 0, width: 100, height: 200)
        let drawer = GraphDrawer(analyses: [], selectedIndex: 0, graphRect: rect, now: resetsAt)

        #expect(drawer.xPosition(for: range.lowerBound, in: rect, timeRange: range) == rect.minX)
        #expect(drawer.xPosition(for: range.upperBound, in: rect, timeRange: range) == rect.maxX)
    }

    /// Dropped, not clamped onto the left edge: a clamped marker would read as a credit at window start.
    @Test func creditEventBeforeWindowStartProducesNoMarker() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)
        let rect = NSRect(x: 0, y: 0, width: 100, height: 200)

        let entry = WindowEntry(
            key: "five_hour", duration: fiveHours, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 10, resetsAt: resetsAt)
        )
        let preWindowEvent = UsageEvent(
            at: range.lowerBound.addingTimeInterval(-1), kind: .credit, from: 20, to: 0, fromTimestamp: nil
        )
        let analysis = WindowAnalysis(
            entry: entry, samples: [], events: [preWindowEvent], consumptionRate: 0,
            projectedAtReset: 10, timeToLimit: nil, rateSource: .insufficient,
            style: Formatting.UsageStyle(level: .normal, isBold: false),
            segments: [], timeSinceLastChange: nil, recentRate: nil
        )
        let drawer = GraphDrawer(analyses: [analysis], selectedIndex: 0, graphRect: rect, now: resetsAt)

        let markers = drawer.visibleCreditMarkers(in: rect, timeRange: range)
        #expect(markers.isEmpty)
    }

    // MARK: - plottableSamples (segment filtering)

    /// Excluded outright, not plotted clamped at `rect.minX`.
    @Test func segmentStraddlingWindowStartRetainsOnlyInWindowSamples() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)

        let preWindow1 = UtilizationSample(utilization: 0, timestamp: range.lowerBound.addingTimeInterval(-7200))
        let preWindow2 = UtilizationSample(utilization: 25, timestamp: range.lowerBound.addingTimeInterval(-60))
        let inWindow1 = UtilizationSample(utilization: 30, timestamp: range.lowerBound.addingTimeInterval(600))
        let inWindow2 = UtilizationSample(utilization: 40, timestamp: range.lowerBound.addingTimeInterval(1200))

        let plotted = GraphDrawer.plottableSamples([preWindow1, preWindow2, inWindow1, inWindow2], in: range)

        #expect(plotted == [inWindow1, inWindow2])
        #expect(plotted.allSatisfy { range.contains($0.timestamp) })
    }

    @Test func differingPreWindowUtilizationsAreAllExcludedNotClamped() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)

        let samples = [
            UtilizationSample(utilization: 0, timestamp: range.lowerBound.addingTimeInterval(-9000)),
            UtilizationSample(utilization: 10, timestamp: range.lowerBound.addingTimeInterval(-5000)),
            UtilizationSample(utilization: 20, timestamp: range.lowerBound.addingTimeInterval(-1000)),
            UtilizationSample(utilization: 30, timestamp: range.lowerBound.addingTimeInterval(600)),
            UtilizationSample(utilization: 40, timestamp: range.lowerBound.addingTimeInterval(1800)),
        ]
        let plotted = GraphDrawer.plottableSamples(samples, in: range)

        #expect(plotted.allSatisfy { range.contains($0.timestamp) })
        #expect(plotted.count == 2)
    }

    @Test func segmentEntirelyBeforeWindowStartProducesNoPlottableSamples() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)

        let samples = [
            UtilizationSample(utilization: 0, timestamp: range.lowerBound.addingTimeInterval(-9000)),
            UtilizationSample(utilization: 15, timestamp: range.lowerBound.addingTimeInterval(-3600)),
        ]
        let plotted = GraphDrawer.plottableSamples(samples, in: range)
        #expect(plotted.isEmpty)
    }

    @Test func segmentEntirelyInsideDomainIsUnchanged() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)

        let samples = [
            UtilizationSample(utilization: 5, timestamp: range.lowerBound.addingTimeInterval(600)),
            UtilizationSample(utilization: 15, timestamp: range.lowerBound.addingTimeInterval(1800)),
            UtilizationSample(utilization: 25, timestamp: range.lowerBound.addingTimeInterval(3600)),
        ]
        let plotted = GraphDrawer.plottableSamples(samples, in: range)
        #expect(plotted == samples)
    }

    // MARK: - clipGapSegment

    @Test func gapFullyInsideDomainKeepsBothHatchAndLine() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)
        let before = UtilizationSample(utilization: 10, timestamp: range.lowerBound.addingTimeInterval(600))
        let after = UtilizationSample(utilization: 12, timestamp: range.lowerBound.addingTimeInterval(1800))

        let clipped = GraphDrawer.clipGapSegment(before: before, after: after, in: range)

        #expect(clipped?.hatchStart == before.timestamp)
        #expect(clipped?.hatchEnd == after.timestamp)
        #expect(clipped?.line != nil)
    }

    /// The line is dropped: drawing it would present an out-of-domain sample's value as observed at window start.
    @Test func gapStraddlingWindowStartHatchesFromEdgeButDrawsNoLine() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)
        let before = UtilizationSample(utilization: 25, timestamp: range.lowerBound.addingTimeInterval(-3600))
        let after = UtilizationSample(utilization: 5, timestamp: range.lowerBound.addingTimeInterval(600))

        let clipped = GraphDrawer.clipGapSegment(before: before, after: after, in: range)

        #expect(clipped?.hatchStart == range.lowerBound)
        #expect(clipped?.hatchEnd == after.timestamp)
        #expect(clipped?.line == nil)
    }

    @Test func gapEntirelyBeforeWindowStartProducesNothing() {
        let resetsAt = Date(timeIntervalSince1970: 100_000)
        let range = GraphDrawer.timeRange(resetsAt: resetsAt, duration: fiveHours)
        let before = UtilizationSample(utilization: 25, timestamp: range.lowerBound.addingTimeInterval(-7200))
        let after = UtilizationSample(utilization: 5, timestamp: range.lowerBound.addingTimeInterval(-3600))

        let clipped = GraphDrawer.clipGapSegment(before: before, after: after, in: range)
        #expect(clipped == nil)
    }
}
