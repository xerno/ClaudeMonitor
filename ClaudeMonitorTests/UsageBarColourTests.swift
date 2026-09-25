import AppKit
import Testing
@testable import ClaudeMonitor

/// The bar's fill. The reference design shows a blue bar at 100%, but every other surface in the
/// app treats 100% as blocked and paints it red — so the bar resolves red there too, and these
/// pin that the two rules cannot drift apart again.
///
/// The resting fill is `restingAccent` — the same green as "All systems operational", so a calm
/// bar and a calm service list read as one state rather than two.
@MainActor
struct UsageBarColourTests {

    @Test func aWindowWithHeadroomIsTheRestingFill() {
        #expect(Formatting.barFillColor(percent: 0) == .restingAccent)
        #expect(Formatting.barFillColor(percent: 99) == .restingAccent)
    }

    @Test func anExhaustedWindowIsRed() {
        #expect(Formatting.barFillColor(percent: 100) == .systemRed)
        #expect(Formatting.barFillColor(percent: 140) == .systemRed)
    }

    /// The threshold is the shared constant, not a second literal 100 that could be edited alone.
    @Test func theSwitchHappensAtTheBlockedThreshold() {
        let blocked = Constants.Projection.blockedUtilization
        #expect(Formatting.barFillColor(percent: blocked - 1) == .restingAccent)
        #expect(Formatting.barFillColor(percent: blocked) == .systemRed)
    }

    @Test func theRenderedBarActuallyCarriesThatFill() {
        let image = Formatting.progressBarImage(percent: 60)
        #expect(pixelCount(in: image, matching: .restingAccent) > 0)
        #expect(pixelCount(in: image, matching: .systemRed) == 0)
    }

    @Test func anEmptyBarDrawsNoFillAtAll() {
        let image = Formatting.progressBarImage(percent: 0)
        #expect(pixelCount(in: image, matching: .restingAccent) == 0)
        #expect(pixelCount(in: image, matching: .systemRed) == 0)
    }
}
