import AppKit

extension MenuBuilder {
    @discardableResult
    static func populate(menu: NSMenu, state: MonitorState, target: any MenuActions) -> UsageCache {
        let (desired, cache) = buildDesiredItems(state: state, target: target)
        if menu.numberOfItems == 0 {
            for item in desired { menu.addItem(item) }
        } else {
            reconcile(menu: menu, desired: desired)
            if let usageHeaderItem = menu.item(withTag: usageSectionTag) {
                updateUsageHeader(usageHeaderItem, state: state, target: target)
            }
            if let servicesHeaderItem = menu.item(withTag: servicesSectionTag) {
                let servicesTitle = String(localized: "menu.section.services", bundle: .module)
                if let subtitle = servicesSubtitle(state: state) {
                    servicesHeaderItem.view = makeHeaderView(title: servicesTitle, subtitle: subtitle)
                } else if servicesHeaderItem.view != nil {
                    servicesHeaderItem.view = nil
                }
            }
            if state.polling.isAnyServiceStale,
               let bannerItem = menu.item(withTag: connectivityBannerTag) {
                let bannerText = bannerItem.title
                bannerItem.view = makeHeaderView(title: bannerText, subtitle: Constants.Menu.appTitle)
            }
        }
        refreshGraph(in: menu, analyses: state.usage.windowAnalyses, energy: state.energy)
        return cache
    }

    static func buildDesiredItems(state: MonitorState, target: any MenuActions) -> ([NSMenuItem], UsageCache) {
        var items: [NSMenuItem] = []

        if state.polling.isAnyServiceStale {
            let bannerText = state.polling.isOnline
                ? String(localized: "connectivity.connectionError", bundle: .module)
                : String(localized: "connectivity.offline", bundle: .module)
            let bannerItem = NSMenuItem(title: bannerText, action: nil, keyEquivalent: "")
            bannerItem.isEnabled = false
            bannerItem.tag = connectivityBannerTag
            bannerItem.view = makeHeaderView(title: bannerText, subtitle: Constants.Menu.appTitle)
            items.append(bannerItem)
            items.append(separator(tag: separatorAfterConnectivityTag))
        }

        items.append(sectionHeader(
            String(localized: "menu.section.usage", bundle: .module),
            subtitle: usageSubtitle(state: state),
            tag: usageSectionTag,
            switcher: accountSwitcher(state: state, target: target)
        ))
        let (usageMenuItems, cache) = usageItems(state: state, target: target)
        items.append(contentsOf: usageMenuItems)


        if state.showGraph {
            items.append(usageGraphPlaceholder())
        }
        items.append(separator(tag: separatorAfterUsageTag))

        items.append(sectionHeader(String(localized: "menu.section.services", bundle: .module), subtitle: servicesSubtitle(state: state), tag: servicesSectionTag))
        items.append(contentsOf: serviceItems(state: state))

        if let incidents = state.service.currentStatus?.incidents, !incidents.isEmpty {
            items.append(separator(tag: separatorIncidentsTag))
            items.append(sectionHeader(String(localized: "menu.section.incidents", bundle: .module), tag: incidentsSectionTag))
            for (index, incident) in incidents.enumerated() {
                items.append(incidentItem(incident: incident, tag: incidentBaseTag + index, target: target))
            }
        }

        items.append(separator(tag: separatorAfterServicesTag))
        items.append(contentsOf: controlItems(state: state))
        items.append(separator(tag: separatorControlsTag))
        items.append(footerActionsItem(target: target))
        items.append(contentsOf: shortcutItems(target: target))

        return (items, cache)
    }

    static func refreshGraph(in menu: NSMenu, analyses: [WindowAnalysis], energy: EnergyEstimate? = nil) {
        guard let item = menu.item(withTag: usageGraphTag),
              let graphView = item.view as? UsageGraphView else { return }
        graphView.update(analyses: analyses)
        graphView.update(energy: energy)
        syncUsageCheckmarks(in: menu, selectedIndex: graphView.currentSelectedIndex)
    }

    static func refreshTimes(in menu: NSMenu, cache: UsageCache) {
        for (tag, _, window) in cache.labels {
            guard let resetsAt = window?.resetsAt,
                  let prefix = cache.prefixes[tag],
                  let item = menu.item(withTag: tag) else { continue }
            let text = appendTime(to: prefix, resetsAt: resetsAt, style: cache.style)
            if let rowView = item.view as? UsageRowView {
                rowView.updateTitle(text)
            } else {
                item.attributedTitle = text
            }
        }
    }

    static func displayedComponents(state: MonitorState) -> [StatusComponent] {
        let components = state.service.currentStatus?.components ?? []
        let shown = state.compactServices ? components.filter { $0.status != .operational } : components
        return shown.sorted(by: { $0.name < $1.name })
    }

    static func servicesSubtitle(state: MonitorState) -> String? {
        let components = state.service.currentStatus?.components ?? []
        guard state.compactServices,
              !components.isEmpty,
              components.allSatisfy({ $0.status == .operational }) else { return nil }
        return String(localized: "services.all_operational", bundle: .module)
    }

    static func serviceItems(state: MonitorState) -> [NSMenuItem] {
        guard state.service.currentStatus?.components != nil else {
            return [staticItem("  " + String(localized: "menu.loading", bundle: .module), tag: servicesPlaceholderTag)]
        }
        return displayedComponents(state: state).enumerated().map { index, component in
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

    private static func usageSubtitle(state: MonitorState) -> String? {
        state.polling.isAnyServiceStale ? nil : Constants.Menu.appTitle
    }

    private static func updateUsageHeader(_ item: NSMenuItem, state: MonitorState, target: any MenuActions) {
        let subtitle = usageSubtitle(state: state)
        let switcher = accountSwitcher(state: state, target: target)
        if let switcher,
           let toggle = findAccountToggle(in: item.view),
           toggle.currentSegments == switcher.segments,
           headerSubtitle(in: item.view) == subtitle {
            toggle.configure(with: switcher)
        } else {
            let title = String(localized: "menu.section.usage", bundle: .module)
            item.view = headerView(title: title, subtitle: subtitle, switcher: switcher)
        }
    }
}
