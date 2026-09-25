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
    private let makeUsageHistory: @MainActor () -> UsageHistory
    private(set) var monitors: [String: AccountMonitor] = [:]
    var statusPollTask: Task<Void, Never>?
    var demoRotationIndex = 0
    var demoFrame: DemoData.DemoFrame?
    var demoWindowAnalyses: [WindowAnalysis] = []
    var demoRefreshedAt: Date?

    var currentStatus: StatusSummary?
    var statusError: String?
    var statusLastFailedAt: Date?
    var statusScheduler = PollingScheduler()

    var onUpdate: (() -> Void)?
    var onCriticalReset: (() -> Void)?

    init(
        statusService: any StatusFetching = StatusService(),
        usageService: any UsageFetching = UsageService(),
        systemIdleProvider: any SystemIdleProviding = SystemIdleService(),
        pathMonitor: any PathMonitoring = PathMonitor(),
        profileStore: ProfileStore = .production(),
        defaults: UserDefaults = .standard,
        makeUsageHistory: @escaping @MainActor () -> UsageHistory = { UsageHistory(baseDirectory: UsageHistory.productionBaseDirectory) }
    ) {
        self.statusService = statusService
        self.usageService = usageService
        self.systemIdleProvider = systemIdleProvider
        self.pathMonitor = pathMonitor
        self.profileStore = profileStore
        self.defaults = defaults
        self.makeUsageHistory = makeUsageHistory
        reconcileMonitors()
        pathMonitor.setOnPathChange { [weak self] satisfied in
            guard let self, satisfied else { return }
            self.statusScheduler.resetRetryState()
            for monitor in self.monitors.values {
                monitor.scheduler.resetRetryState()
            }
            self.restartLoops()
        }
    }

    deinit {
        statusPollTask?.cancel()
    }
}

extension DataCoordinator {
    var activeMonitor: AccountMonitor? {
        guard let profile = profileStore.activeProfile else { return nil }
        return monitors[Self.monitorKey(organizationId: profile.organizationId)]
    }

    var usageHistories: [UsageHistory] {
        monitors.values.map(\.usageHistory)
    }

    var currentUsage: UsageResponse? {
        demoFrame?.usage ?? activeMonitor?.currentUsage
    }

    var usageError: String? {
        guard let monitor = activeMonitor else {
            return Constants.Demo.isActive ? nil : String(localized: "credentials.configure", bundle: .module)
        }
        return monitor.usageError
    }

    var windowAnalyses: [WindowAnalysis] {
        demoFrame != nil ? demoWindowAnalyses : activeMonitor?.windowAnalyses ?? []
    }

    var lastRefreshed: Date? {
        demoRefreshedAt ?? activeMonitor?.lastRefreshed
    }

    var currentPollInterval: TimeInterval? {
        demoFrame?.pollInterval ?? activeMonitor?.currentPollInterval
    }

    var hasCredentials: Bool {
        Constants.Demo.isActive || activeMonitor != nil
    }

    var monitorState: MonitorState {
        let monitor = activeMonitor
        let histories = usageHistories
        return MonitorState(
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
                hasRecentFailure: demoFrame?.hasRecentFailure
                    ?? (statusScheduler.hasRecentFailure || monitor?.scheduler.hasRecentFailure == true),
                lastFailedAt: demoFrame?.lastFailedAt
                    ?? [statusLastFailedAt, monitor?.lastFailedAt].compactMap { $0 }.max(),
                isAnyServiceStale: demoFrame?.isAnyServiceStale
                    ?? (statusScheduler.isAnyServiceStale || monitor?.scheduler.isAnyServiceStale == true),
                currentPollInterval: currentPollInterval,
                isUsageDataExpired: monitor?.scheduler.isUsageDataExpired ?? false
            ),
            history: HistoryHealth(
                lastSaveSucceeded: histories.allSatisfy(\.lastSaveSucceeded),
                persistenceFailingSince: histories.compactMap(\.persistenceFailingSince).min(),
                quarantinedFileCount: monitors.values.reduce(0) { $0 + $1.quarantinedFileCount }
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
    static func monitorKey(organizationId: String) -> String {
        organizationId.lowercased()
    }

    func reconcileMonitors() {
        guard !Constants.Demo.isActive else { return }
        var retained: [String: AccountMonitor] = [:]
        for profile in profileStore.profiles {
            guard !profile.organizationId.isEmpty,
                  let cookie = profileStore.cookie(for: profile), !cookie.isEmpty else { continue }
            let key = Self.monitorKey(organizationId: profile.organizationId)
            if let existing = monitors[key] {
                existing.updateCookie(cookie)
                retained[key] = existing
            } else {
                retained[key] = makeMonitor(organizationId: profile.organizationId, cookie: cookie)
            }
        }
        for (key, monitor) in monitors where retained[key] == nil {
            monitor.stop()
        }
        monitors = retained
    }

    private func makeMonitor(organizationId: String, cookie: String) -> AccountMonitor {
        let monitor = AccountMonitor(
            organizationId: organizationId,
            cookie: cookie,
            usageHistory: makeUsageHistory(),
            usageService: usageService,
            systemIdleProvider: systemIdleProvider,
            pathMonitor: pathMonitor
        )
        monitor.onUpdate = { [weak self, weak monitor] in
            guard let self, let monitor, monitor === self.activeMonitor else { return }
            self.onUpdate?()
        }
        monitor.onCriticalReset = { [weak self, weak monitor] in
            guard let self, let monitor, monitor === self.activeMonitor else { return }
            self.onCriticalReset?()
        }
        return monitor
    }
}
