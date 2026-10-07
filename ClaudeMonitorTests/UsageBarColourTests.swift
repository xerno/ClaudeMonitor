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

    @Test func aLowFillStaysInsideTheTrack() {
        for percent in [1, 2, 5, 9] {
            let image = Formatting.progressBarImage(percent: percent)
            #expect(pixelCount(in: image, matching: .restingAccent) > 0, "\(percent)% draws nothing")
            #expect(fillPixelsOutsideTrack(in: image) == 0, "\(percent)% spills past the track")
        }
    }

    @Test func aWideFillKeepsItsRoundedEnd() throws {
        let rep = try #require(renderedBitmap(of: Formatting.progressBarImage(percent: 50)))
        let end = Formatting.barImageWidth / 2
        #expect(isFill(rep, at: CGPoint(x: end - 4, y: Formatting.barImageHeight / 2)))
        #expect(!isFill(rep, at: CGPoint(x: end - 1, y: 0.5)), "the fill's top-right corner is square")
    }

    private func fillPixelsOutsideTrack(in image: NSImage) -> Int {
        guard let rep = renderedBitmap(of: image) else { return -1 }
        let size = image.size, radius = size.height / 2
        var outside = 0
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide where isPixel(rep.colorAt(x: x, y: y), matching: .restingAccent) {
                let px = (Double(x) + 0.5) / pixelScale, py = (Double(y) + 0.5) / pixelScale
                let nearestOnSpine = min(max(px, radius), size.width - radius)
                if hypot(px - nearestOnSpine, py - radius) > radius + 0.5 { outside += 1 }
            }
        }
        return outside
    }

    private func isFill(_ rep: NSBitmapImageRep, at point: CGPoint) -> Bool {
        isPixel(rep.colorAt(x: Int(point.x * pixelScale), y: Int(point.y * pixelScale)), matching: .restingAccent)
    }
}
