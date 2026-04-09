import AppKit

@MainActor
enum StatusBarRenderer {
    private static let iconPointSize: CGFloat = 14

    private static let blockedOctagon: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "octagon.fill", accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .medium)
            .applying(.init(paletteColors: [.systemRed]))
        guard let configured = symbol.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false
        return configured
    }()

    static func updateIcon(
        button: NSStatusBarButton,
        status: StatusSummary?,
        hasRefreshWarning: Bool
    ) {
        if hasRefreshWarning {
            button.image = makeImage(symbolName: "exclamationmark.triangle.fill", color: .systemYellow)
            return
        }

        guard let worst = status?.components.map(\.status).max() else {
            button.image = makeImage(symbolName: "checkmark.circle.fill", color: .systemGreen)
            return
        }

        switch worst {
        case .majorOutage:
            button.image = makeImage(symbolName: "xmark.circle.fill", color: .systemRed)
        case .partialOutage:
            button.image = makeImage(symbolName: "exclamationmark.circle.fill", color: .systemOrange)
        case .degradedPerformance:
            button.image = makeImage(symbolName: "exclamationmark.circle.fill", color: .systemYellow)
        case .underMaintenance:
            button.image = makeImage(symbolName: "wrench.and.screwdriver.fill", color: .systemBlue)
        case .operational, .unknown:
            button.image = makeImage(symbolName: "checkmark.circle.fill", color: .systemGreen)
        }
    }

    static func updateText(
        button: NSStatusBarButton,
        usage: UsageResponse?,
        hasCredentials: Bool,
        isStale: Bool
    ) {
        let fontSize = NSFont.systemFontSize
        if !hasCredentials {
            button.attributedTitle = noCredentialsTitle(fontSize: fontSize)
            return
        }
        guard let usage, !isStale else {
            button.attributedTitle = loadingTitle(fontSize: fontSize)
            return
        }
        if let blockedUntil = Formatting.blockingLimit(usage) {
            button.attributedTitle = blockedTitle(blockedUntil: blockedUntil, fontSize: fontSize)
            return
        }
        button.attributedTitle = usageTitle(usage: usage, fontSize: fontSize)
    }

    private static func noCredentialsTitle(fontSize: CGFloat) -> NSAttributedString {
        let regularFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        return NSAttributedString(string: "-%", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: regularFont,
        ])
    }

    private static func loadingTitle(fontSize: CGFloat) -> NSAttributedString {
        let regularFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        return NSAttributedString(string: "…", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: regularFont,
        ])
    }

    private static func blockedTitle(blockedUntil: Date, fontSize: CGFloat) -> NSAttributedString {
        let regularFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let countdown = Formatting.timeUntil(blockedUntil)
        let result = NSMutableAttributedString()
        if let octagon = blockedOctagon {
            let attachment = NSTextAttachment()
            attachment.image = octagon
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " ", attributes: [.font: regularFont]))
        }
        result.append(NSAttributedString(string: countdown, attributes: [
            .foregroundColor: NSColor.systemRed,
            .font: regularFont,
        ]))
        result.append(NSAttributedString(string: " ", attributes: [.font: regularFont]))
        return result
    }

    private static func usageTitle(usage: UsageResponse, fontSize: CGFloat) -> NSAttributedString {
        let regularFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)
        let parts = NSMutableAttributedString()

        guard let first = usage.entries.first else { return NSAttributedString() }

        appendWindow(first.window, duration: first.duration,
                     into: parts, regularFont: regularFont, boldFont: boldFont)

        let rest = usage.entries.dropFirst()
        let visible = secondaryWindowKeys(from: rest)
        for entry in rest where visible.contains(entry.key) {
            appendWindow(entry.window, duration: entry.duration,
                         into: parts, regularFont: regularFont, boldFont: boldFont)
        }

        return parts.length > 0 ? parts : NSAttributedString()
    }

    static func secondaryWindowKeys(from entries: some Collection<WindowEntry>) -> Set<String> {
        var keys = Set<String>()
        for entry in entries {
            guard Formatting.shouldShowInMenuBar(
                utilization: entry.window.utilization,
                resetsAt: entry.window.resetsAt,
                windowDuration: entry.duration
            ) else { continue }
            keys.insert(entry.key)
            if entry.modelScope != nil,
               let allModels = entries.first(where: { $0.durationLabel == entry.durationLabel && $0.modelScope == nil }) {
                keys.insert(allModels.key)
            }
        }
        return keys
    }

    private static func appendWindow(
        _ window: UsageWindow,
        duration: TimeInterval,
        into parts: NSMutableAttributedString,
        regularFont: NSFont,
        boldFont: NSFont
    ) {
        if parts.length > 0 {
            parts.append(NSAttributedString(string: " | ", attributes: [
                .foregroundColor: NSColor.secondaryLabelColor, .font: regularFont,
            ]))
        }
        let style = Formatting.usageStyle(
            utilization: window.utilization,
            resetsAt: window.resetsAt,
            windowDuration: duration
        )
        parts.append(NSAttributedString(string: "\(window.utilization)%", attributes: [
            .foregroundColor: nsColor(for: style.level),
            .font: style.isBold ? boldFont : regularFont,
        ]))
    }

    static func nsColor(for level: Formatting.UsageLevel) -> NSColor {
        switch level {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        }
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
