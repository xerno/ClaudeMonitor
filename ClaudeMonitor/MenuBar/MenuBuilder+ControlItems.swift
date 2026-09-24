import AppKit

extension MenuBuilder {
    static func controlItems(state: MonitorState) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if let date = state.lastRefreshed {
            let title = updatedNextTitle(lastRefreshed: date, interval: state.polling.currentPollInterval)
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = updatedTag
            item.isEnabled = false
            item.view = ControlRowView(title: title)
            items.append(item)
        }

        if let item = historyHealthItem(state: state) {
            items.append(item)
        }

        return items
    }

    static func footerActionsItem(target: any MenuActions) -> NSMenuItem {
        let buttons = [
            FooterIconButton(
                symbol: Constants.Menu.Symbol.refresh,
                help: String(localized: "menu.refresh", bundle: .module),
                closesMenu: false
            ) { [weak target] in target?.didSelectRefresh() },
            FooterIconButton(
                symbol: Constants.Menu.Symbol.preferences,
                help: String(localized: "menu.preferences", bundle: .module),
                closesMenu: true
            ) { [weak target] in target?.didSelectPreferences() },
            FooterIconButton(
                symbol: Constants.Menu.Symbol.about,
                help: String(localized: "menu.about", bundle: .module),
                closesMenu: true
            ) { [weak target] in target?.didSelectAbout() },
            FooterIconButton(
                symbol: Constants.Menu.Symbol.quit,
                help: String(localized: "menu.quit", bundle: .module),
                closesMenu: true
            ) { _ = NSApplication.shared.sendAction(#selector(NSApplication.terminate(_:)), to: nil, from: nil) },
        ]

        let stack = NSStackView(views: buttons)
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.translatesAutoresizingMaskIntoConstraints = false

        let edgePadding = Constants.Menu.edgePadding
        let width = CGFloat(buttons.count) * Constants.Menu.footerButtonSize.width + 2 * edgePadding
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: Constants.Menu.footerHeight))
        container.autoresizingMask = .width
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: edgePadding),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -edgePadding),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        let item = NSMenuItem()
        item.tag = footerActionsTag
        item.view = container
        return item
    }

    static func footerButtons(in menu: NSMenu) -> [FooterIconButton] {
        let stack = menu.item(withTag: footerActionsTag)?.view?.subviews.first { $0 is NSStackView } as? NSStackView
        return stack?.arrangedSubviews.compactMap { $0 as? FooterIconButton } ?? []
    }

    static func resetFooterHover(in menu: NSMenu) {
        footerButtons(in: menu).forEach { $0.resetHover() }
    }

    static func shortcutItems(target: any MenuActions) -> [NSMenuItem] {
        [
            shortcutItem(
                title: String(localized: "menu.refresh", bundle: .module),
                action: #selector(MenuActions.didSelectRefresh),
                keyEquivalent: Constants.Menu.KeyEquivalent.refresh,
                tag: refreshTag,
                target: target
            ),
            shortcutItem(
                title: String(localized: "menu.preferences", bundle: .module),
                action: #selector(MenuActions.didSelectPreferences),
                keyEquivalent: Constants.Menu.KeyEquivalent.preferences,
                tag: preferencesTag,
                target: target
            ),
            shortcutItem(
                title: String(localized: "menu.quit", bundle: .module),
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: Constants.Menu.KeyEquivalent.quit,
                tag: quitTag,
                target: nil
            ),
        ]
    }

    private static func shortcutItem(title: String, action: Selector, keyEquivalent: String, tag: Int, target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.tag = tag
        item.target = target
        item.isHidden = true
        item.allowsKeyEquivalentWhenHidden = true
        return item
    }

    /// Status line reporting `UsageHistory`'s persistence-failure/quarantine state — `nil` when
    /// there is nothing to report (saving is succeeding and no files are quarantined), so it
    /// never appears as an empty row. Deliberately a plain disabled row, never an alert or sheet:
    /// this is ambient status, not something that should interrupt the user.
    static func historyHealthItem(state: MonitorState) -> NSMenuItem? {
        var lines: [String] = []
        if !state.history.lastSaveSucceeded, let since = state.history.persistenceFailingSince {
            let timeStr = Formatting.absoluteTime(since, .hourMinute)
            lines.append(String(format: String(localized: "menu.history.saveFailing", bundle: .module), timeStr))
        }
        if state.history.quarantinedFileCount > 0 {
            let template = String(localized: "menu.history.quarantinedCount", bundle: .module)
            lines.append(String(format: template, locale: .current, state.history.quarantinedFileCount))
        }
        guard !lines.isEmpty else { return nil }
        return staticItem("  ⚠︎  " + lines.joined(separator: "  ·  "), tag: historyHealthTag)
    }

}
