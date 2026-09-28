import AppKit

/// Drawn as a path, not an asset: `Assets.xcassets` is excluded from the SPM test bundle, so an
/// asset would be untestable.
enum ClaudeGlyph {
    /// Fixed brand coral; reads on both light and dark menus.
    static let color = NSColor(srgbRed: 0.839, green: 0.459, blue: 0.337, alpha: 1)

    private static let rayCount = 12
    /// Ray start and end, as fractions of the radius.
    private static let innerRadius: CGFloat = 0.20
    private static let longRay: CGFloat = 1.0
    private static let shortRay: CGFloat = 0.72
    /// Ray thickness as a fraction of the radius.
    private static let rayWidth: CGFloat = 0.155

    static func image(size: CGFloat, color: NSColor = color) -> NSImage {
        NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            color.setFill()
            path(in: rect).fill()
            return true
        }
    }

    /// Separate from `image` so tests can measure it without rendering.
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
