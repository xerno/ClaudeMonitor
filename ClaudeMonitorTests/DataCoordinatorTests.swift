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

        #expect(mockStatus.fetchCount == 1)
        #expect(mockUsage.fetchCount == 1)
    }

    @Test func refreshPassesCredentialsToUsageService() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, orgId) = coordinator(fixture: fixture)
        await coordinator.refresh()

        #expect(mockUsage.lastOrgId == orgId)
        #expect(mockUsage.lastCookie == "test-cookie")
    }

    @Test func refreshCallsOnUpdate() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()

        #expect(updateCount == 1)
    }

    @Test func refreshRecordsSchedulerSuccess() async throws {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        let monitor = try #require(coordinator.activeMonitor)
        #expect(coordinator.statusScheduler.statusState.lastSuccess != nil)
        #expect(monitor.scheduler.usageState.lastSuccess != nil)
        #expect(coordinator.statusScheduler.statusState.consecutiveFailures == 0)
        #expect(monitor.scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - Credentials

    @Test func refreshWithNoCredentialsSetsUsageError() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture, credentials: [:])
        await coordinator.refresh()

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

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func noCredentialsStillFetchesStatus() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture, credentials: [:])
        await coordinator.refresh()

        #expect(mockStatus.fetchCount == 1)
        #expect(coordinator.currentStatus == (try? mockStatus.result.get()))
    }

    @Test func hasCredentialsReturnsFalseWhenMissing() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture, credentials: [:])
        #expect(!coordinator.hasCredentials)
    }

    @Test func hasCredentialsReturnsTrueWhenPresent() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        #expect(coordinator.hasCredentials)
    }

    // MARK: - MonitorState

    @Test func monitorStateReflectsCurrentData() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

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
        let state = coordinator.monitorState

        #expect(!state.hasCredentials)
        #expect(state.usage.currentUsage == nil)
    }

    @Test func monitorStateReflectsPreferences() {
        let fixture = UsageHistoryTestFixture()
        let defaults = makeTestDefaults("monitor-state-prefs")
        let coordinator = DataCoordinator(
            statusService: mockStatus,
            usageService: mockUsage,
            systemIdleProvider: mockIdleProvider,
            pathMonitor: mockPath,
            profileStore: makeTestProfileStore(secrets: InMemorySecrets(), defaults: defaults),
            defaults: defaults,
            makeUsageHistory: { fixture.history }
        )

        #expect(coordinator.monitorState.showGraph)
        #expect(coordinator.monitorState.compactServices)

        defaults.set(false, forKey: Constants.Preferences.showUsageGraph)
        defaults.set(false, forKey: Constants.Preferences.compactServices)

        #expect(!coordinator.monitorState.showGraph)
        #expect(!coordinator.monitorState.compactServices)
    }

    // MARK: - Restart

    @Test func restartResetsScheduler() async throws {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        let monitor = try #require(coordinator.activeMonitor)
        #expect(monitor.scheduler.usageState.consecutiveFailures == 1)

        mockUsage.result = .success(TestFixtures.usage())
        coordinator.restartPolling()

        #expect(monitor.scheduler.usageState.consecutiveFailures == 0)
        #expect(monitor.scheduler.effectivePollingInterval == Constants.Polling.baseInterval)
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

        #expect(updateCount == 3)
    }

    // MARK: - Scheduler Adjustment

    @Test func schedulerIntervalAtLeastBaseAfterNormalUtilization() async throws {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        // testUsage has 42% and 18% utilization — projected well below 100%, so no urgency-driven
        // ramp-up. The interval must be >= baseInterval (never below it), but may exceed baseInterval
        // when the idle-cooldown path elevates it — hence >= rather than ==.
        let monitor = try #require(coordinator.activeMonitor)
        #expect(monitor.scheduler.effectivePollingInterval >= Constants.Polling.baseInterval)
        #expect(monitor.scheduler.isAwayMode == false)
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

        let analyses = coordinator.monitorState.usage.windowAnalyses
        #expect(!analyses.isEmpty)
        #expect(analyses.count == TestFixtures.usage().entries.count)
    }

    @Test func windowAnalysisEntriesMatchUsageEntries() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

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

    @Test func awayModeRemainsOffAfterRefreshWithNoData() async throws {
        // Sanity: even with idle time above threshold, refresh() with no analysis data must not set away mode.
        mockIdleProvider.idleTimeValue = Constants.Polling.awayThreshold + 1
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        let monitor = try #require(coordinator.activeMonitor)
        #expect(monitor.scheduler.isAwayMode == false)
    }

    // MARK: - Offline / Connectivity

    @Test func offlinePollSkipsNetwork() async throws {
        mockPath.simulate(satisfied: false)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        #expect(mockStatus.fetchCount == 0)
        #expect(mockUsage.fetchCount == 0)
        let monitor = try #require(coordinator.activeMonitor)
        #expect(coordinator.statusScheduler.statusState.consecutiveFailures == 1)
        #expect(monitor.scheduler.usageState.consecutiveFailures == 1)
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
        #expect(coordinator.monitorState.polling.lastFailedAt == nil)
    }

    // MARK: - Deallocation

    /// Proves the coordinator (and its per-account `AccountMonitor`) can actually be deallocated
    /// once polling is stopped and every other strong reference is dropped. Before the fix, the
    /// poll task's closure captured `self` strongly and the poll loop never returned except on
    /// cancellation, forming a `self -> pollTask -> closure -> self` cycle that kept the object
    /// (and its `usageHistory`) alive for the rest of the process, no matter what `deinit` did. A
    /// test that only asserts "the task was cancelled" would not catch that: the cycle keeps
    /// the object alive even after cancellation, since nothing ever drops the strong
    /// reference. Checking a `weak` reference actually goes `nil` is the only way to catch it.
    @Test func coordinatorDeallocatesAfterPollTaskCancelledAndReleased() async {
        let fixture = UsageHistoryTestFixture()
        weak var weakCoordinator: DataCoordinator?
        weak var weakMonitor: AccountMonitor?

        do {
            let (coordinator, _) = coordinator(fixture: fixture)
            coordinator.startPolling()
            weakCoordinator = coordinator
            weakMonitor = coordinator.activeMonitor

            // Let the poll task actually begin executing — i.e. wait until `refresh()` has been
            // entered and returned at least once — before stopping it and dropping the last
            // strong reference. Note this does NOT prove deallocation mid-`await`: `MockUsageService
            // .fetch` has no internal suspension point, so by the time `fetchCount` is observed
            // as non-zero, `await self.refresh()` inside the loop has already completed and `self`
            // is no longer in scope. What this proves is that real polling actually started (this
            // isn't cancelling a task before its first iteration ever ran) and that the weak
            // reference still nils out afterward — the regression this test guards against.
            for _ in 0..<20 where mockUsage.fetchCount == 0 {
                await Task.yield()
            }
            coordinator.stopPolling()
        }

        // Give the cancelled task's suspension points a chance to unwind so the weakly
        // captured `self` inside the poll loop is not itself the last thing keeping the
        // object alive.
        for _ in 0..<50 where weakCoordinator != nil || weakMonitor != nil {
            try? await Task.sleep(for: .milliseconds(10))
        }

        #expect(weakCoordinator == nil)
        #expect(weakMonitor == nil)
    }
}
