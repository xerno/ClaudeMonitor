import AppKit
import Foundation

@MainActor
final class DataCoordinator {
    let statusService: any StatusFetching
    let usageService: any UsageFetching
    let systemIdleProvider: any SystemIdleProviding
    let pathMonitor: any PathMonitoring
    let loadCredential: @Sendable (String) -> String?
    var pollTask: Task<Void, Never>?
    var demoRotationIndex = 0
    var loadedCredentials: (cookie: String, orgId: String)?
    let usageHistory: UsageHistory
    var demoFrame: DemoData.DemoFrame?
    var lastFailedAt: Date?

    var currentStatus: StatusSummary?
    var currentUsage: UsageResponse?
    var usageError: String?
    var statusError: String?
    var lastRefreshed: Date?
    var nextPollDate: Date?
    var currentPollInterval: TimeInterval?
    var scheduler = PollingScheduler()
    var windowAnalyses: [WindowAnalysis] = []

    var onUpdate: (() -> Void)?
    var onCriticalReset: (() -> Void)?

    init(
        statusService: any StatusFetching = StatusService(),
        usageService: any UsageFetching = UsageService(),
        systemIdleProvider: any SystemIdleProviding = SystemIdleService(),
        pathMonitor: any PathMonitoring = PathMonitor(),
        loadCredential: @escaping @Sendable (String) -> String? = { EncryptedDefaultsService.load(key: $0) },
        usageHistory: UsageHistory = UsageHistory()
    ) {
        self.statusService = statusService
        self.usageService = usageService
        self.systemIdleProvider = systemIdleProvider
        self.pathMonitor = pathMonitor
        self.loadCredential = loadCredential
        self.usageHistory = usageHistory
        reloadCredentials()
        pathMonitor.setOnPathChange { [weak self] satisfied in
            guard let self, satisfied else { return }
            self.scheduler.resetRetryState()
            self.pollTask?.cancel()
            self.pollTask = Task { await self.pollLoop() }
        }
    }
}
