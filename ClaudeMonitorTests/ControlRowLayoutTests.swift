import AppKit
import Testing
@testable import ClaudeMonitor

@MainActor
struct ControlRowLayoutTests {

    private let segments = ["Updated: 8:20:39", "Interval: 5m", "Next: 8:25:39"]

    private func labels(of row: ControlRowView) -> [NSTextField] {
        row.subviews.compactMap { $0 as? NSTextField }
    }

    private func laidOut(width: CGFloat) -> ControlRowView {
        let row = ControlRowView(segments: segments)
        row.frame.size.width = width
        row.layoutSubtreeIfNeeded()
        return row
    }

    /// Direct subviews, no container: `headerShadeMatchesTheControlRow` searches `subviews` non-recursively.
    @Test func everyReadingIsItsOwnDirectSubview() {
        let found = labels(of: ControlRowView(segments: segments))
        #expect(found.count == 3)
        #expect(found.map(\.stringValue) == segments)
    }

    @Test func theOuterReadingsSitOnTheSharedInset() {
        let row = laidOut(width: 460)
        let found = labels(of: row)
        let inset = MenuBuilder.rowTrailingInset
        #expect(found[0].frame.minX == inset)
        #expect(abs(found[2].frame.maxX - (460 - inset)) < 0.5)
    }

    @Test func theReadingsFollowTheRowAsItWidens() {
        let narrow = labels(of: laidOut(width: 360))
        let wide = labels(of: laidOut(width: 520))
        #expect(wide[2].frame.minX > narrow[2].frame.minX)
        #expect(wide[0].frame.minX == narrow[0].frame.minX)
    }

    @Test func theMiddleReadingIsCentredWhenThereIsRoom() {
        let row = laidOut(width: 520)
        let middle = labels(of: row)[1]
        #expect(abs(middle.frame.midX - 260) < 1)
    }

    @Test func theReadingsNeverOverlapWhenTheRowIsTight() {
        let found = labels(of: laidOut(width: ControlRowView(segments: segments).frame.width))
        #expect(found[0].frame.maxX <= found[1].frame.minX)
        #expect(found[1].frame.maxX <= found[2].frame.minX)
    }

    /// A single reading (no poll interval yet) stays left-aligned.
    @Test func oneReadingStaysOnTheLeadingInset() {
        let row = ControlRowView(title: "Updated: 8:20:39")
        row.frame.size.width = 460
        row.layoutSubtreeIfNeeded()
        let found = labels(of: row)
        #expect(found.count == 1)
        #expect(found[0].frame.minX == MenuBuilder.rowTrailingInset)
    }

    /// The labels are rebuilt only when the reading count changes.
    @Test func updatingInPlaceKeepsTheSameLabels() {
        let row = ControlRowView(segments: segments)
        let before = labels(of: row)
        row.update(segments: ["Updated: 9:00:00", "Interval: 1m", "Next: 9:01:00"])
        let after = labels(of: row)
        #expect(before.count == after.count)
        #expect(zip(before, after).allSatisfy { $0 === $1 })
        #expect(row.segments == ["Updated: 9:00:00", "Interval: 1m", "Next: 9:01:00"])
    }
}
