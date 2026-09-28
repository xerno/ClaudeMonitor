import AppKit
import Testing
@testable import ClaudeMonitor

/// The reference design shows a blue bar at 100%, but every other surface paints blocked (100%) red, so the bar does too.
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

    /// The shared constant, not a second literal 100 that could be edited alone.
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
