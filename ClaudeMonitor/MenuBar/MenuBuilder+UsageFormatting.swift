import AppKit

extension MenuBuilder {
    private static let menuFont = NSFont.menuFont(ofSize: 0)
    private static let boldMenuFont = NSFontManager.shared.convert(menuFont, toHaveTrait: .boldFontMask)

    // Vertical offset that visually centers the bar attachment against the menu font's cap height.
    private static let barAttachmentY: CGFloat = (menuFont.capHeight - Formatting.barImageHeight) / 2

    // Bar image width + suffix "   100%" measured in boldMenuFont — the font that segment is
    // actually drawn in. Measuring it in the regular font leaves the "resets in" column short
    // of where the percentage ends, and the two columns drift apart.
    static func barPercentWidth(_ barWidth: CGFloat = Formatting.barImageWidth) -> CGFloat {
        let suffixStr = NSAttributedString(string: "   100%", attributes: [.font: boldMenuFont])
        return barWidth + suffixStr.size().width
    }

    /// Attributes for a value the eye should land on — the window label, the percentage, the
    /// countdown. Everything else in the row is deliberately quieter.
    private static func valueAttrs(_ style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: boldMenuFont, .paragraphStyle: style, .foregroundColor: NSColor.labelColor]
    }

    /// Attributes for the row's connecting words ("resets in"), which carry no value.
    private static func captionAttrs(_ style: NSParagraphStyle) -> [NSAttributedString.Key: Any] {
        [.font: menuFont, .paragraphStyle: style, .foregroundColor: NSColor.secondaryLabelColor]
    }

    static func usageParagraphStyle(labelColumnWidth: CGFloat, barWidth: CGFloat = Formatting.barImageWidth) -> NSParagraphStyle {
        let padding: CGFloat = 8
        let barStart = labelColumnWidth + padding
        let resetsStart = barStart + barPercentWidth(barWidth) + padding

        let style = NSMutableParagraphStyle()
        style.tabStops = [
            NSTextTab(textAlignment: .left, location: barStart),
            NSTextTab(textAlignment: .right, location: barStart + barPercentWidth(barWidth)),
            NSTextTab(textAlignment: .left, location: resetsStart),
        ]
        return style
    }

    static func maxLabelWidth(labels: [String]) -> CGFloat {
        labels.map { label in
            NSAttributedString(string: "  \(label)  ", attributes: [.font: boldMenuFont]).size().width
        }.max() ?? 0
    }

    private static func barAndPercentSegment(window: UsageWindow, style: NSParagraphStyle, barWidth: CGFloat = Formatting.barImageWidth) -> NSAttributedString {
        let attachment = NSTextAttachment()
        attachment.image = Formatting.progressBarImage(percent: window.utilization, width: barWidth)
        attachment.bounds = NSRect(x: 0, y: barAttachmentY, width: barWidth, height: Formatting.barImageHeight)
        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "\t\(window.utilization)%", attributes: valueAttrs(style)))
        return result
    }

    static func usageAttributedTitle(label: String, window: UsageWindow, style: NSParagraphStyle, barWidth: CGFloat = Formatting.barImageWidth, timeOverride: String? = nil) -> NSAttributedString {
        let text = NSMutableAttributedString(string: "  \(label)  \t", attributes: valueAttrs(style))
        text.append(barAndPercentSegment(window: window, style: style, barWidth: barWidth))
        if let resetsAt = window.resetsAt {
            let timeStr = timeOverride ?? Formatting.timeUntil(resetsAt)
            text.append(NSAttributedString(string: "\t \(String(localized: "menu.resets.prefix", bundle: .module))", attributes: captionAttrs(style)))
            text.append(NSAttributedString(string: timeStr, attributes: valueAttrs(style)))
        }
        return text
    }

    static func buildPrefixes(
        labels: [(tag: Int, label: String, window: UsageWindow?)],
        style: NSParagraphStyle,
        barWidth: CGFloat = Formatting.barImageWidth
    ) -> [Int: NSAttributedString] {
        var prefixes: [Int: NSAttributedString] = [:]
        for (tag, label, window) in labels {
            guard let window, window.resetsAt != nil else { continue }
            let prefix = NSMutableAttributedString(string: "  \(label)  \t", attributes: valueAttrs(style))
            prefix.append(barAndPercentSegment(window: window, style: style, barWidth: barWidth))
            prefix.append(NSAttributedString(string: "\t \(String(localized: "menu.resets.prefix", bundle: .module))", attributes: captionAttrs(style)))
            prefixes[tag] = prefix
        }
        return prefixes
    }

    static func appendTime(to prefix: NSAttributedString, resetsAt: Date, style: NSParagraphStyle) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: prefix)
        text.append(NSAttributedString(
            string: Formatting.timeUntil(resetsAt),
            attributes: valueAttrs(style)
        ))
        return text
    }

    /// The three readings of the status line, separately — `ControlRowView` spaces them across the
    /// row's real width instead of relying on padding baked into one string.
    static func updatedNextSegments(lastRefreshed: Date, interval: TimeInterval?) -> [String] {
        let updated = String(format: String(localized: "menu.updated", bundle: .module),
                             Formatting.absoluteTime(lastRefreshed, .hourMinuteSecond))
        guard let interval else { return [updated] }
        let intervalLabel = String(format: String(localized: "menu.interval", bundle: .module),
                                   Formatting.timeUntil(interval))
        let nextDate = lastRefreshed.addingTimeInterval(interval)
        let nextLabel = String(format: String(localized: "menu.next", bundle: .module),
                               Formatting.absoluteTime(nextDate, .hourMinuteSecond))
        return [updated, intervalLabel, nextLabel]
    }

    /// The same readings as one string, for `NSMenuItem.title` — the accessibility label and the
    /// fallback when the item has no view. The layout no longer depends on this spacing.
    static func updatedNextTitle(lastRefreshed: Date, interval: TimeInterval?) -> String {
        updatedNextSegments(lastRefreshed: lastRefreshed, interval: interval)
            .joined(separator: "        ")
    }
}
