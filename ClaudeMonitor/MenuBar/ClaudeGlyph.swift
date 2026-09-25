import AppKit

/// The sunburst mark shown beside the dropdown's title.
///
/// Drawn as a path rather than shipped as an asset: images in `Assets.xcassets` are not part of
/// the SPM resource bundle the tests run against (`Package.swift` excludes the catalogue), so an
/// asset could not be tested at all, and `build.sh` copies resources by name. A path costs one
/// small file and stays visible to `pixelCount`.
enum ClaudeGlyph {
    /// Claude's coral. Fixed rather than semantic — it is a brand mark, and it reads on both the
    /// light and the dark menu background.
    static let color = NSColor(srgbRed: 0.839, green: 0.459, blue: 0.337, alpha: 1)

    private static let rayCount = 12
    /// Where each ray starts and ends, as a fraction of the mark's radius. Rays alternate between
    /// the two lengths, which is what gives the mark its uneven, hand-drawn look.
    private static let innerRadius: CGFloat = 0.20
    private static let longRay: CGFloat = 1.0
    private static let shortRay: CGFloat = 0.72
    /// Ray thickness as a fraction of the radius.
    private static let rayWidth: CGFloat = 0.155

    /// The mark at `size` points square, in `color`.
    static func image(size: CGFloat, color: NSColor = color) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            path(in: rect).fill()
            return true
        }
    }

    /// The mark's outline, so tests and callers can measure it without rendering.
    static func path(in rect: NSRect) -> NSBezierPath {
        let centre = NSPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let path = NSBezierPath()
        for index in 0..<rayCount {
            let angle = CGFloat(index) / CGFloat(rayCount) * 2 * .pi
            let outer = index.isMultiple(of: 2) ? longRay : shortRay
            path.append(ray(centre: centre, radius: radius, angle: angle, outer: outer))
        }
        return path
    }

    /// One ray: a capsule running outward from `innerRadius` to `outer`, rotated to `angle`.
    private static func ray(
        centre: NSPoint, radius: CGFloat, angle: CGFloat, outer: CGFloat
    ) -> NSBezierPath {
        let thickness = radius * rayWidth
        let length = radius * (outer - innerRadius)
        let capsule = NSBezierPath(
            roundedRect: NSRect(x: -thickness / 2, y: radius * innerRadius, width: thickness, height: length),
            xRadius: thickness / 2, yRadius: thickness / 2
        )
        var transform = AffineTransform(translationByX: centre.x, byY: centre.y)
        transform.rotate(byRadians: angle)
        capsule.transform(using: transform)
        return capsule
    }
}
