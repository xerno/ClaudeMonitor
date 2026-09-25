import AppKit
import Testing
@testable import ClaudeMonitor

/// The sunburst mark beside the dropdown's title. Drawn as a path rather than shipped as an asset
/// precisely so it can be measured here — an image in `Assets.xcassets` is not in the test bundle.
@MainActor
struct ClaudeGlyphTests {

    @Test func theMarkRendersInItsOwnColour() {
        let image = ClaudeGlyph.image(size: 20)
        #expect(pixelCount(in: image, matching: ClaudeGlyph.color) > 0)
    }

    @Test func theMarkHonoursAnOverriddenColour() {
        let image = ClaudeGlyph.image(size: 20, color: .systemGreen)
        #expect(pixelCount(in: image, matching: .systemGreen) > 0)
        #expect(pixelCount(in: image, matching: ClaudeGlyph.color) == 0)
    }

    /// Rays, not a disc: the centre of the mark is empty, so a solid blob would fail this.
    @Test func theCentreIsOpen() {
        let rect = NSRect(x: 0, y: 0, width: 40, height: 40)
        #expect(!ClaudeGlyph.path(in: rect).contains(NSPoint(x: 20, y: 20)))
    }

    @Test func theMarkFillsTheSizeItIsAskedFor() {
        let image = ClaudeGlyph.image(size: 18)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(ClaudeGlyph.path(in: NSRect(x: 0, y: 0, width: 18, height: 18)).bounds.width <= 18)
    }
}
