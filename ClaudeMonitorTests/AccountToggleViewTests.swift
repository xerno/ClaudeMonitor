import AppKit
import Testing
@testable import ClaudeMonitor

/// The account switcher is drawn, not built from `NSSegmentedControl`, so nothing but these
/// measurements stands between the coral and a future edit that quietly drops it.
@MainActor
struct AccountToggleViewTests {
    private let names = ["Rennie", "Marek"]

    private func segments(_ names: [String]) -> [AccountSegment] {
        names.map { AccountSegment(id: $0, label: $0, toolTip: $0) }
    }

    private func switcher(_ names: [String], selectedIndex: Int) -> HeaderAccountSwitcher {
        HeaderAccountSwitcher(segments: segments(names), activeIndex: selectedIndex, onSelect: { _ in })
    }

    // MARK: - Colour

    @Test func theActiveSegmentCarriesTheMarksCoral() {
        let image = AccountTogglePill.image(labels: names, selectedIndex: 0)
        #expect(pixelCount(in: image, matching: ClaudeGlyph.color) > 0)
    }

    /// The label has to survive the fill it sits on. White would be 3.2:1 here, which is why the
    /// dark glyph colour is used — this fails if someone swaps it back.
    @Test func theActiveLabelIsReadableOnTheCoral() {
        let image = AccountTogglePill.image(labels: names, selectedIndex: 0)
        #expect(pixelCount(in: image, matching: AccountTogglePill.selectedText) > 0)
    }

    /// Without this, `theActiveSegmentCarriesTheMarksCoral` could pass for the wrong reason — a
    /// pill that painted coral everywhere, or a stray coral pixel from the track, would satisfy it.
    @Test func aPillWithNothingSelectedHasNoCoralAtAll() {
        let image = AccountTogglePill.image(labels: names, selectedIndex: -1)
        #expect(pixelCount(in: image, matching: ClaudeGlyph.color) == 0)
    }

    /// The fill has to follow the selection, not flood the pill. Measured with two very different
    /// label widths: filling the wide segment must cover far more than filling the narrow one.
    @Test func theFillFollowsTheSelectedSegmentRatherThanTheWholePill() {
        let labels = ["A", "Considerably longer"]
        let narrow = pixelCount(in: AccountTogglePill.image(labels: labels, selectedIndex: 0),
                                matching: ClaudeGlyph.color)
        let wide = pixelCount(in: AccountTogglePill.image(labels: labels, selectedIndex: 1),
                              matching: ClaudeGlyph.color)
        #expect(narrow > 0)
        #expect(wide > narrow * 2)
    }

    // MARK: - Geometry

    /// The header sizes the switcher from `fittingSize`. A drawn view has no constraints, so
    /// without `intrinsicContentSize` it collapses to nothing and vanishes from the header.
    @Test func theViewReportsARealSizeSoTheHeaderCanPlaceIt() {
        let view = AccountToggleView(frame: .zero)
        view.configure(with: switcher(names, selectedIndex: 0))
        #expect(view.intrinsicContentSize.width > 0)
        #expect(view.intrinsicContentSize.height == AccountTogglePill.height)
        #expect(view.fittingSize.width > 0)
    }

    @Test func segmentsTileTheWholePillWithoutOverlapping() {
        let rect = NSRect(origin: .zero, size: AccountTogglePill.size(labels: names))
        let rects = AccountTogglePill.segmentRects(labels: names, in: rect)
        #expect(rects.count == names.count)
        #expect(rects[0].maxX == rects[1].minX)
        #expect(abs(rects[1].maxX - rect.maxX) < 1)
    }

    @Test func aLongerNameGetsAWiderSegment() {
        let widths = AccountTogglePill.segmentWidths(["A", "Considerably longer"])
        #expect(widths[1] > widths[0])
    }

    // MARK: - Selection

    @Test func configureKeepsTheLabelsItWasGiven() {
        let view = AccountToggleView(frame: .zero)
        view.configure(with: switcher(names, selectedIndex: 1))
        #expect(view.currentSegments.map(\.label) == names)
    }

    /// An index outside the set must not be stored — the builder maps the index back to a profile
    /// id, so a stale one would switch to the wrong account.
    @Test func configureIgnoresASelectionOutsideTheSegments() {
        let view = AccountToggleView(frame: .zero)
        view.configure(with: switcher(names, selectedIndex: 0))
        view.configure(with: switcher(names, selectedIndex: 7))
        #expect(view.selectedIndex == 0)
        #expect(view.currentSegments.map(\.label) == names)
    }
}
