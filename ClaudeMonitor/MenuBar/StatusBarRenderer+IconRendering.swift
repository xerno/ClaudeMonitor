import AppKit

extension StatusBarRenderer {
    static let blockedOctagon: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "octagon.fill", accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .medium)
            .applying(.init(paletteColors: [.systemRed]))
        guard let configured = symbol.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false
        return configured
    }()

    static func resolveIcon(
        status: StatusSummary?,
        hasRefreshWarning: Bool
    ) -> (symbolName: String, color: NSColor) {
        if hasRefreshWarning {
            return ("exclamationmark.triangle.fill", .systemYellow)
        }

        guard let worst = status?.components.map(\.status).max() else {
            return ("checkmark.circle.fill", .systemGreen)
        }

        switch worst {
        case .majorOutage:
            return ("xmark.circle.fill", .systemRed)
        case .partialOutage:
            return ("exclamationmark.circle.fill", .systemOrange)
        case .degradedPerformance:
            return ("exclamationmark.circle.fill", .systemYellow)
        case .underMaintenance:
            return ("wrench.and.screwdriver.fill", .systemBlue)
        case .operational, .unknown:
            return ("checkmark.circle.fill", .systemGreen)
        }
    }

    static func updateIcon(
        button: NSStatusBarButton,
        status: StatusSummary?,
        hasRefreshWarning: Bool
    ) {
        let icon = resolveIcon(status: status, hasRefreshWarning: hasRefreshWarning)
        button.image = makeImage(symbolName: icon.symbolName, color: icon.color)
    }

    static func makeImage(symbolName: String, color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
            .applying(.init(paletteColors: [color]))
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
