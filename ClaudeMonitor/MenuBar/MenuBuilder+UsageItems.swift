import AppKit

extension MenuBuilder {
    static func usageGraphPlaceholder() -> NSMenuItem {
        let item = NSMenuItem()
        item.tag = usageGraphTag
        item.isEnabled = false
        item.view = UsageGraphView()
        return item
    }

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
        guard let usage = state.usage.currentUsage else {
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

    static func usageItem(label: String, window: UsageWindow, tag: Int, style: NSParagraphStyle, barWidth: CGFloat = Formatting.barImageWidth, target: (any MenuActions)? = nil) -> NSMenuItem {
        let attrTitle = usageAttributedTitle(label: label, window: window, style: style, barWidth: barWidth)
        let item = NSMenuItem()
        item.tag = tag
        if let target {
            let rowView = UsageRowView(attributedTitle: attrTitle)
            if window.resetsAt != nil {
                let wideAttr = usageAttributedTitle(label: label, window: window, style: style, barWidth: barWidth, timeOverride: "23h 59m")
                rowView.ensureFrameWidth(for: wideAttr)
            }
            let index = tag - usageBaseTag
            rowView.onClick = { [weak target] in
                let sender = NSMenuItem()
                sender.tag = tag
                sender.representedObject = index
                target?.didSelectUsageWindow(sender)
            }
            item.view = rowView
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
}
