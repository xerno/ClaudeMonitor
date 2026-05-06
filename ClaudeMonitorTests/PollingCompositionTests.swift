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
    @Test func cooldownViaUsageHistoryRecordAndSamplesPath() throws {
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

        Task { await fixture.cleanup() }
    }

    // MARK: - Test 4: Credential swap clears windowAnalyses

    /// Tests that switching to a different organization ID clears the coordinator's
    /// windowAnalyses, preventing stale analyses from a previous org from leaking.
    ///
    /// Strategy: use a mutable-credentials closure so we can simulate a credential
    /// swap inside restartPolling() without touching real Keychain.
    ///
    /// The path under test:
    ///   restartPolling() → reloadCredentials() → orgId changed →
    ///   usageHistory.switchOrganization(newOrgId) → windowAnalyses = []
    @Test func credentialSwapClearsWindowAnalyses() async {
        let mockStatus = MockStatusService()
        let mockUsage = MockUsageService()
        let mockIdleProvider = MockSystemIdleProvider()

        // Credentials are read via a @Sendable closure — use a class wrapper so we can
        // mutate the orgId from the test body without a Sendable capture violation.
        let orgAlpha = "org-alpha-\(UUID().uuidString)"
        let orgBeta = "org-beta-\(UUID().uuidString)"
        final class OrgIdBox: @unchecked Sendable { var value: String; init(_ v: String) { value = v } }
        let orgIdBox = OrgIdBox(orgAlpha)
        let fixture = UsageHistoryTestFixture()
        let coordinator = DataCoordinator(
            statusService: mockStatus,
            usageService: mockUsage,
            systemIdleProvider: mockIdleProvider,
            loadCredential: { key in
                switch key {
                case Constants.Keychain.cookieString: return "test-cookie"
                case Constants.Keychain.organizationId: return orgIdBox.value
                default: return nil
                }
            },
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
        orgIdBox.value = orgBeta
        coordinator.restartPolling()

        // After restartPolling() with a different org ID, reloadCredentials() detects the
        // org change and calls usageHistory.switchOrganization(newOrgId) + windowAnalyses = [].
        // This check is synchronous (restartPolling is sync up to launching the Task).
        #expect(coordinator.windowAnalyses.isEmpty,
                "windowAnalyses must be cleared when org ID changes")

        await fixture.cleanup()
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

        await fixture.cleanup()
    }
}
