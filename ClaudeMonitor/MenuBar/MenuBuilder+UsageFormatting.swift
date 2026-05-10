import AppKit

extension MenuBuilder {
    private static let menuFont = NSFont.menuFont(ofSize: 0)
    private static let boldMenuFont = NSFontManager.shared.convert(menuFont, toHaveTrait: .boldFontMask)

    // Vertical offset that visually centers the bar attachment against the menu font's cap height.
    private static let barAttachmentY: CGFloat = (menuFont.capHeight - Formatting.barImageHeight) / 2

    // Bar image width + suffix "   100%" measured in menuFont (the font used for that segment).
    static func barPercentWidth(_ barWidth: CGFloat = Formatting.barImageWidth) -> CGFloat {
        let suffixStr = NSAttributedString(string: "   100%", attributes: [.font: menuFont])
        return barWidth + suffixStr.size().width
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
            NSAttributedString(string: "  \(label)  ", attributes: [.font: menuFont]).size().width
        }.max() ?? 0
    }

    private static func barAndPercentSegment(window: UsageWindow, style: NSParagraphStyle, barWidth: CGFloat = Formatting.barImageWidth) -> NSAttributedString {
        let menuAttrs: [NSAttributedString.Key: Any] = [.font: menuFont, .paragraphStyle: style]
        let attachment = NSTextAttachment()
        attachment.image = Formatting.progressBarImage(percent: window.utilization, width: barWidth)
        attachment.bounds = NSRect(x: 0, y: barAttachmentY, width: barWidth, height: Formatting.barImageHeight)
        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "\t\(window.utilization)%", attributes: menuAttrs))
        return result
    }

    static func usageAttributedTitle(label: String, window: UsageWindow, style: NSParagraphStyle, barWidth: CGFloat = Formatting.barImageWidth, timeOverride: String? = nil) -> NSAttributedString {
        let menuAttrs: [NSAttributedString.Key: Any] = [.font: menuFont, .paragraphStyle: style]
        let text = NSMutableAttributedString(string: "  \(label)  \t", attributes: menuAttrs)
        text.append(barAndPercentSegment(window: window, style: style, barWidth: barWidth))
        if let resetsAt = window.resetsAt {
            let timeStr = timeOverride ?? Formatting.timeUntil(resetsAt)
            text.append(NSAttributedString(string: "\t \(String(localized: "menu.resets.prefix", bundle: .module))", attributes: menuAttrs))
            text.append(NSAttributedString(string: timeStr, attributes: [.font: boldMenuFont, .paragraphStyle: style]))
        }
        return text
    }

    static func buildPrefixes(
        labels: [(tag: Int, label: String, window: UsageWindow?)],
        style: NSParagraphStyle,
        barWidth: CGFloat = Formatting.barImageWidth
    ) -> [Int: NSAttributedString] {
        var prefixes: [Int: NSAttributedString] = [:]
        let menuAttrs: [NSAttributedString.Key: Any] = [.font: menuFont, .paragraphStyle: style]
        for (tag, label, window) in labels {
            guard let window, window.resetsAt != nil else { continue }
            let prefix = NSMutableAttributedString(string: "  \(label)  \t", attributes: menuAttrs)
            prefix.append(barAndPercentSegment(window: window, style: style, barWidth: barWidth))
            prefix.append(NSAttributedString(string: "\t \(String(localized: "menu.resets.prefix", bundle: .module))", attributes: menuAttrs))
            prefixes[tag] = prefix
        }
        return prefixes
    }

    static func appendTime(to prefix: NSAttributedString, resetsAt: Date, style: NSParagraphStyle) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: prefix)
        text.append(NSAttributedString(
            string: Formatting.timeUntil(resetsAt),
            attributes: [.font: boldMenuFont, .paragraphStyle: style]
        ))
        return text
    }

    static func updatedNextTitle(lastRefreshed: Date, interval: TimeInterval?) -> String {
        let updated = String(format: String(localized: "menu.updated", bundle: .module),
                             lastRefreshed.formatted(.dateTime.hour().minute().second()))
        guard let interval else { return updated }
        let intervalLabel = String(format: String(localized: "menu.interval", bundle: .module),
                                   Formatting.timeUntil(interval))
        let nextDate = lastRefreshed.addingTimeInterval(interval)
        let nextLabel = String(format: String(localized: "menu.next", bundle: .module),
                               nextDate.formatted(.dateTime.hour().minute().second()))
        return "\(updated)        \(intervalLabel)        \(nextLabel)"
    }
}
