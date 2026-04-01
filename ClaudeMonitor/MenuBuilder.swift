import AppKit

@objc protocol MenuActions {
    func didSelectRefresh()
    func openIncident(_ sender: NSMenuItem)
    func didSelectPreferences()
    func didSelectAbout()
}

enum MenuBuilder {
    static func build(state: MonitorState, target: any MenuActions) -> NSMenu {
        let menu = NSMenu()
        addUsageSection(to: menu, state: state)
        menu.addItem(.separator())
        addServicesSection(to: menu, state: state)
        if let incidents = state.currentStatus?.incidents, !incidents.isEmpty {
            menu.addItem(.separator())
            addIncidentsSection(to: menu, incidents: incidents, target: target)
        }
        menu.addItem(.separator())
        addControlsSection(to: menu, state: state, target: target)
        return menu
    }

    // MARK: - Usage

    private static func addUsageSection(to menu: NSMenu, state: MonitorState) {
        menu.addItem(sectionHeader("Usage"))

        if !state.hasCredentials {
            menu.addItem(staticItem("  ⚙  Configure credentials in Preferences"))
            return
        }
        if let error = state.usageError {
            menu.addItem(staticItem("  ⚠︎  \(error)"))
            return
        }
        guard let usage = state.currentUsage else {
            menu.addItem(staticItem("  Loading..."))
            return
        }
        if let w = usage.fiveHour {
            menu.addItem(usageItem(label: "5h window", window: w))
        }
        if let w = usage.sevenDay {
            menu.addItem(usageItem(label: "7d window", window: w))
        }
        if let w = usage.sevenDaySonnet {
            menu.addItem(usageItem(label: "7d Sonnet", window: w))
        }
    }

    private static func usageItem(label: String, window: UsageWindow) -> NSMenuItem {
        let bar = Formatting.progressBar(percent: window.utilization)
        let reset = Formatting.timeUntil(window.resetsAt)
        let menuFont = NSFont.menuFont(ofSize: 0)
        let boldFont = NSFontManager.shared.convert(menuFont, toHaveTrait: .boldFontMask)

        let resetTime = String(reset.dropFirst(3))
        let text = NSMutableAttributedString(string: "  \(label):  \(bar)  \(window.utilization)%   (resets in ", attributes: [.font: menuFont])
        text.append(NSAttributedString(string: resetTime, attributes: [.font: boldFont]))
        text.append(NSAttributedString(string: ")", attributes: [.font: menuFont]))

        let item = NSMenuItem()
        item.attributedTitle = text
        item.isEnabled = false
        return item
    }

    // MARK: - Services

    private static func addServicesSection(to menu: NSMenu, state: MonitorState) {
        menu.addItem(sectionHeader("Services"))
        guard let components = state.currentStatus?.components else {
            if let error = state.statusError {
                menu.addItem(staticItem("  ⚠︎  \(error)"))
            } else {
                menu.addItem(staticItem("  Loading..."))
            }
            return
        }
        for component in components.sorted(by: { $0.name < $1.name }) {
            menu.addItem(staticItem("  \(component.status.dot)  \(component.name)  –  \(component.status.label)"))
        }
    }

    // MARK: - Incidents

    private static func addIncidentsSection(to menu: NSMenu, incidents: [Incident], target: any MenuActions) {
        menu.addItem(sectionHeader("Active Incidents"))
        for incident in incidents {
            let item = NSMenuItem(
                title: "  ⚠︎  \(incident.name)",
                action: #selector(MenuActions.openIncident(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = incident.shortlink
            menu.addItem(item)
        }
    }

    // MARK: - Controls

    private static func addControlsSection(to menu: NSMenu, state: MonitorState, target: any MenuActions) {
        if let date = state.lastRefreshed {
            menu.addItem(staticItem("Updated: \(date.formatted(.dateTime.hour().minute().second()))"))
        }

        let refresh = NSMenuItem(
            title: "Refresh Now",
            action: #selector(MenuActions.didSelectRefresh),
            keyEquivalent: "r"
        )
        refresh.target = target
        menu.addItem(refresh)

        let prefs = NSMenuItem(
            title: "Preferences…",
            action: #selector(MenuActions.didSelectPreferences),
            keyEquivalent: ","
        )
        prefs.target = target
        menu.addItem(prefs)

        let about = NSMenuItem(
            title: "About Claude Monitor",
            action: #selector(MenuActions.didSelectAbout),
            keyEquivalent: ""
        )
        about.target = target
        menu.addItem(about)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    // MARK: - Helpers

    private static func sectionHeader(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func staticItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
