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
            button: button, usage: state.currentUsage,
            hasCredentials: state.hasCredentials,
            isStale: state.isStale || state.isUsageStale
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    // MARK: - UI Updates

    private func applyUIUpdates() {
        animationTask?.cancel()
        let state = coordinator.monitorState
        if let button = statusItem.button {
            StatusBarRenderer.updateIcon(
                button: button, status: state.currentStatus,
                hasRefreshWarning: state.isStale
            )
            StatusBarRenderer.updateText(
                button: button, usage: state.currentUsage,
                hasCredentials: state.hasCredentials,
                isStale: state.isStale || state.isUsageStale,
                windowAnalyses: state.windowAnalyses
            )
        }
        if let menu = statusItem.menu {
            usageCache = MenuBuilder.populate(menu: menu, state: state, target: self)
        }
        updateCountdownState()
    }

    // MARK: - Menu

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        usageCache = MenuBuilder.populate(menu: menu, state: coordinator.monitorState, target: self)
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

    @objc func didSelectUsageWindow(_ sender: NSMenuItem) {
        guard let menu = statusItem.menu else { return }
        let index = sender.tag - MenuBuilder.usageBaseTag
        guard let graphView = menu.item(withTag: MenuBuilder.usageGraphTag)?.view as? UsageGraphView else { return }
        graphView.selectWindow(at: index)
        MenuBuilder.syncUsageCheckmarks(in: menu, selectedIndex: graphView.currentSelectedIndex)
    }

    @objc func didSelectAbout() {
        if aboutController == nil {
            aboutController = AboutWindowController()
        }
        aboutController?.showWindow(nil)
    }

    @objc func didSelectPreferences() {
        if preferencesController == nil {
            preferencesController = PreferencesWindowController { [weak self] in
                self?.coordinator.restartPolling()
            }
        }
        preferencesController?.showWindow(nil)
    }

    private func showSetup() {
        if setupController == nil {
            setupController = SetupWindowController { [weak self] in
                self?.coordinator.restartPolling()
            }
        }
        setupController?.showWindow(nil)
    }
}

extension MenuBarController: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        isMenuOpen = true
        updateCountdownState()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        updateCountdownState()
    }
}
