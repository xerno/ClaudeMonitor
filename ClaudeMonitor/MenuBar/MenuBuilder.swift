import AppKit

@MainActor @objc protocol MenuActions {
    func didSelectRefresh()
    func openIncident(_ sender: NSMenuItem)
    func didSelectPreferences()
    func didSelectAbout()
    func didSelectUsageWindow(_ sender: NSMenuItem)
}

@MainActor
enum MenuBuilder {
    // Usage items
    static let usageSectionTag = 10
    static let usageBaseTag = 100
    static let usagePlaceholderTag = 199

    // Services items
    static let servicesSectionTag = 20
    static let serviceBaseTag = 300
    static let servicesPlaceholderTag = 310

    // Incidents items
    static let incidentsSectionTag = 30
    static let incidentBaseTag = 400

    // Controls items
    static let updatedTag = 200
    static let refreshTag = 601
    static let preferencesTag = 602
    static let aboutTag = 603
    static let quitTag = 604

    // Graph view
    static let usageGraphTag = 700

    // Separators
    static let separatorAfterUsageTag = 501
    static let separatorAfterServicesTag = 502
    static let separatorIncidentsTag = 503
    static let separatorControlsTag = 504
    static let separatorQuitTag = 505

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
        refreshGraph(in: menu, analyses: state.windowAnalyses)
    }

    // MARK: - Layout cache (recomputed per data update, read by countdown loop)

    static var cachedLabels: [(tag: Int, label: String, window: UsageWindow?)] = []
    static var cachedStyle: NSParagraphStyle = NSParagraphStyle()

    // MARK: - Live Refresh (countdown loop)

    static func refreshTimes(in menu: NSMenu, usage _: UsageResponse) {
        let labels = cachedLabels
        let style = cachedStyle
        for (tag, label, window) in labels {
            guard let window, let item = menu.item(withTag: tag) else { continue }
            let attrTitle = usageAttributedTitle(label: label, window: window, style: style)
            if let rowView = item.view as? UsageRowView {
                rowView.updateTitle(attrTitle)
            } else {
                item.attributedTitle = attrTitle
            }
        }
    }

    static func refreshGraph(in menu: NSMenu, analyses: [WindowAnalysis]) {
        guard let item = menu.item(withTag: usageGraphTag),
              let graphView = item.view as? UsageGraphView else { return }
        graphView.update(analyses: analyses)
        syncUsageCheckmarks(in: menu, selectedIndex: graphView.currentSelectedIndex)
    }

    static func syncUsageCheckmarks(in menu: NSMenu, selectedIndex: Int) {
        for item in menu.items {
            let tag = item.tag
            guard tag >= usageBaseTag && tag < usagePlaceholderTag else { continue }
            let index = tag - usageBaseTag
            if let rowView = item.view as? UsageRowView {
                rowView.isSelected = index == selectedIndex
            } else {
                item.state = index == selectedIndex ? .on : .off
            }
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
        items.append(contentsOf: usageItems(state: state, target: target))
        items.append(usageGraphPlaceholder())
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
                if !existing.isSeparatorItem {
                    if existing.view == nil {
                        updateItem(existing, from: desiredItem)
                    } else if let existingRow = existing.view as? UsageRowView,
                              let desiredRow = desiredItem.view as? UsageRowView {
                        existingRow.updateTitle(desiredRow.currentAttributedTitle)
                    }
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

    // MARK: - Helpers

    static func sectionHeader(_ title: String, subtitle: String? = nil, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag
        if let subtitle {
            item.view = makeHeaderView(title: title, subtitle: subtitle)
        }
        return item
    }

    static func makeHeaderView(title: String, subtitle: String) -> NSView {
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
        return view
    }

    static func staticItem(_ title: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag
        return item
    }

    static func separator(tag: Int) -> NSMenuItem {
        let item = NSMenuItem.separator()
        item.tag = tag
        return item
    }

    static let maxDisplayLength = 40
    static let truncatedPrefixLength = 30

    static func truncatedName(_ name: String) -> String {
        name.count > maxDisplayLength ? String(name.prefix(truncatedPrefixLength)).trimmingCharacters(in: .whitespaces) + "…" : name
    }
}
