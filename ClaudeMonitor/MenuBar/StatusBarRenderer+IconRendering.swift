import AppKit

/// Badge symbols have two layers (inner glyph, enclosing shape) and need two palette colours:
/// one colour for both would hide the glyph.
struct StatusIcon {
    let symbolName: String
    /// nil draws the whole symbol in `color`.
    let glyph: NSColor?
    let color: NSColor
}

extension StatusBarRenderer {
    /// Glyph on dark badges (green, red).
    static let lightGlyph = NSColor.white
    /// Glyph on bright badges (yellow, orange); white would wash out.
    static let darkGlyph = NSColor(calibratedWhite: 0.10, alpha: 1.0)

    static let blockedOctagon: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "octagon.fill", accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .medium)
            .applying(.init(paletteColors: [.systemRed]))
        guard let configured = symbol.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false
        return configured
    }()

    /// Darker than `.systemGreen` to sit quietly in the menu bar; the white checkmark still reads at ≈4.3:1.
    static let healthyIcon = StatusIcon(
        symbolName: "checkmark.circle.fill",
        glyph: lightGlyph,
        color: NSColor(calibratedRed: 0.16, green: 0.55, blue: 0.24, alpha: 1.0)
    )

    static func resolveIcon(
        status: StatusSummary?,
        hasRefreshWarning: Bool
    ) -> StatusIcon {
        if hasRefreshWarning {
            return StatusIcon(symbolName: "exclamationmark.triangle.fill", glyph: darkGlyph, color: .systemYellow)
        }

        guard let worst = status?.components.map(\.status).max() else {
            return Self.healthyIcon
        }

        switch worst {
        case .majorOutage:
            return StatusIcon(symbolName: "xmark.circle.fill", glyph: lightGlyph, color: .systemRed)
        case .partialOutage:
            return StatusIcon(symbolName: "exclamationmark.circle.fill", glyph: darkGlyph, color: .systemOrange)
        case .degradedPerformance:
            return StatusIcon(symbolName: "exclamationmark.circle.fill", glyph: darkGlyph, color: .systemYellow)
        case .underMaintenance:
            // No enclosing shape, so single-colour.
            return StatusIcon(symbolName: "wrench.and.screwdriver.fill", glyph: nil, color: .systemBlue)
        case .operational, .unknown:
            return Self.healthyIcon
        }
    }

    static func updateIcon(
        button: NSStatusBarButton,
        status: StatusSummary?,
        hasRefreshWarning: Bool
    ) {
        button.image = makeImage(icon: resolveIcon(status: status, hasRefreshWarning: hasRefreshWarning))
    }

    static func makeImage(icon: StatusIcon) -> NSImage? {
        makeImage(symbolName: icon.symbolName, color: icon.color, glyph: icon.glyph)
    }

    static func makeImage(symbolName: String, color: NSColor, glyph: NSColor? = nil) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
        // Palette order is glyph first, enclosing shape second.
        let palette: [NSColor] = glyph.map { [$0, color] } ?? [color]
        let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
            .applying(.init(paletteColors: palette))
        guard let configured = symbol.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false

        let verticalOffset: CGFloat = 2.0
        let horizontalTrim: CGFloat = 0.5
        let newSize = NSSize(width: configured.size.width - horizontalTrim * 2,
                             height: configured.size.height + verticalOffset)
        let shifted = NSImage(size: newSize, flipped: false) { rect in
            configured.draw(in: NSRect(x: -horizontalTrim, y: verticalOffset,
                                       width: configured.size.width,
                                       height: configured.size.height))
            return true
        }
        shifted.isTemplate = false
        return shifted
    }
}
