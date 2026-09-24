import AppKit
import Foundation

@MainActor
final class DataCoordinator {
    let statusService: any StatusFetching
    let usageService: any UsageFetching
    let systemIdleProvider: any SystemIdleProviding
    let pathMonitor: any PathMonitoring
    let profileStore: ProfileStore
    private let defaults: UserDefaults
    var pollTask: Task<Void, Never>?
    var demoRotationIndex = 0
    var loadedCredentials: (cookie: String, orgId: String)?
    let usageHistory: UsageHistory
    var demoFrame: DemoData.DemoFrame?
    var lastFailedAt: Date?
    // Runs pruneArchives() once at launch and then on Constants.History.pruneInterval
    // thereafter, independent of network/credential state — pruning is calendar-driven and
    // has nothing to do with whether a fetch ever succeeds. This is in addition to (not a
    // replacement for) the existing prune-after-detected-boundary call in
    // detectAndStoreResets, which now runs far more often than that alone did.
    var historyMaintenanceTask: Task<Void, Never>?

    var currentStatus: StatusSummary?
    var currentUsage: UsageResponse?
    var usageError: String?
    var statusError: String?
    var lastRefreshed: Date?
    var nextPollDate: Date?
    var currentPollInterval: TimeInterval?
    var scheduler = PollingScheduler()
    var windowAnalyses: [WindowAnalysis] = []
    /// Cached from `usageHistory.quarantinedFileCount()` (an async disk scan) so `monitorState`
    /// can stay a synchronous computed property. Refreshed on the same calendar-driven cadence
    /// as `pruneArchives()` (see `historyMaintenanceTask`) — quarantine accumulation is not
    /// time-sensitive enough to warrant scanning on every poll cycle.
    var quarantinedFileCount = 0

    var onUpdate: (() -> Void)?
    var onCriticalReset: (() -> Void)?

    init(
        statusService: any StatusFetching = StatusService(),
        usageService: any UsageFetching = UsageService(),
        systemIdleProvider: any SystemIdleProviding = SystemIdleService(),
        pathMonitor: any PathMonitoring = PathMonitor(),
        profileStore: ProfileStore = .production(),
        defaults: UserDefaults = .standard,
        usageHistory: UsageHistory = UsageHistory(baseDirectory: UsageHistory.productionBaseDirectory)
    ) {
        self.statusService = statusService
        self.usageService = usageService
        self.systemIdleProvider = systemIdleProvider
        self.pathMonitor = pathMonitor
        self.profileStore = profileStore
        self.defaults = defaults
        self.usageHistory = usageHistory
        reloadCredentials()
        historyMaintenanceTask = Task { [weak self, usageHistory] in
            await self?.runLegacyArchiveMigrationAndPrune()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Constants.History.pruneInterval))
                guard !Task.isCancelled else { break }
                await usageHistory.pruneArchives()
                self?.quarantinedFileCount = await usageHistory.quarantinedFileCount()
            }
        }
        pathMonitor.setOnPathChange { [weak self] satisfied in
            guard let self, satisfied else { return }
            self.scheduler.resetRetryState()
            self.pollTask?.cancel()
            self.pollTask = self.spawnPollTask()
        }
    }

    deinit {
        // `pollTask` is otherwise cancelled before every reassignment (see the path-monitor
        // callback above), but nothing reassigns it after `init`, so only a `deinit` gives it
        // the same guarantee it never outlives this object. `historyMaintenanceTask` is never
        // reassigned at all, so this is the only place it can be cancelled — without it, every
        // `DataCoordinator` (in particular the many short-lived ones the test suite constructs)
        // leaked one infinitely-sleeping task holding `usageHistory` alive for the rest of the
        // process.
        pollTask?.cancel()
        historyMaintenanceTask?.cancel()
    }
}

extension DataCoordinator {
    var monitorState: MonitorState {
        MonitorState(
            usage: UsageSnapshot(
                currentUsage: currentUsage,
                usageError: usageError,
                windowAnalyses: windowAnalyses
            ),
            service: ServiceHealth(
                currentStatus: currentStatus,
                statusError: statusError
            ),
            polling: PollingState(
                isOnline: demoFrame?.isOnline ?? pathMonitor.isSatisfied,
                hasRecentFailure: demoFrame?.hasRecentFailure ?? scheduler.hasRecentFailure,
                lastFailedAt: demoFrame?.lastFailedAt ?? lastFailedAt,
                isAnyServiceStale: demoFrame?.isAnyServiceStale ?? scheduler.isAnyServiceStale,
                currentPollInterval: currentPollInterval,
                isUsageDataExpired: scheduler.isUsageDataExpired
            ),
            history: HistoryHealth(
                lastSaveSucceeded: usageHistory.lastSaveSucceeded,
                persistenceFailingSince: usageHistory.persistenceFailingSince,
                quarantinedFileCount: quarantinedFileCount
            ),
            profiles: ProfileSnapshot(profiles: profileStore.profiles, activeId: profileStore.activeId),
            lastRefreshed: lastRefreshed,
            hasCredentials: hasCredentials,
            showGraph: Constants.Preferences.isUsageGraphEnabled(in: defaults),
            compactServices: Constants.Preferences.isServicesCompact(in: defaults)
        )
    }
}

extension DataCoordinator {
    var hasCredentials: Bool {
        Constants.Demo.isActive || loadedCredentials != nil
    }

    func reloadCredentials() {
        guard !Constants.Demo.isActive,
              let orgId = profileStore.activeProfile?.organizationId,
              let cookie = profileStore.activeCookie,
              !cookie.isEmpty, !orgId.isEmpty else {
            if loadedCredentials != nil {
                usageHistory.switchOrganization(nil)
                clearDisplayedUsage()
            }
            loadedCredentials = nil
            return
        }
        let previousOrgId = loadedCredentials?.orgId
        loadedCredentials = (cookie, orgId)
        if orgId != previousOrgId {
            usageHistory.switchOrganization(orgId)
            clearDisplayedUsage()
            // Defect 5: `historyMaintenanceTask` only ever migrates the ORIGINAL organization
            // present at `init` — if the user switches to a different organization later (here,
            // `previousOrgId != nil` means this is a genuine later switch, not that initial
            // assignment, which `historyMaintenanceTask` already covers), that org's own legacy
            // archives would otherwise never be migrated for the rest of the process. Safe to
            // fire on every switch: `migrateLegacyArchives()` is gated by a cheap directory scan
            // (`hasLegacyArchives`), so re-running it for an org with nothing left to migrate is
            // a near-free no-op.
            if previousOrgId != nil {
                Task { [weak self] in
                    await self?.runLegacyArchiveMigrationAndPrune()
                }
            }
        }
    }

    private func clearDisplayedUsage() {
        currentUsage = nil
        windowAnalyses = []
        usageError = nil
    }

    /// Migrates this organization's legacy archives, prunes retention-expired archives and
    /// quarantine debris, and refreshes the cached quarantine count — the one-time-per-organization
    /// history maintenance pass. Shared by `init`'s `historyMaintenanceTask` (the original
    /// organization present at launch) and `reloadCredentials()` (Defect 5: a later switch to a
    /// different organization) so the two call sites can never drift apart.
    func runLegacyArchiveMigrationAndPrune() async {
        _ = await usageHistory.migrateLegacyArchives()
        await usageHistory.pruneArchives()
        quarantinedFileCount = await usageHistory.quarantinedFileCount()
    }
}
