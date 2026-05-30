import AppKit

/// Lightweight menu updates for when menu is open.
/// Updates only values of existing items without changing structure.
extension MenuBuilder {
    
    /// Update existing menu items without structural changes.
    /// - Parameters:
    ///   - menu: The menu to update
    ///   - state: Current monitor state
    ///
    /// Use this when the menu is open to avoid visual glitches from rebuilding.
    /// This updates only the values/content of existing items.
    static func updateExistingItems(menu: NSMenu, state: MonitorState) {
        updateUsageRows(in: menu, state: state)
        updateServiceRows(in: menu, state: state)
        updateControlRows(in: menu, state: state)
        updateConnectivityBanner(in: menu, state: state)
        refreshGraph(in: menu, analyses: state.usage.windowAnalyses)
    }
}

// MARK: - Private Update Helpers

private extension MenuBuilder {
    
    static func updateUsageRows(in menu: NSMenu, state: MonitorState) {
        guard let usage = state.usage.currentUsage else { return }
        
        let labels = usageLabels(usage: usage)
        let barWidth = usage.hasAnyModelSpecific 
            ? Formatting.barImageWidth 
            : Formatting.barImageWidthWide
        let style = usageParagraphStyle(
            labelColumnWidth: maxLabelWidth(labels: labels.map(\.label)),
            barWidth: barWidth
        )
        
        for (tag, label, window) in labels {
            guard let window else { continue }
            updateUsageItem(
                in: menu,
                tag: tag,
                label: label,
                window: window,
                style: style,
                barWidth: barWidth
            )
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
        guard let components = state.service.currentStatus?.components else { return }
        
        let sorted = components.sorted(by: { $0.name < $1.name })
        for (index, component) in sorted.enumerated() {
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
                bannerItem.view = makeHeaderView(title: bannerText, subtitle: "Claude Monitor")
            }
        }
    }
}
