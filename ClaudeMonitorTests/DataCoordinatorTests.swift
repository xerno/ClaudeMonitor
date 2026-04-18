import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct DataCoordinatorTests {
    private let mockStatus = MockStatusService()
    private let mockUsage = MockUsageService()
    private let mockIdleProvider = MockSystemIdleProvider()

    private func makeCoordinator(
        testOrgId: String = UUID().uuidString,
        credentials: [String: String]? = nil
    ) -> (DataCoordinator, String) {
        let resolvedCredentials = credentials ?? [
            Constants.Keychain.cookieString: "test-cookie",
            Constants.Keychain.organizationId: testOrgId,
        ]
        let coordinator = DataCoordinator(
            statusService: mockStatus,
            usageService: mockUsage,
            systemIdleProvider: mockIdleProvider,
            loadCredential: { resolvedCredentials[$0] }
        )
        return (coordinator, testOrgId)
    }

    private func cleanupTestOrg(_ orgId: String) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let orgDir = appSupport.appendingPathComponent("ClaudeMonitor/usage/\(orgId)")
        try? FileManager.default.removeItem(at: orgDir)
    }

    // MARK: - Successful Fetch

    @Test func refreshUpdatesStateOnSuccess() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        #expect(coordinator.currentStatus == testStatus)
        #expect(coordinator.currentUsage == testUsage)
        #expect(coordinator.usageError == nil)
        #expect(coordinator.statusError == nil)
        #expect(coordinator.lastRefreshed != nil)
    }

    @Test func refreshCallsBothServices() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        #expect(mockStatus.fetchCount == 1)
        #expect(mockUsage.fetchCount == 1)
    }

    @Test func refreshPassesCredentialsToUsageService() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        #expect(mockUsage.lastOrgId == orgId)
        #expect(mockUsage.lastCookie == "test-cookie")
    }

    @Test func refreshCallsOnUpdate() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()

        #expect(updateCount == 1)
    }

    @Test func refreshRecordsSchedulerSuccess() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        #expect(coordinator.scheduler.statusState.lastSuccess != nil)
        #expect(coordinator.scheduler.usageState.lastSuccess != nil)
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 0)
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - Credentials

    @Test func refreshWithNoCredentialsSetsUsageError() async {
        let (coordinator, _) = makeCoordinator(credentials: [:])
        await coordinator.refresh()

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func refreshWithEmptyCredentialsSetsUsageError() async {
        let (coordinator, orgId) = makeCoordinator(credentials: [
            Constants.Keychain.cookieString: "",
            Constants.Keychain.organizationId: "org",
        ])
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func noCredentialsStillFetchesStatus() async {
        let (coordinator, _) = makeCoordinator(credentials: [:])
        await coordinator.refresh()

        #expect(mockStatus.fetchCount == 1)
        #expect(coordinator.currentStatus == testStatus)
    }

    @Test func hasCredentialsReturnsFalseWhenMissing() {
        let (coordinator, _) = makeCoordinator(credentials: [:])
        #expect(!coordinator.hasCredentials)
    }

    @Test func hasCredentialsReturnsTrueWhenPresent() {
        let (coordinator, _) = makeCoordinator()
        #expect(coordinator.hasCredentials)
    }

    // MARK: - MonitorState

    @Test func monitorStateReflectsCurrentData() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        let state = coordinator.monitorState
        #expect(state.currentUsage == testUsage)
        #expect(state.currentStatus == testStatus)
        #expect(state.hasCredentials)
        #expect(state.usageError == nil)
        #expect(state.statusError == nil)
        #expect(state.lastRefreshed != nil)
    }

    @Test func monitorStateWithNoCredentials() {
        let (coordinator, _) = makeCoordinator(credentials: [:])
        let state = coordinator.monitorState

        #expect(!state.hasCredentials)
        #expect(state.currentUsage == nil)
    }

    // MARK: - Restart

    @Test func restartResetsScheduler() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 1)

        mockUsage.result = .success(testUsage)
        coordinator.restartPolling()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - Multiple Refreshes

    @Test func onUpdateCalledOnEveryRefresh() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()
        await coordinator.refresh()
        await coordinator.refresh()

        #expect(updateCount == 3)
    }

    // MARK: - Scheduler Adjustment

    @Test func schedulerNoRampUpAfterNormalUtilization() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        // testUsage has 42% and 18% utilization — projected well below 100%, so no ramp-up.
        // Interval must be at or above baseInterval (may be higher due to idle cooldown, never lower).
        #expect(coordinator.scheduler.effectivePollingInterval >= Constants.Polling.baseInterval)
        #expect(coordinator.scheduler.isAwayMode == false)
    }

    @Test func schedulerUsesRateDrivenIntervalWhenRecentRateIsHigh() {
        // Rate-driven interval: pollInterval = resolutionPerPoll / (recentRate * activityFactor).
        // With activityFactor=1 (tslc=nil → no decay), a recentRate > 1/60 %/s drives the
        // interval below baseInterval=60s. With recentRate=0.05 %/s: desired = 1.0/0.05 = 20s,
        // clamped to max(minInterval=24, 20) = 24s.
        //
        // Samples: two samples 60s apart, utilization rises from 10% to 13%
        //   instantaneous = (13-10)/60 = 0.05%/s → EMA = 0.05 (first step, no prior EMA)
        let now = Date()
        let t0 = now.addingTimeInterval(-60)
        let samples = [
            UtilizationSample(utilization: 10, timestamp: t0),
            UtilizationSample(utilization: 13, timestamp: now),
        ]
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 13, resetsAt: now.addingTimeInterval(9000))
        )

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)
        #expect(analysis.recentRate != nil, "two samples with a 60s gap must produce a recentRate")

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        // rate-driven desired = 1.0 / recentRate; clamped to [minInterval, baseInterval].
        // With recentRate ≈ 0.05: desired ≈ 20s → clamped to minInterval=24s.
        #expect(scheduler.effectivePollingInterval < Constants.Polling.baseInterval,
                "high recentRate must drive interval below baseInterval")
        #expect(scheduler.effectivePollingInterval >= Constants.Polling.minInterval,
                "interval must never drop below minInterval")
    }

    // MARK: - WindowAnalyses

    @Test func windowAnalysesPopulatedAfterRefresh() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        let analyses = coordinator.monitorState.windowAnalyses
        #expect(!analyses.isEmpty)
        #expect(analyses.count == testUsage.entries.count)
    }

    @Test func windowAnalysisEntriesMatchUsageEntries() async {
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        let analyses = coordinator.monitorState.windowAnalyses
        let analysisKeys = Set(analyses.map(\.entry.key))
        let usageKeys = Set(testUsage.entries.map(\.key))
        #expect(analysisKeys == usageKeys)
    }

    // MARK: - Away-Mode Propagation

    @Test func awayModeOffWhenIdleBelowThreshold() async {
        // Idle time below the away threshold: away mode must be off regardless.
        mockIdleProvider.idleTimeValue = Constants.Polling.awayThreshold - 1
        let (coordinator, orgId) = makeCoordinator()
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        #expect(coordinator.scheduler.isAwayMode == false)
    }
}
