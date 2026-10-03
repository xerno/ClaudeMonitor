import AppKit

/// Catches a badge symbol painted in one colour: it vanishes into the disc and the count is 0.
@MainActor
func pixelCount(in image: NSImage, matching target: NSColor, tolerance: CGFloat = 0.12) -> Int {
    guard let rep = renderedBitmap(of: image) else { return 0 }
    var matches = 0
    for y in 0..<rep.pixelsHigh {
        for x in 0..<rep.pixelsWide where isPixel(rep.colorAt(x: x, y: y), matching: target, tolerance: tolerance) {
            matches += 1
        }
    }
    return matches
}

@MainActor
func renderedBitmap(of image: NSImage, scale: Double = 3.0) -> NSBitmapImageRep? {
    let width = Int(image.size.width * scale), height = Int(image.size.height * scale)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: Double(width), height: Double(height)))
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

func isPixel(_ colour: NSColor?, matching target: NSColor, tolerance: CGFloat = 0.12) -> Bool {
    guard let pixel = colour?.usingColorSpace(.deviceRGB), pixel.alphaComponent > 0.5,
          let wanted = target.usingColorSpace(.deviceRGB) else { return false }
    return abs(pixel.redComponent - wanted.redComponent) < tolerance
        && abs(pixel.greenComponent - wanted.greenComponent) < tolerance
        && abs(pixel.blueComponent - wanted.blueComponent) < tolerance
}
