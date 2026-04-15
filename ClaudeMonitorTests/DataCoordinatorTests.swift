import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct DataCoordinatorTests {
    private let mockStatus = MockStatusService()
    private let mockUsage = MockUsageService()
    private let mockIdleProvider = MockSystemIdleProvider()

    private func makeCoordinator(
        credentials: [String: String] = [
            Constants.Keychain.cookieString: "test-cookie",
            Constants.Keychain.organizationId: "test-org-id",
        ]
    ) -> DataCoordinator {
        DataCoordinator(
            statusService: mockStatus,
            usageService: mockUsage,
            systemIdleProvider: mockIdleProvider,
            loadCredential: { credentials[$0] }
        )
    }

    // MARK: - Successful Fetch

    @Test func refreshUpdatesStateOnSuccess() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(coordinator.currentStatus == testStatus)
        #expect(coordinator.currentUsage == testUsage)
        #expect(coordinator.usageError == nil)
        #expect(coordinator.statusError == nil)
        #expect(coordinator.lastRefreshed != nil)
    }

    @Test func refreshCallsBothServices() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(mockStatus.fetchCount == 1)
        #expect(mockUsage.fetchCount == 1)
    }

    @Test func refreshPassesCredentialsToUsageService() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(mockUsage.lastOrgId == "test-org-id")
        #expect(mockUsage.lastCookie == "test-cookie")
    }

    @Test func refreshCallsOnUpdate() async {
        let coordinator = makeCoordinator()
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()

        #expect(updateCount == 1)
    }

    @Test func refreshRecordsSchedulerSuccess() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(coordinator.scheduler.statusState.lastSuccess != nil)
        #expect(coordinator.scheduler.usageState.lastSuccess != nil)
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 0)
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - Credentials

    @Test func refreshWithNoCredentialsSetsUsageError() async {
        let coordinator = makeCoordinator(credentials: [:])
        await coordinator.refresh()

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func refreshWithEmptyCredentialsSetsUsageError() async {
        let coordinator = makeCoordinator(credentials: [
            Constants.Keychain.cookieString: "",
            Constants.Keychain.organizationId: "org",
        ])
        await coordinator.refresh()

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func noCredentialsStillFetchesStatus() async {
        let coordinator = makeCoordinator(credentials: [:])
        await coordinator.refresh()

        #expect(mockStatus.fetchCount == 1)
        #expect(coordinator.currentStatus == testStatus)
    }

    @Test func hasCredentialsReturnsFalseWhenMissing() {
        let coordinator = makeCoordinator(credentials: [:])
        #expect(!coordinator.hasCredentials)
    }

    @Test func hasCredentialsReturnsTrueWhenPresent() {
        let coordinator = makeCoordinator()
        #expect(coordinator.hasCredentials)
    }

    // MARK: - MonitorState

    @Test func monitorStateReflectsCurrentData() async {
        let coordinator = makeCoordinator()
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
        let coordinator = makeCoordinator(credentials: [:])
        let state = coordinator.monitorState

        #expect(!state.hasCredentials)
        #expect(state.currentUsage == nil)
    }

    // MARK: - Restart

    @Test func restartResetsScheduler() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()
        await coordinator.refresh()
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 1)

        mockUsage.result = .success(testUsage)
        coordinator.restartPolling()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - Multiple Refreshes

    @Test func onUpdateCalledOnEveryRefresh() async {
        let coordinator = makeCoordinator()
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()
        await coordinator.refresh()
        await coordinator.refresh()

        #expect(updateCount == 3)
    }

    // MARK: - Scheduler Adjustment

    @Test func schedulerNoRampUpAfterNormalUtilization() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        // testUsage has 42% and 18% utilization — projected well below 100%, so no ramp-up.
        // Interval must be at or above baseInterval (may be higher due to idle cooldown, never lower).
        #expect(coordinator.scheduler.effectivePollingInterval >= Constants.Polling.baseInterval)
        #expect(coordinator.scheduler.isAwayMode == false)
    }

    @Test func schedulerDecreasesIntervalAfterCriticalUtilization() async {
        // 50% utilization with 1000s elapsed of a 5-hour window (17000s remaining):
        //   rate = 50/1000 = 0.05%/s; projected = 50 + 0.05*17000 = 900% → well above 120% critical
        //   timeToLimit = (100-50)/0.05 = 1000s → above 600s threshold, so NOT approaching-limit
        // This guarantees the critical projection path (Priority 2) not the approaching-limit path.
        mockUsage.result = .success(UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(17000))),
        ]))
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        // Critical projection (≥120%) → interval = max(minInterval, baseInterval / 2) = 30s.
        let expected = max(Constants.Polling.minInterval, Constants.Polling.baseInterval / 2)
        #expect(coordinator.scheduler.effectivePollingInterval == expected)
        #expect(coordinator.scheduler.effectivePollingInterval < Constants.Polling.baseInterval)
    }

    // MARK: - WindowAnalyses

    @Test func windowAnalysesPopulatedAfterRefresh() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        let analyses = coordinator.monitorState.windowAnalyses
        #expect(!analyses.isEmpty)
        #expect(analyses.count == testUsage.entries.count)
    }

    @Test func windowAnalysisEntriesMatchUsageEntries() async {
        let coordinator = makeCoordinator()
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
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(coordinator.scheduler.isAwayMode == false)
    }
}
