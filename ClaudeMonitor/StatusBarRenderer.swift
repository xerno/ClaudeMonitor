import AppKit

enum StatusBarRenderer {
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
        default:
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
        let regularFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .regular)
        let boldFont = NSFont.monospacedDigitSystemFont(ofSize: fontSize, weight: .bold)

        if !hasCredentials {
            button.attributedTitle = NSAttributedString(string: "-%", attributes: [
                .foregroundColor: NSColor.secondaryLabelColor, .font: regularFont,
            ])
            return
        }

        guard let usage, !isStale else {
            button.attributedTitle = NSAttributedString(string: "…", attributes: [
                .foregroundColor: NSColor.secondaryLabelColor, .font: regularFont,
            ])
            return
        }

        let parts = NSMutableAttributedString()

        func appendWindow(_ window: UsageWindow, duration: TimeInterval) {
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
                .foregroundColor: style.color,
                .font: style.isBold ? boldFont : regularFont,
            ]))
        }

        if let w = usage.fiveHour {
            appendWindow(w, duration: Constants.UsageWindows.fiveHourDuration)
        }

        let showSevenDay = usage.sevenDay.map {
            Formatting.shouldShowInMenuBar(
                utilization: $0.utilization, resetsAt: $0.resetsAt,
                windowDuration: Constants.UsageWindows.sevenDayDuration)
        } ?? false
        let showSonnet = usage.sevenDaySonnet.map {
            Formatting.shouldShowInMenuBar(
                utilization: $0.utilization, resetsAt: $0.resetsAt,
                windowDuration: Constants.UsageWindows.sevenDayDuration)
        } ?? false

        if showSevenDay || showSonnet, let w = usage.sevenDay {
            appendWindow(w, duration: Constants.UsageWindows.sevenDayDuration)
        }
        if showSonnet, let w = usage.sevenDaySonnet {
            appendWindow(w, duration: Constants.UsageWindows.sevenDayDuration)
        }

        button.attributedTitle = parts.length > 0 ? parts : NSAttributedString()
    }

    static func makeImage(symbolName: String, color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
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
