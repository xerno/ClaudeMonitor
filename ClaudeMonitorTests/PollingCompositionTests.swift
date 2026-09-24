import Testing
import Foundation
@testable import ClaudeMonitor

/// Composition tests that exercise the full chain from real WindowEntry data through
/// UsageHistory.analyze() into PollingScheduler.adjustPollingRate().
/// Focuses on paths not covered by PollIntervalTests or CompositionTests.
@MainActor struct PollingCompositionTests {

    // MARK: - Test 1: Cooldown via real UsageHistory.record() → samples() → analyze()

    /// Tests the full persistence path through UsageHistory:
    ///   record() accumulates samples → samples(for:) retrieves them → analyze() computes
    ///   timeSinceLastChange → adjustPollingRate() extends interval to idle cap.
    ///
    /// This differs from CompositionTests.testSchedulerCooldownFromRealAnalysis (which
    /// builds samples manually and calls analyze() directly) by exercising record()
    /// and samples(for:) as the data source — the path the coordinator actually uses.
    ///
    /// Setup: stable at 20% for 96 minutes via 96 record() calls spaced 60s apart.
    ///   timeSinceLastChange ≈ 95 * 60 = 5700s  (= cooldownEnd=5700s → t=1 → maxIdleInterval)
    @Test func cooldownViaUsageHistoryRecordAndSamplesPath() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 20, resetsAt: resetsAt)
        )

        // Record 96 samples spaced 60s apart, ending at `now`.
        // Earliest sample is 95 * 60 = 5700s before now, which equals cooldownEnd.
        // All at 20% → timeSinceLastChange = time since first sample ≈ 5700s.
        // record() deduplicates samples within deduplicationInterval (30s) with same utilization;
        // spacing 60s apart (> 30s) ensures every sample is stored.
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

        // All samples are at 20% → timeSinceLastChange = time since first sample ≈ 5700s.
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

    /// Same rationale as CompositionTests.testSchedulerCooldownMidRampIsStrictlyBetweenBounds,
    /// but exercises record()/samples(for:) as the data source (the path the coordinator
    /// actually uses), matching how cooldownViaUsageHistoryRecordAndSamplesPath complements
    /// CompositionTests.testSchedulerCooldownFromRealAnalysis above.
    @Test func cooldownMidRampViaUsageHistoryIsStrictlyBetweenBounds() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 20, resetsAt: resetsAt)
        )

        // Two samples, both at 20%, spanning exactly the ramp's midpoint (well beyond the
        // 30s dedup interval, so both are stored).
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

    // MARK: - Test 4: Credential swap clears windowAnalyses

    /// Tests that switching to a different organization ID clears the coordinator's
    /// windowAnalyses, preventing stale analyses from a previous org from leaking.
    ///
    /// Strategy: edit the active profile's organization in an isolated ProfileStore so we can
    /// simulate a credential swap inside restartPolling() without touching real Keychain.
    ///
    /// The path under test:
    ///   restartPolling() → reloadCredentials() → orgId changed →
    ///   usageHistory.switchOrganization(newOrgId) → windowAnalyses = []
    @Test func credentialSwapClearsWindowAnalyses() async throws {
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
            usageHistory: fixture.history
        )

        // Populate windowAnalyses by refreshing with real usage data.
        let resetsAt = Date().addingTimeInterval(9000)
        mockUsage.result = .success(UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 40, resetsAt: resetsAt)),
        ]))
        await coordinator.refresh()

        // Verify analyses are populated before the swap.
        #expect(!coordinator.windowAnalyses.isEmpty,
                "windowAnalyses must be non-empty after a successful refresh")

        // Swap to a different org ID and restart polling (which calls reloadCredentials()).
        try store.updateProfile(id: profile.id, name: "Acct", organizationId: orgBeta, cookie: "test-cookie")
        coordinator.restartPolling()

        // After restartPolling() with a different org ID, reloadCredentials() detects the
        // org change and calls usageHistory.switchOrganization(newOrgId) + windowAnalyses = [].
        // This check is synchronous (restartPolling is sync up to launching the Task).
        #expect(coordinator.windowAnalyses.isEmpty,
                "windowAnalyses must be cleared when org ID changes")

    }

    // MARK: - Test 5: UsageHistory.switchOrganization clears history and analyses

    /// Tests UsageHistory.switchOrganization() directly: verifies that switching org ID
    /// clears in-memory samples, preventing data from org-A bleeding into org-B analyses.
    ///
    /// Uses the fixture's tmpdir so no production paths are touched.
    @Test func switchOrganizationClearsHistoryAndProducesEmptyAnalysis() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history

        let orgA = "test-org-a-\(UUID().uuidString)"
        let orgB = "test-org-b-\(UUID().uuidString)"

        // Start on orgA and clear any stale state for it.
        history.switchOrganization(orgA)
        await history.clearAll()

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 55, resetsAt: resetsAt)
        )

        // Record 5 samples spaced 60s apart under orgA.
        for i in 0..<5 {
            history.record(entries: [entry], at: now.addingTimeInterval(TimeInterval(i * 60)))
        }
        let samplesBeforeSwitch = history.samples(for: entry)
        #expect(samplesBeforeSwitch.count == 5, "5 samples should be stored for orgA")

        // Switch to orgB — in-memory storage must be cleared immediately (disk is empty for orgB).
        history.switchOrganization(orgB)
        let samplesAfterSwitch = history.samples(for: entry)
        #expect(samplesAfterSwitch.isEmpty,
                "switching org must clear in-memory samples from previous org")

        // analyze() with zero samples should produce timeSinceLastChange = nil.
        let analysis = UsageHistory.analyze(entry: entry, samples: samplesAfterSwitch, now: now)
        #expect(analysis.timeSinceLastChange == nil,
                "no samples after org switch → timeSinceLastChange must be nil")

        // With no history a scheduler fed this analysis falls back to baseline.
        // 55% util, 3600s remaining on 18000s window:
        //   elapsed = 18000 - 3600 = 14400s, rate = 55/14400 ≈ 0.003819/s
        //   projected = 55 + 0.003819 * 3600 = 55 + 13.75 = 68.75%
        // projected < boldThreshold(80) → normal style, no cooldown → baseInterval.
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.effectivePollingInterval == Constants.Polling.baseInterval,
                "with no outpacing and no history, interval should be baseInterval=60s")

    }

    // MARK: - Test 6: cross-organisation data bleed when a fetch is in flight during an org switch

    /// Constructs the cross-organisation data bleed race: a usage fetch starts under org A,
    /// suspends mid-flight (via `MockUsageService.beforeReturn`), the test switches the live
    /// coordinator to org B while that fetch is still suspended, then releases the fetch so
    /// org A's stale response resumes and completes `refresh()`.
    ///
    /// `refreshUsage()` (`DataCoordinator+Refresh.swift`) captures `credentials.orgId` before
    /// the `await`, but performs no re-check of the *current* org after it resumes — it
    /// unconditionally sets `currentUsage = response` and returns `.fresh(response)`, which
    /// `refresh()` then unconditionally feeds into `usageHistory.record(...)`,
    /// `archiveMissingWindows`, and `save()`. `UsageHistory.storage`/`organizationId` are
    /// switched synchronously and eagerly by `switchOrganization` (`UsageHistory.swift`), so by
    /// the time org A's response resumes, `usageHistory` already belongs to org B — meaning a
    /// pass records org A's samples into org B's in-memory storage and persists them to org B's
    /// on-disk directory.
    ///
    /// If this test fails, it proves exactly that: a real, unguarded race where a stale
    /// cross-organisation usage response corrupts the newly-selected organization's stored
    /// history. `UsageHistory`'s own `generation` counter already guards `archiveWindow`
    /// against a suspended archive resurrecting stale data post-switch (see its doc comment)
    /// but `record()`/`refresh()`'s fresh-response path has no equivalent guard.
    @Test func staleFetchDuringOrgSwitchDoesNotBleedIntoNewOrganization() async throws {
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
            usageHistory: fixture.history
        )

        // Org A's response uses a distinctive utilization value (91%) unlikely to collide
        // with any other value used in this test.
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

        // Start org A's refresh() as a genuinely in-flight, unawaited Task.
        let refreshTask = Task { await coordinator.refresh() }

        // Wait until the fetch has actually started (and is suspended inside `beforeReturn`)
        // before switching organizations, so the switch provably lands mid-flight.
        await fetchStarted.wait()

        // Switch the live coordinator to org B while org A's fetch is still suspended, via the
        // production org-switch path (reloadCredentials(), called synchronously by
        // restartPolling()).
        try store.updateProfile(id: profile.id, name: "Acct", organizationId: orgB, cookie: "test-cookie")
        coordinator.restartPolling()
        // restartPolling() also spawns a new poll task; cancel it immediately so it doesn't
        // perform its own concurrent refresh() and confound this test's single controlled race.
        coordinator.pollTask?.cancel()

        #expect(coordinator.windowAnalyses.isEmpty,
                "switching org must clear windowAnalyses before org A's stale fetch resumes")

        // Release org A's suspended fetch and let refresh() run to completion.
        await releaseFetch.open()
        await refreshTask.value

        // Org A's stale utilization (91%) must never appear in org B's in-memory state.
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

        // Org B's UsageHistory (same in-memory `usageHistory`, now pointed at org B) must
        // contain none of org A's samples for this identity.
        let orgBSamples = fixture.history.samples(for: orgAEntry)
        let bleedIntoHistory = orgBSamples.contains { $0.utilization == 91 }
        #expect(!bleedIntoHistory,
                "org A's 91% sample must not be recorded into org B's UsageHistory storage")
    }
}
