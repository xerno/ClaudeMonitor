import AppKit

@MainActor
final class MenuBarController: NSObject, MenuActions {
    let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let coordinator = DataCoordinator()
    private var preferencesController: PreferencesWindowController?
    private var setupController: SetupWindowController?
    private var aboutController: AboutWindowController?
    var countdownTask: Task<Void, Never>?
    var animationTask: Task<Void, Never>?
    var isMenuOpen = false
    var usageCache = UsageCache()

    override init() {
        super.init()
        coordinator.onUpdate = { [weak self] in self?.applyUIUpdates() }
        coordinator.onCriticalReset = { [weak self] in self?.handleCriticalReset() }
        configureStatusItem()
        coordinator.startPolling()
        coordinator.energyMonitor.start()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(systemDidWake),
            name: NSWorkspace.didWakeNotification, object: nil
        )
        if !coordinator.hasCredentials {
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(300))
                self?.showSetup()
            }
        }
    }

    // MARK: - Setup

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageTrailing
        button.image = StatusBarRenderer.makeImage(symbolName: "circle.fill", color: .systemGray)
        let state = coordinator.monitorState
        StatusBarRenderer.updateText(
            button: button, usage: state.usage.currentUsage,
            hasCredentials: state.hasCredentials,
            isStale: state.polling.isAnyServiceStale || state.polling.isUsageDataExpired
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        usageCache = MenuBuilder.populate(menu: menu, state: coordinator.monitorState, target: self)
    }

    // MARK: - UI Updates

    private func applyUIUpdates() {
        animationTask?.cancel()
        let state = coordinator.monitorState
        if let button = statusItem.button {
            StatusBarRenderer.updateIcon(
                button: button, status: state.service.currentStatus,
                hasRefreshWarning: state.polling.isAnyServiceStale
            )
            if !isMenuOpen {
                StatusBarRenderer.updateText(
                    button: button, usage: state.usage.currentUsage,
                    hasCredentials: state.hasCredentials,
                    isStale: state.polling.isAnyServiceStale || state.polling.isUsageDataExpired,
                    windowAnalyses: state.usage.windowAnalyses
                )
            }
        }
        if let menu = statusItem.menu {
            if isMenuOpen {
                // Lightweight update — only values, no structural changes outside the usage rows
                usageCache = MenuBuilder.updateExistingItems(menu: menu, state: state, target: self)
            } else {
                // Full rebuild — can add/remove items, reorder, etc.
                usageCache = MenuBuilder.populate(menu: menu, state: state, target: self)
            }
        }
        updateCountdownState()
    }

    // MARK: - MenuActions

    @objc func didSelectRefresh() {
        coordinator.restartPolling()
    }

    @objc private func systemDidWake() {
        stopCountdown()
        coordinator.restartPolling()
    }

    @objc func openIncident(_ sender: NSMenuItem) {
        guard let urlString = sender.representedObject as? String,
              let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func didSelectSentinel() {}

    @objc func didSelectProfile(id: String) {
        coordinator.switchToProfile(id: id)
        applyUIUpdates()
    }

    @objc func didSelectUsageWindow(_ sender: NSMenuItem) {
        guard let menu = statusItem.menu else { return }
        let index = sender.tag - MenuBuilder.usageBaseTag
        guard let graphView = menu.item(withTag: MenuBuilder.usageGraphTag)?.view as? UsageGraphView else { return }
        graphView.selectWindow(at: index)
        MenuBuilder.syncUsageCheckmarks(in: menu, selectedIndex: graphView.currentSelectedIndex)
    }

    private func openWindow<T: NSWindowController>(_ controller: inout T?, make: () -> T) {
        if controller == nil { controller = make() }
        controller?.showWindow(nil)
    }

    @objc func didSelectAbout() {
        openWindow(&aboutController) { [coordinator] in AboutWindowController(energy: coordinator.energyMonitor.estimate) }
    }

    @objc func didSelectPreferences() {
        openWindow(&preferencesController) {
            PreferencesWindowController(
                usageHistories: { [weak self] in self?.coordinator.usageHistories ?? [] },
                profileStore: coordinator.profileStore,
                onDisplaySettingsChanged: { [weak self] in self?.applyUIUpdates() },
                onSave: { [weak self] in self?.coordinator.restartPolling() }
            )
        }
    }

    private func showSetup() {
        openWindow(&setupController) {
            SetupWindowController(profileStore: coordinator.profileStore) { [weak self] in self?.coordinator.restartPolling() }
        }
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        updateCountdownState()
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        MenuBuilder.syncHighlight(in: menu, highlighted: item)
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        applyUIUpdates()
        // Not merely defensive: closing the menu after clicking a row is a path where AppKit
        // never reports the highlight going away, so the row would stay lit until it is hovered
        // and left again — the views outlive the menu session.
        MenuBuilder.syncHighlight(in: menu, highlighted: nil)
        MenuBuilder.resetFooterHover(in: menu)
        updateCountdownState()
    }
}
