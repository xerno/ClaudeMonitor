import Testing
import Foundation
import AppKit
@testable import ClaudeMonitor

struct GraphDrawerCreditTests {
    private let rect = NSRect(x: 0, y: 0, width: 100, height: 200)
    private let windowStart = Date(timeIntervalSince1970: 0)
    private let resetsAt = Date(timeIntervalSince1970: 1000)

    private var timeRange: ClosedRange<Date> { windowStart...resetsAt }

    private func makeEntry(utilization: Int) -> WindowEntry {
        WindowEntry(
            key: "five_hour", duration: 1000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: utilization, resetsAt: resetsAt)
        )
    }

    private func makeAnalysis(utilization: Int, events: [UsageEvent] = []) -> WindowAnalysis {
        WindowAnalysis(
            entry: makeEntry(utilization: utilization), samples: [], events: events, consumptionRate: 0,
            projectedAtReset: Double(utilization), timeToLimit: nil, rateSource: .insufficient,
            style: Formatting.UsageStyle(level: .normal, isBold: false),
            segments: [], timeSinceLastChange: nil, recentRate: nil
        )
    }

    private func drawer(events: [UsageEvent]) -> GraphDrawer {
        GraphDrawer(
            analyses: [makeAnalysis(utilization: 10, events: events)], selectedIndex: 0, graphRect: rect,
            now: resetsAt
        )
    }

    @Test func oneCreditEventProducesMarkerAtExpectedX() {
        let at = Date(timeIntervalSince1970: 500)
        let event = UsageEvent(at: at, kind: .credit, from: 32, to: 0, fromTimestamp: nil)
        let markers = drawer(events: [event]).visibleCreditMarkers(in: rect, timeRange: timeRange)

        #expect(markers.count == 1)
        #expect(markers[0].x == rect.minX + rect.width / 2)
    }

    @Test func twoCreditEventsBothProduceMarkers() {
        let first = UsageEvent(at: Date(timeIntervalSince1970: 200), kind: .credit, from: 55, to: 0, fromTimestamp: nil)
        let second = UsageEvent(at: Date(timeIntervalSince1970: 800), kind: .credit, from: 40, to: 0, fromTimestamp: nil)
        let markers = drawer(events: [first, second]).visibleCreditMarkers(in: rect, timeRange: timeRange)

        #expect(markers.count == 2)
        #expect(markers[0].x < markers[1].x)
    }

    @Test func noEventsProducesNoMarkers() {
        let markers = drawer(events: []).visibleCreditMarkers(in: rect, timeRange: timeRange)
        #expect(markers.isEmpty)
    }

    @Test func eventOutsideVisibleRangeIsNotDrawn() {
        let outOfRange = UsageEvent(at: Date(timeIntervalSince1970: -500), kind: .credit, from: 20, to: 0, fromTimestamp: nil)
        let markers = drawer(events: [outOfRange]).visibleCreditMarkers(in: rect, timeRange: timeRange)
        #expect(markers.isEmpty)
    }

    @Test func markerYPositionsReflectFromAndToUtilization() {
        let event = UsageEvent(at: Date(timeIntervalSince1970: 500), kind: .credit, from: 50, to: 0, fromTimestamp: nil)
        let markers = drawer(events: [event]).visibleCreditMarkers(in: rect, timeRange: timeRange)

        #expect(markers.count == 1)
        #expect(markers[0].yFrom == rect.maxY - rect.height * 0.5)
        #expect(markers[0].yTo == rect.maxY)
    }

    @Test func creditDescriptionIsLocalizedNotRawKey() {
        let event = UsageEvent(at: Date(), kind: .credit, from: 32, to: 0, fromTimestamp: nil)
        let text = Formatting.creditDescription(for: event)
        #expect(text != "graph.credit.description")
        #expect(text.contains("32"))
        #expect(text.contains("0"))
    }

    @Test func statsLabelAppendsMostRecentCreditDescription() {
        let older = UsageEvent(at: Date(timeIntervalSince1970: 100), kind: .credit, from: 90, to: 0, fromTimestamp: nil)
        let newer = UsageEvent(at: Date(timeIntervalSince1970: 900), kind: .credit, from: 32, to: 0, fromTimestamp: nil)
        let analysis = makeAnalysis(utilization: 10, events: [older, newer])
        let text = Formatting.statsLabelText(analysis: analysis, now: resetsAt)
        #expect(text.contains("32"))
    }

    @Test func noEventsProducesNoCreditSuffix() {
        let text = Formatting.statsLabelText(analysis: makeAnalysis(utilization: 10, events: []), now: resetsAt)
        let event = UsageEvent(at: Date(timeIntervalSince1970: 500), kind: .credit, from: 32, to: 0, fromTimestamp: nil)
        let creditSuffixThatWouldBeAppended = Formatting.creditDescription(for: event)

        // "·" is the separator statsLabelText puts between the base text and a credit description.
        #expect(!text.contains(creditSuffixThatWouldBeAppended))
        #expect(!text.contains("·"))
    }
}
