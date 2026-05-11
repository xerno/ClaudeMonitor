import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct DataCoordinatorTests {
    private let mockStatus = MockStatusService()
    private let mockUsage = MockUsageService()
    private let mockIdleProvider = MockSystemIdleProvider()
    private let mockPath = MockPathMonitor()

    private func coordinator(
        fixture: UsageHistoryTestFixture,
        testOrgId: String = UUID().uuidString,
        credentials: [String: String]? = nil
    ) -> (DataCoordinator, String) {
        makeCoordinator(
            fixture: fixture,
            status: mockStatus,
            usage: mockUsage,
            idle: mockIdleProvider,
            path: mockPath,
            testOrgId: testOrgId,
            credentials: credentials
        )
    }

    // MARK: - Successful Fetch

    @Test func refreshUpdatesStateOnSuccess() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.currentStatus == (try? mockStatus.result.get()))
        #expect(coordinator.currentUsage == (try? mockUsage.result.get()))
        #expect(coordinator.usageError == nil)
        #expect(coordinator.statusError == nil)
        #expect(coordinator.lastRefreshed != nil)
    }

    @Test func refreshCallsBothServices() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(mockStatus.fetchCount == 1)
        #expect(mockUsage.fetchCount == 1)
    }

    @Test func refreshPassesCredentialsToUsageService() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, orgId) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(mockUsage.lastOrgId == orgId)
        #expect(mockUsage.lastCookie == "test-cookie")
    }

    @Test func refreshCallsOnUpdate() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()
        await fixture.cleanup()

        #expect(updateCount == 1)
    }

    @Test func refreshRecordsSchedulerSuccess() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.scheduler.statusState.lastSuccess != nil)
        #expect(coordinator.scheduler.usageState.lastSuccess != nil)
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 0)
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - Credentials

    @Test func refreshWithNoCredentialsSetsUsageError() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture, credentials: [:])
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func refreshWithEmptyCredentialsSetsUsageError() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture, credentials: [
            Constants.Keychain.cookieString: "",
            Constants.Keychain.organizationId: "org",
        ])
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func noCredentialsStillFetchesStatus() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture, credentials: [:])
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(mockStatus.fetchCount == 1)
        #expect(coordinator.currentStatus == (try? mockStatus.result.get()))
    }

    @Test func hasCredentialsReturnsFalseWhenMissing() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture, credentials: [:])
        await fixture.cleanup()
        #expect(!coordinator.hasCredentials)
    }

    @Test func hasCredentialsReturnsTrueWhenPresent() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await fixture.cleanup()
        #expect(coordinator.hasCredentials)
    }

    // MARK: - MonitorState

    @Test func monitorStateReflectsCurrentData() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        let state = coordinator.monitorState
        #expect(state.usage.currentUsage == (try? mockUsage.result.get()))
        #expect(state.service.currentStatus == (try? mockStatus.result.get()))
        #expect(state.hasCredentials)
        #expect(state.usage.usageError == nil)
        #expect(state.service.statusError == nil)
        #expect(state.lastRefreshed != nil)
    }

    @Test func monitorStateWithNoCredentials() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture, credentials: [:])
        await fixture.cleanup()
        let state = coordinator.monitorState

        #expect(!state.hasCredentials)
        #expect(state.usage.currentUsage == nil)
    }

    // MARK: - Restart

    @Test func restartResetsScheduler() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 1)

        mockUsage.result = .success(TestFixtures.usage())
        coordinator.restartPolling()
        await fixture.cleanup()

        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
        #expect(coordinator.scheduler.effectivePollingInterval == Constants.Polling.baseInterval)
    }

    // MARK: - Multiple Refreshes

    @Test func onUpdateCalledOnEveryRefresh() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()
        await coordinator.refresh()
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(updateCount == 3)
    }

    // MARK: - Scheduler Adjustment

    @Test func schedulerIntervalAtLeastBaseAfterNormalUtilization() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        // testUsage has 42% and 18% utilization — projected well below 100%, so no urgency-driven
        // ramp-up. The interval must be >= baseInterval (never below it), but may exceed baseInterval
        // when the idle-cooldown path elevates it — hence >= rather than ==.
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
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        let analyses = coordinator.monitorState.usage.windowAnalyses
        #expect(!analyses.isEmpty)
        #expect(analyses.count == TestFixtures.usage().entries.count)
    }

    @Test func windowAnalysisEntriesMatchUsageEntries() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        let analyses = coordinator.monitorState.usage.windowAnalyses
        let analysisKeys = Set(analyses.map(\.entry.key))
        let usageKeys = Set((try? mockUsage.result.get())?.entries.map(\.key) ?? [])
        #expect(analysisKeys == usageKeys)
    }

    // MARK: - Away-Mode Propagation
    // Away mode activation requires both baseCooldown >= maxIdleInterval (driven by timeSinceLastChange)
    // AND systemIdleTime > awayThreshold. Testing activation end-to-end via refresh() is not feasible
    // here because mock services return no real analysis data (timeSinceLastChange is nil → baseCooldown
    // stays at baseInterval, never reaching maxIdleInterval). Scheduler-level activation is covered by
    // PollingRateTests.awayModeActivatesAtCooldownCapAndSystemIdle.

    @Test func awayModeRemainsOffAfterRefreshWithNoData() async {
        // Sanity: even with idle time above threshold, refresh() with no analysis data must not set away mode.
        mockIdleProvider.idleTimeValue = Constants.Polling.awayThreshold + 1
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.scheduler.isAwayMode == false)
    }

    // MARK: - Offline / Connectivity

    @Test func offlinePollSkipsNetwork() async {
        mockPath.simulate(satisfied: false)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(mockStatus.fetchCount == 0)
        #expect(mockUsage.fetchCount == 0)
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 1)
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 1)
    }

    @Test func returningOnlineResetsRetryState() {
        var scheduler = PollingScheduler()
        for _ in 0..<(Constants.Retry.failureThreshold + 1) {
            scheduler.recordStatusFailure(category: .transient)
            scheduler.recordUsageFailure(category: .transient)
        }
        #expect(scheduler.statusState.consecutiveFailures > 0)

        scheduler.resetRetryState()
        #expect(scheduler.statusState.consecutiveFailures == 0)
        #expect(scheduler.usageState.consecutiveFailures == 0)
    }

    @Test func warnThresholdDoesNotTriggerStale() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        for _ in 0..<Constants.Retry.warnThreshold {
            await coordinator.refresh()
        }
        await fixture.cleanup()

        #expect(coordinator.monitorState.polling.hasRecentFailure == true)
        #expect(coordinator.monitorState.polling.isAnyServiceStale == false)
    }

    @Test func failureThresholdTriggersStale() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        await fixture.cleanup()

        #expect(coordinator.monitorState.polling.isAnyServiceStale == true)
    }

    @Test func lastFailedAtTracking() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        #expect(coordinator.monitorState.polling.lastFailedAt != nil)

        mockUsage.result = .success(TestFixtures.usage())
        mockStatus.result = .success(TestFixtures.status())
        await coordinator.refresh()
        await fixture.cleanup()
        #expect(coordinator.monitorState.polling.lastFailedAt == nil)
    }
}
