import Foundation

@MainActor
final class AccountMonitor {
    let organizationId: String
    private(set) var cookie: String
    let usageHistory: UsageHistory
    private let usageService: any UsageFetching
    private let systemIdleProvider: any SystemIdleProviding
    private let pathMonitor: any PathMonitoring

    var scheduler = PollingScheduler()
    private(set) var currentUsage: UsageResponse?
    private(set) var usageError: String?
    private(set) var windowAnalyses: [WindowAnalysis] = []
    private(set) var lastRefreshed: Date?
    private(set) var nextPollDate: Date?
    private(set) var currentPollInterval: TimeInterval?
    private(set) var lastFailedAt: Date?
    private(set) var quarantinedFileCount = 0
    private(set) var pollTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?

    var onUpdate: (() -> Void)?
    var onCriticalReset: (() -> Void)?

    init(
        organizationId: String,
        cookie: String,
        usageHistory: UsageHistory,
        usageService: any UsageFetching,
        systemIdleProvider: any SystemIdleProviding,
        pathMonitor: any PathMonitoring
    ) {
        self.organizationId = organizationId
        self.cookie = cookie
        self.usageHistory = usageHistory
        self.usageService = usageService
        self.systemIdleProvider = systemIdleProvider
        self.pathMonitor = pathMonitor
        // Not tied to fetch success: retention is calendar-driven.
        maintenanceTask = Task { [weak self, usageHistory] in
            await self?.runLegacyArchiveMigrationAndPrune()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.History.pruneInterval))
                guard !Task.isCancelled else { break }
                await usageHistory.pruneArchives()
                self?.quarantinedFileCount = await usageHistory.quarantinedFileCount()
            }
        }
    }

    deinit {
        pollTask?.cancel()
        maintenanceTask?.cancel()
    }

    func updateCookie(_ cookie: String) {
        self.cookie = cookie
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = spawnPollTask()
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func stop() {
        stopPolling()
        maintenanceTask?.cancel()
        maintenanceTask = nil
    }

    func runLegacyArchiveMigrationAndPrune() async {
        _ = await usageHistory.migrateLegacyArchives()
        await usageHistory.pruneArchives()
        quarantinedFileCount = await usageHistory.quarantinedFileCount()
    }
}

extension AccountMonitor {
    func refresh(now: Date = Date()) async {
        if !pathMonitor.isSatisfied {
            scheduler.recordUsageFailure(category: .transient)
            // No lastFailedAt stamp: no attempt was made, and the "Last update failed" row would
            // advance every tick.
            commitPollState(now: now, schedulerInterval: scheduler.nextPollInterval(usage: currentUsage))
            return
        }
        let previousAnalyses = windowAnalyses
        let generationAtStart = usageHistory.generation
        let outcome = await refreshUsage()
        guard !Task.isCancelled else { return }
        if scheduler.usageState.consecutiveFailures == 0 {
            lastFailedAt = nil
        }
        if case .fresh(let newUsage) = outcome {
            guard isRefreshCurrent(generation: generationAtStart) else { return }
            let genuineBoundaryKeys = await detectAndStoreResets(current: newUsage.entries, at: now)
            guard isRefreshCurrent(generation: generationAtStart) else { return }
            usageHistory.record(entries: newUsage.entries, at: now)
            await usageHistory.archiveMissingWindows(
                currentIdentities: Set(newUsage.entries.map { $0.storageIdentity }),
                at: now
            )
            guard isRefreshCurrent(generation: generationAtStart) else { return }
            await usageHistory.save()
            guard isRefreshCurrent(generation: generationAtStart) else { return }
            windowAnalyses = newUsage.entries.map { entry in
                UsageHistory.analyze(
                    entry: entry,
                    samples: usageHistory.samples(for: entry),
                    events: usageHistory.storage[entry.storageIdentity]?.events ?? [],
                    now: now
                )
            }
            if Formatting.detectCriticalReset(previousAnalyses: previousAnalyses, genuineBoundaryKeys: genuineBoundaryKeys) {
                onCriticalReset?()
            }
        }
        scheduler.adjustPollingRate(windowAnalyses: windowAnalyses, systemIdleTime: systemIdleProvider.idleTime())
        commitPollState(now: Date(), schedulerInterval: scheduler.nextPollInterval(usage: currentUsage))
    }

