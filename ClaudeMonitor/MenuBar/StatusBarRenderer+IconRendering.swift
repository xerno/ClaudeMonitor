import AppKit

/// A menu-bar status icon: the SF Symbol plus the colours its layers are drawn in.
///
/// Badge symbols (`checkmark.circle.fill`, `xmark.circle.fill`, `exclamationmark.triangle.fill`, …)
/// carry two layers — the inner glyph and the enclosing shape — so they need two palette colours.
/// Painting both layers in one colour hides the glyph entirely (a green checkmark on a green disc).
/// Symbols with no enclosing shape (`wrench.and.screwdriver.fill`, whose layers are the wrench and
/// the screwdriver) leave `glyph` nil and are drawn in a single colour.
struct StatusIcon {
    let symbolName: String
    /// Colour for the inner glyph layer; nil draws the whole symbol in `color`.
    let glyph: NSColor?
    /// Colour for the enclosing shape — the whole symbol when `glyph` is nil.
    let color: NSColor
}

extension StatusBarRenderer {
    /// Glyph colour for dark badges (green, red): a white checkmark / cross reads clearly.
    static let lightGlyph = NSColor.white
    /// Glyph colour for bright badges (yellow, orange), where white would wash out.
    static let darkGlyph = NSColor(calibratedWhite: 0.10, alpha: 1.0)

    static let blockedOctagon: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "octagon.fill", accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .medium)
            .applying(.init(paletteColors: [.systemRed]))
        guard let configured = symbol.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false
        return configured
    }()

    /// The healthy "running" indicator: a white checkmark on a calm green disc. The green is darker
    /// than `.systemGreen` so it sits quietly in the menu bar while still carrying a legible white
    /// checkmark (≈4.3:1 contrast).
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
            // No enclosing shape to sit inside, so it stays a single-colour symbol.
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
