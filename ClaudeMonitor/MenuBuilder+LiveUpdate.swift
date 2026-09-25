import AppKit

/// Lightweight menu updates for when menu is open.
/// Updates only values of existing items without changing structure outside the usage rows.
extension MenuBuilder {
    
    /// Update existing menu items without structural changes outside the usage rows.
    /// - Parameters:
    ///   - menu: The menu to update
    ///   - state: Current monitor state
    ///
    /// Use this when the menu is open to avoid visual glitches from rebuilding.
    /// This updates only the values/content of existing items.
    @discardableResult
    static func updateExistingItems(menu: NSMenu, state: MonitorState, target: (any MenuActions)? = nil) -> UsageCache {
        let cache = updateUsageRows(in: menu, state: state, target: target)
        updateServiceRows(in: menu, state: state)
        updateControlRows(in: menu, state: state)
        updateConnectivityBanner(in: menu, state: state)
        refreshGraph(in: menu, analyses: state.usage.windowAnalyses, energy: state.energy)
        return cache
    }
}

// MARK: - Private Update Helpers

private extension MenuBuilder {

    static func updateUsageRows(in menu: NSMenu, state: MonitorState, target: (any MenuActions)?) -> UsageCache {
        let hasPlaceholder = menu.item(withTag: usagePlaceholderTag) != nil
        guard state.hasCredentials, let usage = state.usage.currentUsage else {
            if !hasPlaceholder {
                replaceUsageRows(in: menu, state: state, target: target)
            }
            return UsageCache()
        }
        if hasPlaceholder {
            return replaceUsageRows(in: menu, state: state, target: target)
        }

        let cache = usageCache(for: usage)
        let barWidth = usageBarWidth(for: usage)
        removeVanishedUsageRows(in: menu, cache: cache)

        for (tag, label, window) in cache.labels {
            guard let window else { continue }
            updateUsageItem(
                in: menu,
                tag: tag,
                label: label,
                window: window,
                style: cache.style,
                barWidth: barWidth
            )
        }
        return cache
    }

    @discardableResult
    static func replaceUsageRows(in menu: NSMenu, state: MonitorState, target: (any MenuActions)?) -> UsageCache {
        let isUsageRow: (NSMenuItem) -> Bool = { $0.tag >= usageBaseTag && $0.tag <= usagePlaceholderTag }
        guard let insertionIndex = menu.items.firstIndex(where: isUsageRow) else { return UsageCache() }
        for item in menu.items where isUsageRow(item) {
            menu.removeItem(item)
        }
        let (items, cache) = usageItems(state: state, target: target)
        for (offset, item) in items.filter(isUsageRow).enumerated() {
            menu.insertItem(item, at: insertionIndex + offset)
        }
        return cache
    }

    static func removeVanishedUsageRows(in menu: NSMenu, cache: UsageCache) {
        let windowTags = Set(cache.labels.filter { $0.window != nil }.map(\.tag))
        for item in menu.items where item.tag >= usageBaseTag && item.tag < usagePlaceholderTag && !windowTags.contains(item.tag) {
            menu.removeItem(item)
        }
    }

    static func updateUsageItem(
        in menu: NSMenu,
        tag: Int,
        label: String,
        window: UsageWindow,
        style: NSParagraphStyle,
        barWidth: CGFloat
    ) {
        guard let item = menu.item(withTag: tag) else { return }
        
        let attrTitle = usageAttributedTitle(
            label: label,
            window: window,
            style: style,
            barWidth: barWidth
        )
        
        if let rowView = item.view as? UsageRowView {
            rowView.updateTitle(attrTitle)
        } else {
            item.attributedTitle = attrTitle
        }
    }
    
    static func updateServiceRows(in menu: NSMenu, state: MonitorState) {
        for (index, component) in displayedComponents(state: state).enumerated() {
            updateServiceItem(in: menu, index: index, component: component)
        }
    }
    
    static func updateServiceItem(
        in menu: NSMenu,
        index: Int,
        component: StatusComponent
    ) {
        let tag = serviceBaseTag + index
        guard let item = menu.item(withTag: tag) else { return }
        
        let name = truncatedName(component.name)
        let newTitle = "  \(component.status.dot)  \(name)  –  \(component.status.label)"
        
        if item.title != newTitle {
            item.title = newTitle
        }
    }
    
    static func updateControlRows(in menu: NSMenu, state: MonitorState) {
        guard let date = state.lastRefreshed else { return }
        updateRefreshTimestamp(in: menu, date: date, interval: state.polling.currentPollInterval)
    }
    
    static func updateRefreshTimestamp(
        in menu: NSMenu,
        date: Date,
        interval: TimeInterval?
    ) {
        guard let item = menu.item(withTag: updatedTag) else { return }
        
        let title = updatedNextTitle(lastRefreshed: date, interval: interval)
        
        if let controlView = item.view as? ControlRowView {
            controlView.updateTitle(title)
        } else {
            item.title = title
        }
    }
    
    static func updateConnectivityBanner(in menu: NSMenu, state: MonitorState) {
        guard let bannerItem = menu.item(withTag: connectivityBannerTag) else { return }
        
        let bannerText = state.polling.isOnline
            ? String(localized: "connectivity.connectionError", bundle: .module)
            : String(localized: "connectivity.offline", bundle: .module)
        
        if bannerItem.title != bannerText {
            bannerItem.title = bannerText
            if state.polling.isAnyServiceStale {
                bannerItem.view = makeHeaderView(title: bannerText, subtitle: Constants.Menu.appTitle)
            }
        }
    }
}