    private func isRefreshCurrent(generation: Int) -> Bool {
        usageHistory.generation == generation
    }

    /// `.stale`: the fetch failed or didn't run, and `currentUsage` may still hold the previous
    /// success, so it can't tell the two apart. Only `.fresh` may feed `UsageHistory.record`,
    /// `archiveMissingWindows` or boundary detection: recording stale data fabricates a
    /// "confirmed unchanged" sample and defeats gap detection.
    enum UsageFetchOutcome: Sendable {
        case fresh(UsageResponse)
        case stale
    }

    func refreshUsage() async -> UsageFetchOutcome {
        guard !Task.isCancelled else { return .stale }
        // Captured before the await: `clearAll` bumps `generation` while the fetch is suspended,
        // and a late response must not repopulate erased history.
        let generationAtFetch = usageHistory.generation
        do {
            let response = try await usageService.fetch(organizationId: organizationId, cookieString: cookie)
            guard usageHistory.generation == generationAtFetch else { return .stale }
            currentUsage = response
            usageError = nil
            scheduler.recordUsageSuccess()
            return .fresh(response)
        } catch {
            if Task.isCancelled { return .stale }
            let category = RetryCategory(classifying: error)
            scheduler.recordUsageFailure(category: category)
            lastFailedAt = Date()
            if scheduler.usageState.consecutiveFailures >= Constants.Retry.failureThreshold {
                usageError = error.localizedDescription
            }
            if category == .authFailure {
                currentUsage = nil
                windowAnalyses = []
            }
            return .stale
        }
    }

    /// Keys of entries with a genuine new-window boundary this cycle: the only boundary signal
    /// `Formatting.detectCriticalReset` uses.
    @discardableResult
    func detectAndStoreResets(current: [WindowEntry], at now: Date) async -> Set<String> {
        var genuineBoundaryKeys: Set<String> = []
        for entry in current {
            let didReset = await usageHistory.detectAndHandleReset(
                entry: entry,
                newResetsAt: entry.window.resetsAt,
                at: now
            )
            if didReset {
                genuineBoundaryKeys.insert(entry.key)
            }
        }
        if !genuineBoundaryKeys.isEmpty {
            await usageHistory.pruneArchives()
        }
        return genuineBoundaryKeys
    }

    private func commitPollState(now: Date, schedulerInterval: TimeInterval) {
        lastRefreshed = now
        nextPollDate = now.addingTimeInterval(schedulerInterval)
        currentPollInterval = schedulerInterval
    }
}

extension AccountMonitor {
    // The strong `self` lives only in the `do` scope and is released at its brace (language guarantee,
    // not an ARC optimization), before either sleep, so the monitor can deallocate mid-wait. A
    // long-running method called on `self` would pin it for the whole loop and defeat `[weak self]`.
    private func spawnPollTask() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                // Outlives `do`; the only other path returns, so it needn't be Optional.
                let cycle: (delay: TimeInterval, isAwayMode: Bool, idleProvider: any SystemIdleProviding)
                do {
                    guard let self else { return }
                    await self.refresh()
                    guard !Task.isCancelled else { return }
                    self.onUpdate?()
                    let delay = self.nextPollDate.map { $0.timeIntervalSinceNow } ?? Constants.Polling.baseInterval
                    cycle = (delay, self.scheduler.isAwayMode, self.systemIdleProvider)
                }

                guard cycle.delay > 0 else { continue }

                if cycle.isAwayMode {
                    let deadline = Date().addingTimeInterval(cycle.delay)
                    while !Task.isCancelled {
                        let sleepTime = min(Constants.Polling.heartbeatInterval, deadline.timeIntervalSinceNow)
                        guard sleepTime > 0 else { break }
                        try? await Task.sleep(for: .seconds(sleepTime))
                        if cycle.idleProvider.idleTime() < Constants.Polling.awayThreshold {
                            break
                        }
                    }
                } else {
                    try? await Task.sleep(for: .seconds(cycle.delay))
                }
            }
        }
    }
}
