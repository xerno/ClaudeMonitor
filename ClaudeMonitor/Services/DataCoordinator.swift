import Foundation

@MainActor
final class DataCoordinator {
    private let statusService: any StatusFetching
    private let usageService: any UsageFetching
    private let systemIdleProvider: any SystemIdleProviding
    private let loadCredential: @Sendable (String) -> String?
    private var pollTask: Task<Void, Never>?
    private var demoRotationIndex = 0
    private var loadedCredentials: (cookie: String, orgId: String)?
    private let usageHistory = UsageHistory()

    private(set) var currentStatus: StatusSummary?
    private(set) var currentUsage: UsageResponse?
    private(set) var usageError: String?
    private(set) var statusError: String?
    private(set) var lastRefreshed: Date?
    private var nextPollDate: Date?
    private(set) var currentPollInterval: TimeInterval?
    private(set) var scheduler = PollingScheduler()
    private(set) var windowAnalyses: [WindowAnalysis] = []

    var onUpdate: (() -> Void)?
    var onCriticalReset: (() -> Void)?

    init(
        statusService: any StatusFetching = StatusService(),
        usageService: any UsageFetching = UsageService(),
        systemIdleProvider: any SystemIdleProviding = SystemIdleService(),
        loadCredential: @escaping @Sendable (String) -> String? = { KeychainService.load(key: $0) }
    ) {
        self.statusService = statusService
        self.usageService = usageService
        self.systemIdleProvider = systemIdleProvider
        self.loadCredential = loadCredential
        UsageHistory.migrateAndDeleteLegacyData()
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
            currentPollInterval: currentPollInterval,
            windowAnalyses: windowAnalyses,
            isUsageStale: scheduler.isUsageStale
        )
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                await refresh()
                guard !Task.isCancelled else { break }
                let delay = nextPollDate.map { $0.timeIntervalSinceNow } ?? Constants.Polling.baseInterval
                guard delay > 0 else { continue }

                if scheduler.isAwayMode {
                    let deadline = Date().addingTimeInterval(delay)
                    while Date() < deadline && !Task.isCancelled {
                        let sleepTime = min(Constants.Polling.heartbeatInterval, deadline.timeIntervalSinceNow)
                        guard sleepTime > 0 else { break }
                        try? await Task.sleep(for: .seconds(sleepTime))
                        if systemIdleProvider.idleTime() < Constants.Polling.awayThreshold {
                            break
                        }
                    }
                } else {
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
            let (usage, status, demoSamples) = DemoData.scenario(scenario)
            currentUsage = usage
            currentStatus = status
            usageError = nil
            statusError = nil
            let now = Date()
            lastRefreshed = now
            nextPollDate = now.addingTimeInterval(Constants.Demo.rotationInterval)
            currentPollInterval = Constants.Demo.rotationInterval
            windowAnalyses = usage.entries.map { entry in
                UsageHistory.analyze(entry: entry, samples: demoSamples[entry.key] ?? [], now: now)
            }
            onUpdate?()
            return
        }
        let usageBeforeRefresh = currentUsage
        async let statusResult: Void = refreshStatus()
        async let usageResult: Void = refreshUsage()
        _ = await (statusResult, usageResult)
        guard !Task.isCancelled else { return }
        if let newUsage = currentUsage {
            let now = Date()
            var anyReset = false
            let previousByKey = Dictionary(uniqueKeysWithValues: usageBeforeRefresh?.entries.map { ($0.key, $0) } ?? [])
            for entry in newUsage.entries {
                let previousEntry = previousByKey[entry.key]
                let didReset = usageHistory.detectAndHandleReset(
                    entry: entry,
                    newResetsAt: entry.window.resetsAt,
                    previousResetsAt: previousEntry?.window.resetsAt
                )
                if didReset {
                    anyReset = true
                }
            }
            if anyReset {
                usageHistory.pruneArchives(currentEntries: newUsage.entries)
            }
            usageHistory.record(entries: newUsage.entries, at: now)
            usageHistory.save()
            windowAnalyses = newUsage.entries.map { entry in
                UsageHistory.analyze(entry: entry, samples: usageHistory.samples(for: entry), now: now)
            }
        }
        scheduler.adjustPollingRate(windowAnalyses: windowAnalyses, systemIdleTime: systemIdleProvider.idleTime())
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
            if loadedCredentials != nil {
                usageHistory.switchOrganization(nil)
                windowAnalyses = []
            }
            loadedCredentials = nil
            return
        }
        let previousOrgId = loadedCredentials?.orgId
        loadedCredentials = (cookie, orgId)
        if orgId != previousOrgId {
            usageHistory.switchOrganization(orgId)
            windowAnalyses = []
        }
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
