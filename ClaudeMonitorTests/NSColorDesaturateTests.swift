import Testing
import AppKit
@testable import ClaudeMonitor

struct NSColorDesaturateTests {

    private func hsl(of color: NSColor) -> (h: CGFloat, s: CGFloat, l: CGFloat) {
        let c = color.usingColorSpace(.sRGB)!
        let r = c.redComponent, g = c.greenComponent, b = c.blueComponent
        let cMax = max(r, g, b), cMin = min(r, g, b)
        let delta = cMax - cMin
        let l = (cMax + cMin) / 2
        let s: CGFloat = delta == 0 ? 0 : delta / (1 - abs(2 * l - 1))
        var h: CGFloat = 0
        if delta != 0 {
            if cMax == r { h = (((g - b) / delta).truncatingRemainder(dividingBy: 6) + 6).truncatingRemainder(dividingBy: 6) / 6 }
            else if cMax == g { h = ((b - r) / delta + 2) / 6 }
            else { h = ((r - g) / delta + 4) / 6 }
        }
        return (h, s, l)
    }

    @Test func pureRedBecomesLessSaturatedAndLighter() {
        let red = NSColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
        let result = red.desaturatedForStale()
        let (_, s, _) = hsl(of: result)
        let orig = hsl(of: red)
        #expect(result.usingColorSpace(.sRGB)!.redComponent > 0.5)
        #expect(result.usingColorSpace(.sRGB)!.greenComponent > 0)
        #expect(result.usingColorSpace(.sRGB)!.blueComponent > 0)
        #expect(s < orig.s)
    }

    @Test func pureWhiteShiftsTowardMidGray() {
        let white = NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        let result = white.desaturatedForStale()
        let r = result.usingColorSpace(.sRGB)!
        #expect(r.redComponent < 1.0)
        #expect(r.redComponent > 0.5)
        #expect(abs(r.redComponent - r.greenComponent) < 0.001)
        #expect(abs(r.redComponent - r.blueComponent) < 0.001)
    }

    @Test func pureBlackShiftsTowardMidGray() {
        let black = NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
        let result = black.desaturatedForStale()
        let r = result.usingColorSpace(.sRGB)!
        #expect(r.redComponent > 0)
        #expect(r.redComponent < 0.5)
        #expect(abs(r.redComponent - r.greenComponent) < 0.001)
        #expect(abs(r.redComponent - r.blueComponent) < 0.001)
    }

    @Test func alphaPreserved() {
        let color = NSColor(srgbRed: 0.5, green: 0.2, blue: 0.8, alpha: 0.7)
        let result = color.desaturatedForStale()
        #expect(abs(result.usingColorSpace(.sRGB)!.alphaComponent - 0.7) < 0.001)
    }

    @Test func identityWithScaleOneAndNoLightnessShift() {
        let color = NSColor(srgbRed: 0.3, green: 0.6, blue: 0.9, alpha: 1)
        let result = color.desaturatedForStale(saturationScale: 1.0, lightnessShiftToMid: 0.0)
        let orig = color.usingColorSpace(.sRGB)!
        let res = result.usingColorSpace(.sRGB)!
        #expect(abs(orig.redComponent - res.redComponent) < 0.001)
        #expect(abs(orig.greenComponent - res.greenComponent) < 0.001)
        #expect(abs(orig.blueComponent - res.blueComponent) < 0.001)
    }

    @Test func catalogColorDoesNotCrash() {
        let result = NSColor.systemRed.desaturatedForStale()
        let r = result.usingColorSpace(.sRGB)!
        #expect(r.redComponent >= 0 && r.redComponent <= 1)
        #expect(r.greenComponent >= 0 && r.greenComponent <= 1)
        #expect(r.blueComponent >= 0 && r.blueComponent <= 1)
    }
}
