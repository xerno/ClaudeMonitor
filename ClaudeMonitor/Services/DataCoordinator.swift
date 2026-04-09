import Foundation

@MainActor
final class DataCoordinator {
    private let statusService: any StatusFetching
    private let usageService: any UsageFetching
    private let loadCredential: @Sendable (String) -> String?
    private var pollTask: Task<Void, Never>?
    private var demoRotationIndex = 0
    private var loadedCredentials: (cookie: String, orgId: String)?

    private(set) var currentStatus: StatusSummary?
    private(set) var currentUsage: UsageResponse?
    private(set) var usageError: String?
    private(set) var statusError: String?
    private(set) var lastRefreshed: Date?
    private var nextPollDate: Date?
    private(set) var currentPollInterval: TimeInterval?
    private(set) var scheduler = PollingScheduler()

    var onUpdate: (() -> Void)?
    var onCriticalReset: (() -> Void)?

    init(
        statusService: any StatusFetching = StatusService(),
        usageService: any UsageFetching = UsageService(),
        loadCredential: @escaping @Sendable (String) -> String? = { KeychainService.load(key: $0) }
    ) {
        self.statusService = statusService
        self.usageService = usageService
        self.loadCredential = loadCredential
        reloadCredentials()
    }

    var hasCredentials: Bool {
        Constants.Demo.isActive || loadedCredentials != nil
    }

    var monitorState: MonitorState {
        MonitorState(
            currentUsage: scheduler.isUsageStale ? nil : currentUsage,
            currentStatus: currentStatus,
            usageError: usageError,
            statusError: statusError,
            lastRefreshed: lastRefreshed,
            hasCredentials: hasCredentials,
            currentPollInterval: currentPollInterval
        )
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                guard !Task.isCancelled else { break }
                let delay = nextPollDate.map { $0.timeIntervalSinceNow } ?? Constants.Polling.baseInterval
                if delay > 0 {
                    try? await Task.sleep(for: .seconds(delay))
                }
            }
        }
    }

    func restartPolling() {
        pollTask?.cancel()
        reloadCredentials()
        scheduler.reset()
        startPolling()
    }

    func refresh() async {
        if Constants.Demo.isActive {
            let scenario = Constants.Demo.rotationOrder[demoRotationIndex]
            demoRotationIndex = (demoRotationIndex + 1) % Constants.Demo.rotationOrder.count
            let (usage, status) = DemoData.scenario(scenario)
            currentUsage = usage
            currentStatus = status
            usageError = nil
            statusError = nil
            lastRefreshed = Date()
            nextPollDate = Date().addingTimeInterval(Constants.Demo.rotationInterval)
            currentPollInterval = Constants.Demo.rotationInterval
            onUpdate?()
            return
        }
        let usageBeforeRefresh = currentUsage
        async let statusResult: Void = refreshStatus()
        async let usageResult: Void = refreshUsage()
        _ = await (statusResult, usageResult)
        guard !Task.isCancelled else { return }
        let isCritical = currentUsage.map(Formatting.hasAnyCriticalWindow) ?? false
        scheduler.adjustPollingRate(usage: currentUsage, isCritical: isCritical)
        let now = Date()
        lastRefreshed = now
        let pollInterval = scheduler.nextPollInterval(usage: currentUsage)
        nextPollDate = now.addingTimeInterval(pollInterval)
        currentPollInterval = pollInterval
        onUpdate?()
        if let prev = usageBeforeRefresh, let curr = currentUsage,
           Formatting.detectCriticalReset(previous: prev, current: curr) {
            onCriticalReset?()
        }
    }

    // MARK: - Private

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

    private func reloadCredentials() {
        guard !Constants.Demo.isActive,
              let cookie = loadCredential(Constants.Keychain.cookieString),
              let orgId = loadCredential(Constants.Keychain.organizationId),
              !cookie.isEmpty, !orgId.isEmpty else {
            loadedCredentials = nil
            return
        }
        loadedCredentials = (cookie, orgId)
    }

    private func refreshUsage() async {
        guard !Task.isCancelled else { return }
        guard let credentials = loadedCredentials else {
            usageError = String(localized: "credentials.configure", bundle: .module)
            return
        }
        do {
            currentUsage = try await usageService.fetch(organizationId: credentials.orgId, cookieString: credentials.cookie)
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
}
