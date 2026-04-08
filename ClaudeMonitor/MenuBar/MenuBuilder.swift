import AppKit

@objc protocol MenuActions {
    func didSelectRefresh()
    func openIncident(_ sender: NSMenuItem)
    func didSelectPreferences()
    func didSelectAbout()
}

enum MenuBuilder {
    // Usage items
    private static let usageSectionTag = 10
    private static let usageBaseTag = 100
    private static let usagePlaceholderTag = 199

    // Services items
    private static let servicesSectionTag = 20
    private static let serviceBaseTag = 300
    private static let servicesPlaceholderTag = 310

    // Incidents items
    private static let incidentsSectionTag = 30
    private static let incidentBaseTag = 400

    // Controls items
    private static let updatedTag = 200
    private static let refreshTag = 601
    private static let preferencesTag = 602
    private static let aboutTag = 603
    private static let quitTag = 604

    // Separators
    private static let separatorAfterUsageTag = 501
    private static let separatorAfterServicesTag = 502
    private static let separatorIncidentsTag = 503
    private static let separatorControlsTag = 504
    private static let separatorQuitTag = 505

    // MARK: - Public API

    static func build(state: MonitorState, target: any MenuActions) -> NSMenu {
        let menu = NSMenu()
        populate(menu: menu, state: state, target: target)
        return menu
    }

    static func populate(menu: NSMenu, state: MonitorState, target: any MenuActions) {
        let desired = buildDesiredItems(state: state, target: target)
        if menu.numberOfItems == 0 {
            for item in desired { menu.addItem(item) }
        } else {
            reconcile(menu: menu, desired: desired)
        }
    }

    // MARK: - Live Refresh (countdown loop)

    static func refreshTimes(in menu: NSMenu, usage: UsageResponse) {
        let labels = usageLabels(usage: usage)
        let style = usageParagraphStyle(labelColumnWidth: maxLabelWidth(labels: labels.map(\.label)))
        for (tag, label, window) in labels {
            guard let window, let item = menu.item(withTag: tag) else { continue }
            item.attributedTitle = usageAttributedTitle(label: label, window: window, style: style)
        }
    }

    static func refreshControlTimes(in menu: NSMenu, lastRefreshed: Date?, interval: TimeInterval?) {
        if let item = menu.item(withTag: updatedTag), let date = lastRefreshed {
            item.title = updatedNextTitle(lastRefreshed: date, interval: interval)
        }
    }

    // MARK: - Desired Items

    private static func buildDesiredItems(state: MonitorState, target: any MenuActions) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        items.append(sectionHeader(String(localized: "menu.section.usage", bundle: .module), subtitle: "Claude Monitor", tag: usageSectionTag))
        items.append(contentsOf: usageItems(state: state))
        items.append(separator(tag: separatorAfterUsageTag))

        items.append(sectionHeader(String(localized: "menu.section.services", bundle: .module), tag: servicesSectionTag))
        items.append(contentsOf: serviceItems(state: state))

        if let incidents = state.currentStatus?.incidents, !incidents.isEmpty {
            items.append(separator(tag: separatorIncidentsTag))
            items.append(sectionHeader(String(localized: "menu.section.incidents", bundle: .module), tag: incidentsSectionTag))
            for (index, incident) in incidents.enumerated() {
                items.append(incidentItem(incident: incident, tag: incidentBaseTag + index, target: target))
            }
        }

        items.append(separator(tag: separatorAfterServicesTag))
        items.append(contentsOf: controlItems(state: state, target: target))

