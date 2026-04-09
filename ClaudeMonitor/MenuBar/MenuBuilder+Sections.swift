import AppKit

extension MenuBuilder {
    // MARK: - Section Builders

    static func usageItems(state: MonitorState) -> [NSMenuItem] {
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

    static func serviceItems(state: MonitorState) -> [NSMenuItem] {
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

    // MARK: - Attributed Title

    static func usageItem(label: String, window: UsageWindow, tag: Int, style: NSParagraphStyle) -> NSMenuItem {
        let item = NSMenuItem()
        item.attributedTitle = usageAttributedTitle(label: label, window: window, style: style)
        item.isEnabled = false
        item.tag = tag
        return item
    }

    static func usageLabels(usage: UsageResponse) -> [(tag: Int, label: String, window: UsageWindow?)] {
        usage.entries.enumerated().map { index, entry in
            (usageBaseTag + index, Formatting.displayLabel(for: entry, in: usage), entry.window)
        }
    }

    private static let menuFont = NSFont.menuFont(ofSize: 0)
    private static let boldMenuFont = NSFontManager.shared.convert(menuFont, toHaveTrait: .boldFontMask)

    static let barPercentWidth: CGFloat = NSAttributedString(
        string: "\(Formatting.progressBar(percent: 50))  100%",
        attributes: [.font: menuFont]
    ).size().width

    static func usageParagraphStyle(labelColumnWidth: CGFloat) -> NSParagraphStyle {
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

    static func maxLabelWidth(labels: [String]) -> CGFloat {
        labels.map { label in
            NSAttributedString(string: "  \(label)  ", attributes: [.font: menuFont]).size().width
        }.max() ?? 0
    }

    static func usageAttributedTitle(label: String, window: UsageWindow, style: NSParagraphStyle) -> NSAttributedString {
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
        text.append(NSAttributedString(string: reset, attributes: [.font: boldMenuFont, .paragraphStyle: style]))
        return text
    }

    static func updatedNextTitle(lastRefreshed: Date, interval: TimeInterval?) -> String {
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
}
