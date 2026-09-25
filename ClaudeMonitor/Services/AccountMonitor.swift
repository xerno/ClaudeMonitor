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
        // Runs pruneArchives() once at launch and then on Constants.History.pruneInterval
        // thereafter, independent of network/credential state — pruning is calendar-driven and
        // has nothing to do with whether a fetch ever succeeds. This is in addition to (not a
        // replacement for) the existing prune-after-detected-boundary call in
        // detectAndStoreResets, which now runs far more often than that alone did.
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

    /// Migrates this organization's legacy archives, prunes retention-expired archives and
    /// quarantine debris, and refreshes the cached quarantine count — the one-time-per-organization
    /// history maintenance pass.
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
            // Don't stamp lastFailedAt for offline ticks: the "Last update failed at HH:MM" row
            // would advance every tick despite no real attempt being made. Stale banner already
            // signals the problem at threshold.
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
        // Only a FRESH, complete usage response may drive history recording, boundary
        // detection, and missing-window archiving — never a stale `currentUsage` retained
        // from a previous successful cycle (see `refreshUsage()`'s doc comment). The UI may
        // still display stale data (via `monitorState`/`currentUsage`), but stale data must
        // never be re-recorded as if it were a fresh, confirmed-unchanged observation.
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

    /// Whether a `refreshUsage()` cycle produced a response fresh enough to drive history
    /// recording (`.fresh`), or is merely retaining a previously-fetched value for display
    /// while this cycle's fetch didn't happen or failed (`.stale`). `currentUsage` alone can't
    /// express this distinction — on any non-auth failure it's left holding the PREVIOUS
    /// successful value, so `if let newUsage = currentUsage` cannot tell a failed cycle apart
    /// from a fresh success. Callers of `refreshUsage()` must use this return value (not
    /// `currentUsage`) to decide whether to feed a cycle into `UsageHistory.record`,
    /// `archiveMissingWindows`, or boundary detection — recording a stale value would
    /// fabricate a "confirmed unchanged at now" sample that never happened, destroying gap
    /// detection and violating `archiveMissingWindows`' documented precondition.
    enum UsageFetchOutcome: Sendable {
        case fresh(UsageResponse)
        case stale
    }

    func refreshUsage() async -> UsageFetchOutcome {
        guard !Task.isCancelled else { return .stale }
        // Captured BEFORE the fetch's suspension point. `UsageHistory.generation` is bumped by
        // `clearAll`, which is synchronous and eager, so it can complete while this fetch is
        // suspended; an in-flight response landing afterwards would repopulate history the user
        // had just explicitly erased.
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

    /// Runs `UsageHistory`'s boundary detection per entry and returns the keys of entries
    /// that had a genuine new-window boundary this cycle — the single authoritative signal
    /// consumed both for archive pruning and for `Formatting.detectCriticalReset` (Task 5:
    /// critical-reset detection no longer re-derives a boundary from raw timestamps).
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
    // Builds the infinitely-looping poll task with only a *weak* capture of self at the
    // Task-closure level. `pollLoop()` used to be an ordinary instance method called as
    // `self.pollLoop()`; because that call binds `self` strongly for the entire (never
    // returning, except on cancellation) execution of the method, wrapping the outer Task
    // in `[weak self]` did nothing to break the `self -> pollTask -> closure -> self` cycle.
    //
    // Here, every iteration confines its strong reference to `self` to the `do` block below —
    // a `do` without `catch` is purely a scope in Swift, and a local's lifetime ends, by
    // language guarantee (not merely as an ARC optimization that may or may not fire), at the
    // closing brace of the scope it was declared in. So the strong `self` bound by `guard let
    // self` is released right there, *before* either sleep call below ever runs — nothing
    // used while sleeping (`cycle.delay`, `cycle.isAwayMode`, `cycle.idleProvider`) is, or
    // refers back to, the monitor. That means the monitor is free to deallocate at
    // any point during even a long away-mode wait, not merely once per outer cycle: the two
    // sleep branches below never touch `self` again at all (only the plain values/existential
    // captured into `cycle`), so the very next time this loop needs `self` — the top of the
    // next outer iteration — a gone monitor is detected via the weak capture and the task
    // returns for good.
    private func spawnPollTask() -> Task<Void, Never> {
        Task { [weak self] in
            while !Task.isCancelled {
                // Declared outside the `do` block so its value survives past it, but only ever
                // assigned along the path that falls through to the closing brace below — the
                // only other path (`guard let self else`) returns from this whole Task closure,
                // so definite-initialization is satisfied without `cycle` needing to be Optional.
                let cycle: (delay: TimeInterval, isAwayMode: Bool, idleProvider: any SystemIdleProviding)
                do {
                    guard let self else { return }
                    await self.refresh()
                    guard !Task.isCancelled else { return }
                    self.onUpdate?()
                    let delay = self.nextPollDate.map { $0.timeIntervalSinceNow } ?? Constants.Polling.baseInterval
                    cycle = (delay, self.scheduler.isAwayMode, self.systemIdleProvider)
                } // `self` goes out of scope here.

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
