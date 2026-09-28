import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct PollingCompositionTests {

    // MARK: - Test 1: Cooldown via real UsageHistory.record() → samples() → analyze()

    @Test func cooldownViaUsageHistoryRecordAndSamplesPath() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 20, resetsAt: resetsAt)
        )

        // 60s spacing clears the 30s dedup interval; 95 gaps span exactly cooldownEnd (5700s).
        let sampleCount = 96
        for i in 0..<sampleCount {
            let sampleTime = now.addingTimeInterval(TimeInterval(i - (sampleCount - 1)) * 60)
            history.record(entries: [
                WindowEntry(
                    key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                    window: UsageWindow(utilization: 20, resetsAt: resetsAt)
                )
            ], at: sampleTime)
        }

        let samples = history.samples(for: entry)
        #expect(samples.count == sampleCount, "all \(sampleCount) samples should be stored")

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.timeSinceLastChange != nil, "timeSinceLastChange must be non-nil")
        let tslc = try #require(analysis.timeSinceLastChange)
        #expect(tslc >= Constants.Polling.cooldownEnd,
                "tslc \(tslc) must reach cooldownEnd=\(Constants.Polling.cooldownEnd)s for full idle cap")

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        #expect(scheduler.effectivePollingInterval == Constants.Polling.maxIdleInterval,
                "at full cooldown the interval should be capped at maxIdleInterval=300s")
        #expect(scheduler.effectivePollingInterval > Constants.Polling.baseInterval,
                "cooldown interval must exceed baseInterval=60s")

    }

    // MARK: - Test 1b: Cooldown mid-ramp via UsageHistory.record()/samples() is strictly between bounds

    @Test func cooldownMidRampViaUsageHistoryIsStrictlyBetweenBounds() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 20, resetsAt: resetsAt)
        )

        let midRampTslc = (Constants.Polling.cooldownStart + Constants.Polling.cooldownEnd) / 2
        history.record(entries: [entry], at: now.addingTimeInterval(-midRampTslc))
        history.record(entries: [entry], at: now)

        let samples = history.samples(for: entry)
        #expect(samples.count == 2, "both samples should be stored")

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)
        let tslc = try #require(analysis.timeSinceLastChange)
        #expect(tslc > Constants.Polling.cooldownStart)
        #expect(tslc < Constants.Polling.cooldownEnd)

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        #expect(scheduler.effectivePollingInterval > Constants.Polling.baseInterval,
                "mid-ramp interval must be strictly greater than the pre-cooldown baseInterval")
        #expect(scheduler.effectivePollingInterval < Constants.Polling.maxIdleInterval,
                "mid-ramp interval must be strictly less than the fully-idle cap")
    }

    // MARK: - Test 4: Org change on the same profile drops the old monitor and starts a fresh one

    @Test func orgChangeOnSameProfileStartsAFreshEmptyMonitor() async throws {
        let mockStatus = MockStatusService()
        let mockUsage = MockUsageService()
        let mockIdleProvider = MockSystemIdleProvider()

        let orgAlpha = "org-alpha-\(UUID().uuidString)"
        let orgBeta = "org-beta-\(UUID().uuidString)"
        let defaults = makeTestDefaults("polling-composition")
        let store = makeTestProfileStore(secrets: InMemorySecrets(), defaults: defaults)
        let profile = try store.addProfile(name: "Acct", organizationId: orgAlpha, cookie: "test-cookie")
        store.setActive(id: profile.id)
        let fixture = UsageHistoryTestFixture()
        let coordinator = DataCoordinator(
            statusService: mockStatus,
            usageService: mockUsage,
            systemIdleProvider: mockIdleProvider,
            profileStore: store,
            defaults: defaults,
            makeUsageHistory: { UsageHistory(baseDirectory: fixture.baseDirectory) }
        )
        let monitorAlpha = try #require(coordinator.activeMonitor)

        let resetsAt = Date().addingTimeInterval(9000)
        mockUsage.result = .success(UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 40, resetsAt: resetsAt)),
        ]))
        await coordinator.refresh()

        #expect(!coordinator.windowAnalyses.isEmpty,
                "windowAnalyses must be non-empty after a successful refresh")

        // restartPolling() reconciles monitors: orgAlpha's is dropped and a fresh one built for orgBeta.
        try store.updateProfile(id: profile.id, name: "Acct", organizationId: orgBeta, cookie: "test-cookie")
        coordinator.restartPolling()
        coordinator.stopPolling()

        #expect(coordinator.windowAnalyses.isEmpty,
                "windowAnalyses must be empty on the fresh monitor for the new org")
        let monitorBeta = try #require(coordinator.activeMonitor)
        #expect(monitorBeta !== monitorAlpha)
    }

    // MARK: - Test 5: UsageHistory.switchOrganization clears history and analyses

    @Test func switchOrganizationClearsHistoryAndProducesEmptyAnalysis() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history

        let orgA = "test-org-a-\(UUID().uuidString)"
        let orgB = "test-org-b-\(UUID().uuidString)"

        history.switchOrganization(orgA)
        await history.clearAll()

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 55, resetsAt: resetsAt)
        )

        for i in 0..<5 {
            history.record(entries: [entry], at: now.addingTimeInterval(TimeInterval(i * 60)))
        }
        let samplesBeforeSwitch = history.samples(for: entry)
        #expect(samplesBeforeSwitch.count == 5, "5 samples should be stored for orgA")

        history.switchOrganization(orgB)
        let samplesAfterSwitch = history.samples(for: entry)
        #expect(samplesAfterSwitch.isEmpty,
                "switching org must clear in-memory samples from previous org")

        let analysis = UsageHistory.analyze(entry: entry, samples: samplesAfterSwitch, now: now)
        #expect(analysis.timeSinceLastChange == nil,
                "no samples after org switch → timeSinceLastChange must be nil")

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.effectivePollingInterval == Constants.Polling.baseInterval,
                "with no outpacing and no history, interval should be baseInterval=60s")

    }

    // MARK: - Test 6: an in-flight fetch under the old org lands only in its own (dropped) monitor

    /// A fetch in flight under org A while the profile switches to org B lands only in A's orphaned
    /// monitor and history, never in B's monitor, history or the coordinator's facades.
    /// A's generation guard still passes: the switch never touches A's `UsageHistory`.
    @Test func staleFetchDuringOrgChangeLandsOnlyInTheOldMonitorNeverTheNewOne() async throws {
        let mockStatus = MockStatusService()
        let mockUsage = MockUsageService()
        let mockIdleProvider = MockSystemIdleProvider()

        let orgA = "org-a-\(UUID().uuidString)"
        let orgB = "org-b-\(UUID().uuidString)"
        let defaults = makeTestDefaults("polling-composition")
        let store = makeTestProfileStore(secrets: InMemorySecrets(), defaults: defaults)
        let profile = try store.addProfile(name: "Acct", organizationId: orgA, cookie: "test-cookie")
        store.setActive(id: profile.id)
        let fixture = UsageHistoryTestFixture()
        let coordinator = DataCoordinator(
            statusService: mockStatus,
            usageService: mockUsage,
            systemIdleProvider: mockIdleProvider,
            profileStore: store,
            defaults: defaults,
            makeUsageHistory: { UsageHistory(baseDirectory: fixture.baseDirectory) }
        )
        let monitorA = try #require(coordinator.activeMonitor)

        let orgAResetsAt = Date().addingTimeInterval(3600)
        let orgAEntry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 91, resetsAt: orgAResetsAt)
        )
        mockUsage.result = .success(UsageResponse(entries: [orgAEntry]))

        let fetchStarted = Gate()
        let releaseFetch = Gate()
        mockUsage.beforeReturn = {
            await fetchStarted.open()
            await releaseFetch.wait()
        }

        let refreshTask = Task { await coordinator.refresh() }

        await fetchStarted.wait()

        // restartPolling() reconciles monitors synchronously, dropping org A's while its fetch is suspended.
        try store.updateProfile(id: profile.id, name: "Acct", organizationId: orgB, cookie: "test-cookie")
        coordinator.restartPolling()
        // The poll loops it spawns would run their own refresh() and confound the single controlled race.
        coordinator.stopPolling()

        #expect(coordinator.windowAnalyses.isEmpty,
                "org B's fresh monitor must start empty before org A's stale fetch resumes")

        await releaseFetch.open()
        await refreshTask.value

        let orgAIdentity = orgAEntry.storageIdentity
        let bleedIntoCurrentUsage = coordinator.currentUsage?.entries.contains {
            $0.storageIdentity == orgAIdentity && $0.window.utilization == 91
        } ?? false
        #expect(!bleedIntoCurrentUsage,
                "org A's 91% utilization must not appear in currentUsage after switching to org B")

        let bleedIntoAnalyses = coordinator.windowAnalyses.contains {
            $0.entry.storageIdentity == orgAIdentity && $0.entry.window.utilization == 91
        }
        #expect(!bleedIntoAnalyses,
                "org A's 91% utilization must not appear in windowAnalyses after switching to org B")

        let monitorB = try #require(coordinator.activeMonitor)
        #expect(monitorB !== monitorA)
        let orgBSamples = monitorB.usageHistory.samples(for: orgAEntry)
        let bleedIntoHistory = orgBSamples.contains { $0.utilization == 91 }
        #expect(!bleedIntoHistory,
                "org A's 91% sample must not be recorded into org B's UsageHistory storage")

        #expect(monitorA.usageHistory.samples(for: orgAEntry).contains { $0.utilization == 91 },
                "org A's own monitor legitimately records its own in-flight response")
    }
}
