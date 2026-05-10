import AppKit

extension MenuBuilder {
    static func controlItems(state: MonitorState, target: any MenuActions) -> [NSMenuItem] {
        var items: [NSMenuItem] = []

        if let date = state.lastRefreshed {
            let title = updatedNextTitle(lastRefreshed: date, interval: state.polling.currentPollInterval)
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

    static func makeControlRowView(title: String) -> ControlRowView {
        ControlRowView(title: title)
    }
}
