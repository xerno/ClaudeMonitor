import AppKit

@MainActor
final class MenuBarController: NSObject, MenuActions {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let statusService = StatusService()
    private let usageService = UsageService()
    private var preferencesController: PreferencesWindowController?
    private var setupController: SetupWindowController?
    private var aboutController: AboutWindowController?

    private var currentStatus: StatusSummary?
    private var currentUsage: UsageResponse?
    private var usageError: String?
    private var statusError: String?
    private var lastRefreshed: Date?
    private var pollTask: Task<Void, Never>?
    private var scheduler = PollingScheduler()

    private var hasCredentials: Bool {
        guard let cookie = KeychainService.load(key: Constants.Keychain.cookieString),
              let orgId = KeychainService.load(key: Constants.Keychain.organizationId),
              !cookie.isEmpty, !orgId.isEmpty else { return false }
        return true
    }

    override init() {
        super.init()
        configureStatusItem()
        startPolling()
        if !hasCredentials {
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                showSetup()
            }
        }
    }

    // MARK: - Polling

    private func startPolling() {
        pollTask = Task {
            while !Task.isCancelled {
                await refreshAll()
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(scheduler.nextPollInterval(usage: currentUsage)))
            }
        }
    }

    // MARK: - Setup

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.imagePosition = .imageTrailing
        button.image = StatusBarRenderer.makeImage(symbolName: "circle.fill", color: .systemGray)
        StatusBarRenderer.updateText(
            button: button, usage: currentUsage, hasCredentials: hasCredentials,
            isStale: scheduler.isUsageStale
        )
        rebuildMenu()
    }

    // MARK: - Data Refresh

    private func refreshAll() async {
        async let statusResult: Void = refreshStatus()
        async let usageResult: Void = refreshUsage()
        _ = await (statusResult, usageResult)
        guard !Task.isCancelled else { return }
        let isCritical = currentUsage.map(Formatting.hasAnyCriticalWindow) ?? false
        scheduler.adjustPollingRate(usage: currentUsage, isCritical: isCritical)
        applyUIUpdates()
    }

    private func refreshStatus() async {
        guard !Task.isCancelled else { return }
        do {
            currentStatus = try await statusService.fetch()
            statusError = nil
            scheduler.recordStatusSuccess()
        } catch {
            if Task.isCancelled { return }
            scheduler.recordStatusFailure(category: RetryCategory(classifying: error))
            if scheduler.statusState.consecutiveFailures >= Constants.Retry.failureThreshold {
                statusError = error.localizedDescription
            }
        }
    }

    private func refreshUsage() async {
        guard !Task.isCancelled else { return }
        guard let cookie = KeychainService.load(key: Constants.Keychain.cookieString),
              let orgId = KeychainService.load(key: Constants.Keychain.organizationId),
              !cookie.isEmpty, !orgId.isEmpty else {
            usageError = "Configure credentials in Preferences"
            return
        }
        do {
            currentUsage = try await usageService.fetch(organizationId: orgId, cookieString: cookie)
            usageError = nil
            scheduler.recordUsageSuccess()
        } catch {
            if Task.isCancelled { return }
            let category = RetryCategory(classifying: error)
            scheduler.recordUsageFailure(category: category)
            if scheduler.usageState.consecutiveFailures >= Constants.Retry.failureThreshold {
                usageError = error.localizedDescription
            }
            if category == .authFailure {
                currentUsage = nil
            }
        }
    }

    // MARK: - UI Updates

    private func applyUIUpdates() {
        lastRefreshed = Date()
        if let button = statusItem.button {
            StatusBarRenderer.updateIcon(
                button: button, status: currentStatus,
                hasRefreshWarning: scheduler.hasRefreshWarning
            )
            StatusBarRenderer.updateText(
                button: button, usage: currentUsage, hasCredentials: hasCredentials,
                isStale: scheduler.isUsageStale
            )
        }
        rebuildMenu()
    }

    private var currentMonitorState: MonitorState {
        MonitorState(
            currentUsage: scheduler.isUsageStale ? nil : currentUsage,
            currentStatus: currentStatus,
            usageError: usageError,
            statusError: statusError,
            lastRefreshed: lastRefreshed,
            hasCredentials: hasCredentials
        )
    }

    // MARK: - Menu

    private func rebuildMenu() {
        statusItem.menu = MenuBuilder.build(state: currentMonitorState, target: self)
    }

    // MARK: - MenuActions

    @objc func didSelectRefresh() {
        pollTask?.cancel()
        scheduler.reset()
        startPolling()
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
                self?.didSelectRefresh()
            }
        }
        preferencesController?.showWindow(nil)
    }

    private func showSetup() {
        if setupController == nil {
            setupController = SetupWindowController { [weak self] in
                self?.didSelectRefresh()
            }
        }
        setupController?.showWindow(nil)
    }
}
