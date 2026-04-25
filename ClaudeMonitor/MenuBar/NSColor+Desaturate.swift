import AppKit

extension NSColor {
    // HSL desaturation is background-independent so the result is consistent in light and dark mode.
    func desaturatedForStale(
        saturationScale: CGFloat = Constants.Color.staleSaturationScale,
        lightnessShiftToMid: CGFloat = Constants.Color.staleLightnessShiftToMid
    ) -> NSColor {
        let resolved = self.usingColorSpace(.sRGB) ?? self
        let r = resolved.redComponent
        let g = resolved.greenComponent
        let b = resolved.blueComponent
        let a = resolved.alphaComponent

        let cMax = max(r, g, b)
        let cMin = min(r, g, b)
        let delta = cMax - cMin

        let l = (cMax + cMin) / 2

        let s: CGFloat
        if delta == 0 {
            s = 0
        } else {
            s = delta / (1 - abs(2 * l - 1))
        }

        let h: CGFloat
        if delta == 0 {
            h = 0
        } else if cMax == r {
            h = (((g - b) / delta).truncatingRemainder(dividingBy: 6) + 6).truncatingRemainder(dividingBy: 6) / 6
        } else if cMax == g {
            h = ((b - r) / delta + 2) / 6
        } else {
            h = ((r - g) / delta + 4) / 6
        }

        let sNew = min(max(s * saturationScale, 0), 1)
        let lNew = min(max(l + (0.5 - l) * lightnessShiftToMid, 0), 1)

        let c = (1 - abs(2 * lNew - 1)) * sNew
        let x = c * (1 - abs((h * 6).truncatingRemainder(dividingBy: 2) - 1))
        let m = lNew - c / 2

        let (r1, g1, b1): (CGFloat, CGFloat, CGFloat)
        switch Int(h * 6) % 6 {
        case 0: (r1, g1, b1) = (c, x, 0)
        case 1: (r1, g1, b1) = (x, c, 0)
        case 2: (r1, g1, b1) = (0, c, x)
        case 3: (r1, g1, b1) = (0, x, c)
        case 4: (r1, g1, b1) = (x, 0, c)
        default: (r1, g1, b1) = (c, 0, x)
        }

        return NSColor(
            colorSpace: .sRGB,
            components: [r1 + m, g1 + m, b1 + m, a],
            count: 4
        )
    }
}
