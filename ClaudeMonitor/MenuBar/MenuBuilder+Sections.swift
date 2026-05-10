import AppKit

extension MenuBuilder {
    // MARK: - Section Builders

    // The fresh UsageGraphView allocated here is only used on the first populate;
    // reconcile() preserves the existing view-based item by tag, so on subsequent
    // populates this instance is discarded and UI state (selectedIndex, hover)
    // survives across polling cycles.
    static func usageGraphPlaceholder() -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = usageGraphTag
        item.isEnabled = false
        item.view = UsageGraphView()
        return item
    }

    // Invisible navigable item that absorbs NSMenu's auto-highlight on open, so the
    // first real usage row doesn't appear pre-selected. Custom 1×1 view.
    static func usageSentinelItem(target: any MenuActions) -> NSMenuItem {
        let item = NSMenuItem()
        item.target = target
        item.action = #selector(MenuActions.didSelectSentinel)
        let view = SentinelView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        item.view = view
        return item
    }

    static func usageItems(state: MonitorState, target: (any MenuActions)?) -> ([NSMenuItem], UsageCache) {
        if !state.hasCredentials {
            return ([staticItem("  ⚙  " + String(localized: "menu.credentials.configure", bundle: .module), tag: usagePlaceholderTag)], UsageCache())
        }
        guard let usage = state.currentUsage else {
            return ([staticItem("  " + String(localized: "menu.loading", bundle: .module), tag: usagePlaceholderTag)], UsageCache())
        }
        let labels = usageLabels(usage: usage)
        let barWidth = usage.hasAnyModelSpecific ? Formatting.barImageWidth : Formatting.barImageWidthWide
        let style = usageParagraphStyle(labelColumnWidth: maxLabelWidth(labels: labels.map(\.label)), barWidth: barWidth)
        let prefixes = buildPrefixes(labels: labels, style: style, barWidth: barWidth)
        let cache = UsageCache(labels: labels, style: style, prefixes: prefixes)

        var items: [NSMenuItem] = []
        if let target {
            items.append(usageSentinelItem(target: target))
        }
        for (tag, label, window) in labels {
            guard let window else { continue }
            items.append(usageItem(label: label, window: window, tag: tag, style: style, barWidth: barWidth, target: target))
        }
        return (items, cache)
    }

    static func serviceItems(state: MonitorState) -> [NSMenuItem] {
        guard let components = state.currentStatus?.components else {
            return [staticItem("  " + String(localized: "menu.loading", bundle: .module), tag: servicesPlaceholderTag)]
        }
        return components.sorted(by: { $0.name < $1.name }).enumerated().map { index, component in
            let name = truncatedName(component.name)
            return staticItem("  \(component.status.dot)  \(name)  –  \(component.status.label)",
                              tag: serviceBaseTag + index)
        }
    }

    static func incidentItem(incident: Incident, tag: Int, target: any MenuActions) -> NSMenuItem {
        let item = NSMenuItem(title: "  ⚠︎  \(incident.name)",
                              action: #selector(MenuActions.openIncident(_:)),
                              keyEquivalent: "")
        item.tag = tag
        item.target = target
        item.representedObject = incident.shortlink
        return item
    }

    static func controlItems(state: MonitorState, target: any MenuActions) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if let date = state.lastRefreshed {
            let title = updatedNextTitle(lastRefreshed: date, interval: state.currentPollInterval)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = updatedTag
            item.isEnabled = false
            item.view = makeControlRowView(title: title)
            items.append(item)
        }

        items.append(separator(tag: separatorControlsTag))

        let refresh = NSMenuItem(title: String(localized: "menu.refresh", bundle: .module),
                                 action: #selector(MenuActions.didSelectRefresh),
                                 keyEquivalent: "r")
        refresh.tag = refreshTag
        refresh.target = target
        items.append(refresh)

        let prefs = NSMenuItem(title: String(localized: "menu.preferences", bundle: .module),
                               action: #selector(MenuActions.didSelectPreferences),
                               keyEquivalent: ",")
        prefs.tag = preferencesTag
        prefs.target = target
        items.append(prefs)

        let about = NSMenuItem(title: String(localized: "menu.about", bundle: .module),
                               action: #selector(MenuActions.didSelectAbout),
                               keyEquivalent: "")
        about.tag = aboutTag
        about.target = target
        items.append(about)

        items.append(separator(tag: separatorQuitTag))

        let quit = NSMenuItem(title: String(localized: "menu.quit", bundle: .module),
                              action: #selector(NSApplication.terminate(_:)),
                              keyEquivalent: "q")
        quit.tag = quitTag
        items.append(quit)

        return items
    }

    // MARK: - Attributed Title

    static func usageItem(label: String, window: UsageWindow, tag: Int, style: NSParagraphStyle, barWidth: CGFloat = Formatting.barImageWidth, target: (any MenuActions)? = nil) -> NSMenuItem {
        let attrTitle = usageAttributedTitle(label: label, window: window, style: style, barWidth: barWidth)
        let item = NSMenuItem()
        item.tag = tag
        if let target {
            // Use a custom view so that clicking does NOT close the menu (NSMenu behavior
            // when item.view is set). The UsageRowView handles click internally.
            let rowView = UsageRowView(attributedTitle: attrTitle)
            if window.resetsAt != nil {
                let wideAttr = usageAttributedTitle(label: label, window: window, style: style, barWidth: barWidth, timeOverride: "23h 59m")
                rowView.ensureFrameWidth(for: wideAttr)
            }
            let index = tag - usageBaseTag
            rowView.onClick = { [weak target] in
                // Synthesize a sender NSMenuItem so didSelectUsageWindow can read the tag
                let sender = NSMenuItem()
                sender.tag = tag
                sender.representedObject = index
                target?.didSelectUsageWindow(sender)
            }
            item.view = rowView
            // Target/action register the item as a keyboard-navigation focus stop; activation goes through onClick (NSMenu does not invoke item.action for view-based items).
            item.target = target
            item.action = #selector(MenuActions.didSelectUsageWindow(_:))
        } else {
            item.attributedTitle = attrTitle
            item.isEnabled = false
        }
        return item
    }

    static func usageLabels(usage: UsageResponse) -> [(tag: Int, label: String, window: UsageWindow?)] {
        usage.entries.enumerated().map { index, entry in
            (usageBaseTag + index, Formatting.displayLabel(for: entry, in: usage), entry.window)
        }
    }

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

    // Appends the current countdown time to a cached prefix attributed string.
    // Called by refreshTimes; lives here so boldMenuFont (private to this file) is in scope.
    static func appendTime(to prefix: NSAttributedString, resetsAt: Date, style: NSParagraphStyle) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: prefix)
        text.append(NSAttributedString(
            string: Formatting.timeUntil(resetsAt),
            attributes: [.font: boldMenuFont, .paragraphStyle: style]
        ))
        return text
    }

    // Builds prefix attributed strings (everything before the countdown time) for items that have
    // a resetsAt date. Stored in UsageCache so refreshTimes only appends the updated time.
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

    // Bar attachment + right-tab + percentage. The right tab stop right-aligns "<pct>%" to the end
    // of the bar+percent column. Shared by buildPrefixes and usageAttributedTitle.
    private static func barAndPercentSegment(window: UsageWindow, style: NSParagraphStyle, barWidth: CGFloat = Formatting.barImageWidth) -> NSAttributedString {
        let menuAttrs: [NSAttributedString.Key: Any] = [.font: menuFont, .paragraphStyle: style]
        let attachment = NSTextAttachment()
        attachment.image = Formatting.progressBarImage(percent: window.utilization, width: barWidth)
        attachment.bounds = NSRect(x: 0, y: barAttachmentY, width: barWidth, height: Formatting.barImageHeight)
        let result = NSMutableAttributedString(attachment: attachment)
        result.append(NSAttributedString(string: "\t\(window.utilization)%", attributes: menuAttrs))
        return result
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

    static func makeControlRowView(title: String) -> ControlRowView {
        ControlRowView(title: title)
    }
}

final class ControlRowView: NSView {
    private let label: NSTextField

    init(title: String) {
        let font = NSFont.menuFont(ofSize: 0)
        label = NSTextField(labelWithString: title)
        label.font = font
        label.textColor = .secondaryLabelColor
        let edgePadding: CGFloat = 14
        let textWidth = NSAttributedString(string: title, attributes: [.font: font]).size().width
        let minWidth = edgePadding + textWidth + edgePadding
        let height: CGFloat = 22
        super.init(frame: NSRect(x: 0, y: 0, width: minWidth, height: height))
        autoresizingMask = .width
        label.frame = NSRect(x: edgePadding, y: (height - label.intrinsicContentSize.height) / 2,
                             width: frame.width - edgePadding * 2, height: label.intrinsicContentSize.height)
        label.autoresizingMask = .width
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateTitle(_ title: String) {
        label.stringValue = title
        needsDisplay = true
    }
}