        return items
    }

    private static func usageItems(state: MonitorState) -> [NSMenuItem] {
        if !state.hasCredentials {
            return [staticItem(String(localized: "menu.credentials.configure", bundle: .module), tag: usagePlaceholderTag)]
        }
        if let error = state.usageError {
            return [staticItem("  ⚠︎  \(error)", tag: usagePlaceholderTag)]
        }
        guard let usage = state.currentUsage else {
            return [staticItem(String(localized: "menu.loading", bundle: .module), tag: usagePlaceholderTag)]
        }
        let labels = usageLabels(usage: usage)
        let style = usageParagraphStyle(labelColumnWidth: maxLabelWidth(labels: labels.map(\.label)))

        var items: [NSMenuItem] = []
        for (tag, label, window) in labels {
            guard let window else { continue }
            items.append(usageItem(label: label, window: window, tag: tag, style: style))
        }
        return items
    }

    private static func serviceItems(state: MonitorState) -> [NSMenuItem] {
        guard let components = state.currentStatus?.components else {
            if let error = state.statusError {
                return [staticItem("  ⚠︎  \(error)", tag: servicesPlaceholderTag)]
            }
            return [staticItem(String(localized: "menu.loading", bundle: .module), tag: servicesPlaceholderTag)]
        }
        return components.sorted(by: { $0.name < $1.name }).enumerated().map { index, component in
            let name = truncatedName(component.name)
            return staticItem("  \(component.status.dot)  \(name)  –  \(component.status.label)",
                              tag: serviceBaseTag + index)
        }
    }

    private static func incidentItem(incident: Incident, tag: Int, target: any MenuActions) -> NSMenuItem {
        let item = NSMenuItem(title: "  ⚠︎  \(incident.name)",
                              action: #selector(MenuActions.openIncident(_:)),
                              keyEquivalent: "")
        item.tag = tag
        item.target = target
        item.representedObject = incident.shortlink
        return item
    }

    private static func controlItems(state: MonitorState, target: any MenuActions) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if let date = state.lastRefreshed {
            items.append(staticItem(updatedNextTitle(lastRefreshed: date, interval: state.currentPollInterval),
                                    tag: updatedTag))
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

    // MARK: - Reconcile

    private static func reconcile(menu: NSMenu, desired: [NSMenuItem]) {
        let desiredTags = Set(desired.map { $0.tag })

        for item in menu.items.reversed() {
            if !desiredTags.contains(item.tag) {
                menu.removeItem(item)
            }
        }

        for (index, desiredItem) in desired.enumerated() {
            if let existing = menu.item(withTag: desiredItem.tag) {
                if !existing.isSeparatorItem && existing.view == nil {
                    updateItem(existing, from: desiredItem)
                }
                let currentIndex = menu.index(of: existing)
                if currentIndex != index {
                    menu.removeItem(existing)
                    menu.insertItem(existing, at: min(index, menu.numberOfItems))
                }
            } else {
                menu.insertItem(desiredItem, at: min(index, menu.numberOfItems))
            }
        }
    }

    private static func updateItem(_ existing: NSMenuItem, from desired: NSMenuItem) {
        if let attr = desired.attributedTitle {
            existing.attributedTitle = attr
        } else if existing.title != desired.title {
            existing.title = desired.title
        }
        if let rep = desired.representedObject as? String {
            existing.representedObject = rep
        }
    }

    // MARK: - Attributed Title

    private static func usageItem(label: String, window: UsageWindow, tag: Int, style: NSParagraphStyle) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = usageAttributedTitle(label: label, window: window, style: style)
        item.isEnabled = false
        item.tag = tag
        return item
    }

    private static func usageLabels(usage: UsageResponse) -> [(tag: Int, label: String, window: UsageWindow?)] {
        usage.entries.enumerated().map { index, entry in
            (usageBaseTag + index, Formatting.displayLabel(for: entry, in: usage), entry.window)
        }
    }

    private static let barPercentWidth: CGFloat = NSAttributedString(
        string: "\(Formatting.progressBar(percent: 50))  100%",
        attributes: [.font: NSFont.menuFont(ofSize: 0)]
    ).size().width

    private static func usageParagraphStyle(labelColumnWidth: CGFloat) -> NSParagraphStyle {
        let padding: CGFloat = 8
        let barStart = labelColumnWidth + padding
        let resetsStart = barStart + barPercentWidth + padding

        let style = NSMutableParagraphStyle()
        style.tabStops = [
            NSTextTab(textAlignment: .left, location: barStart),
            NSTextTab(textAlignment: .left, location: resetsStart),
        ]
        return style
    }

    private static func maxLabelWidth(labels: [String]) -> CGFloat {
        let font = NSFont.menuFont(ofSize: 0)
        return labels.map { label in
            NSAttributedString(string: "  \(label)  ", attributes: [.font: font]).size().width
        }.max() ?? 0
    }

    private static func usageAttributedTitle(label: String, window: UsageWindow, style: NSParagraphStyle) -> NSAttributedString {
        let menuFont = NSFont.menuFont(ofSize: 0)
        let boldFont = NSFontManager.shared.convert(menuFont, toHaveTrait: .boldFontMask)
        let bar = Formatting.progressBar(percent: window.utilization)
        let attrs: [NSAttributedString.Key: Any] = [.font: menuFont, .paragraphStyle: style]

        guard let resetsAt = window.resetsAt else {
            return NSMutableAttributedString(
                string: "  \(label)  \t\(bar)  \(window.utilization)%",
                attributes: attrs
            )
        }

        let reset = Formatting.timeUntil(resetsAt)
        let text = NSMutableAttributedString(
            string: "  \(label)  \t\(bar)  \(window.utilization)%\t \(String(localized: "menu.resets.prefix", bundle: .module))",
            attributes: attrs
        )
        text.append(NSAttributedString(string: reset, attributes: [.font: boldFont, .paragraphStyle: style]))
        return text
    }

    private static func updatedNextTitle(lastRefreshed: Date, interval: TimeInterval?) -> String {
        let updated = String(format: String(localized: "menu.updated", bundle: .module),
                             lastRefreshed.formatted(.dateTime.hour().minute().second()))
        guard let interval else { return updated }
        let intervalLabel = String(format: String(localized: "menu.interval", bundle: .module),
                                   Formatting.formatInterval(interval))
        let nextDate = lastRefreshed.addingTimeInterval(interval)
        let nextLabel = String(format: String(localized: "menu.next", bundle: .module),
                               nextDate.formatted(.dateTime.hour().minute().second()))
        return "\(updated)      \(intervalLabel)      \(nextLabel)"
    }

    // MARK: - Helpers

    private static func sectionHeader(_ title: String, subtitle: String? = nil, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag

        if let subtitle {
            let font = NSFont.menuFont(ofSize: 0)
            let height: CGFloat = 22
            let edgePadding: CGFloat = 14

            let leftLabel = NSTextField(labelWithString: title)
            leftLabel.font = font
            leftLabel.textColor = .disabledControlTextColor
            leftLabel.sizeToFit()
            leftLabel.frame.origin = NSPoint(x: edgePadding, y: (height - leftLabel.frame.height) / 2)

            let rightLabel = NSTextField(labelWithString: subtitle)
            rightLabel.font = font
            rightLabel.textColor = .tertiaryLabelColor
            rightLabel.sizeToFit()
            rightLabel.autoresizingMask = .minXMargin
            let minWidth = edgePadding + leftLabel.frame.width + 20 + rightLabel.frame.width + edgePadding
            rightLabel.frame.origin = NSPoint(
                x: minWidth - edgePadding - rightLabel.frame.width,
                y: (height - rightLabel.frame.height) / 2
            )

            let view = NSView(frame: NSRect(x: 0, y: 0, width: minWidth, height: height))
            view.autoresizingMask = .width
            view.addSubview(leftLabel)
            view.addSubview(rightLabel)
            item.view = view
        }

        return item
    }

    private static func staticItem(_ title: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag
        return item
    }

    private static func separator(tag: Int) -> NSMenuItem {
        let item = NSMenuItem.separator()
        item.tag = tag
        return item
    }

    private static let maxDisplayLength = 40
    private static let truncatedPrefixLength = 30

    private static func truncatedName(_ name: String) -> String {
        name.count > maxDisplayLength ? String(name.prefix(truncatedPrefixLength)).trimmingCharacters(in: .whitespaces) + "…" : name
    }
}
