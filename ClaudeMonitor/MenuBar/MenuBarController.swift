import AppKit

@MainActor
final class MenuBarController: NSObject, MenuActions {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let coordinator = DataCoordinator()
    private var preferencesController: PreferencesWindowController?
    private var setupController: SetupWindowController?
    private var aboutController: AboutWindowController?
    private var countdownTask: Task<Void, Never>?
    private var isMenuOpen = false

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
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                showSetup()
            }
        }
    }

    // MARK: - Setup

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageTrailing
        button.image = StatusBarRenderer.makeImage(symbolName: "circle.fill", color: .systemGray)
        StatusBarRenderer.updateText(
            button: button, usage: coordinator.currentUsage,
            hasCredentials: coordinator.hasCredentials,
            isStale: coordinator.scheduler.isUsageStale
        )
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        rebuildMenu()
    }

    // MARK: - UI Updates

    private func applyUIUpdates() {
        if let button = statusItem.button {
            StatusBarRenderer.updateIcon(
                button: button, status: coordinator.currentStatus,
                hasRefreshWarning: coordinator.scheduler.hasRefreshWarning
            )
            StatusBarRenderer.updateText(
                button: button, usage: coordinator.currentUsage,
                hasCredentials: coordinator.hasCredentials,
                isStale: coordinator.scheduler.isUsageStale
            )
            button.toolTip = Formatting.buildTooltip(state: coordinator.monitorState)
        }
        rebuildMenu()
        updateCountdownState()
    }

    // MARK: - Critical Reset Alert

    private func handleCriticalReset() {
        if UserDefaults.standard.bool(forKey: Constants.Preferences.resetSoundEnabled) {
            NSSound(named: .init(Constants.Sounds.criticalReset))?.play()
        }
        animateResetIcon()
    }

    private func animateResetIcon() {
        guard let button = statusItem.button else { return }
        button.image = StatusBarRenderer.makeImage(symbolName: "checkmark.circle.fill", color: .systemGreen)
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            StatusBarRenderer.updateIcon(
                button: button,
                status: coordinator.currentStatus,
                hasRefreshWarning: coordinator.scheduler.hasRefreshWarning
            )
        }
    }

    // MARK: - Countdown

    private var shouldCountdownRun: Bool {
        let isBlocked = Formatting.blockingLimit(coordinator.currentUsage) != nil
        let menuHasResetTimes = isMenuOpen && coordinator.currentUsage != nil
        return isBlocked || menuHasResetTimes
    }

    private func updateCountdownState() {
        if shouldCountdownRun {
            startCountdown()
        } else {
            stopCountdown()
        }
    }

    private func startCountdown() {
        countdownTask?.cancel()
        countdownTask = Task {
            while !Task.isCancelled {
                guard let target = nextWakeTime() else { break }
                let delay = target.timeIntervalSinceNow
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
                guard !Task.isCancelled else { break }
                updateCountdownDisplays()
            }
            if !Task.isCancelled,
               let blockedUntil = Formatting.blockingLimit(coordinator.currentUsage),
               blockedUntil.timeIntervalSinceNow <= 0 {
                coordinator.restartPolling()
            }
        }
    }

    private func stopCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    private func updateCountdownDisplays() {
        if let button = statusItem.button {
            StatusBarRenderer.updateText(
                button: button, usage: coordinator.currentUsage,
                hasCredentials: coordinator.hasCredentials,
                isStale: coordinator.scheduler.isUsageStale
            )
            button.toolTip = Formatting.buildTooltip(state: coordinator.monitorState)
        }
        if isMenuOpen, let menu = statusItem.menu {
            if let usage = coordinator.currentUsage {
                MenuBuilder.refreshTimes(in: menu, usage: usage)
            }
            MenuBuilder.refreshControlTimes(
                in: menu,
                lastRefreshed: coordinator.lastRefreshed,
                interval: coordinator.currentPollInterval
            )
        }
    }

    private func nextWakeTime() -> Date? {
        var resetTimes: [Date] = []
        if let blockedUntil = Formatting.blockingLimit(coordinator.currentUsage) {
            resetTimes.append(blockedUntil)
        }
        if isMenuOpen, let usage = coordinator.currentUsage {
            resetTimes.append(contentsOf: usage.allWindows.compactMap(\.resetsAt))
        }
        guard !resetTimes.isEmpty else { return nil }
        return Formatting.nextTickTarget(resetTimes: resetTimes, now: Date())
    }

    // MARK: - Menu

    private func rebuildMenu() {
        guard let menu = statusItem.menu else { return }
        MenuBuilder.populate(menu: menu, state: coordinator.monitorState, target: self)
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
