import Testing
import Foundation
@testable import ClaudeMonitor

/// Composition tests that exercise the full chain from real WindowEntry data through
/// UsageHistory.analyze() into PollingScheduler.adjustPollingRate().
/// Focuses on paths not covered by PollIntervalTests or CompositionTests.
@MainActor struct PollingCompositionTests {

    // MARK: - Test 1: Approaching limit (Priority 1) — proportional interval

    /// Full chain: real WindowEntry + resetsAt → analyze() → timeToLimit < 600s →
    /// adjustPollingRate Priority 1 → effectivePollingInterval = timeToLimit / 5.
    ///
    /// Setup: 5h window (18000s), 98% utilization, resetsAt 400s away.
    ///   elapsed = 18000 - 400 = 17600s
    ///   rate    = 98 / 17600 ≈ 0.005568/s
    ///   ttl     = (100 - 98) / rate = 2 * 17600 / 98 ≈ 359s   (< 400s remaining ✓, < 600s ✓)
    ///   interval = max(minInterval=24, 359/5) ≈ 71.8s   (> baseInterval=60, proportional to ttl)
    @Test func realApproachingLimitYieldsProportionalInterval() throws {
        let now = Date()
        let resetsAt = now.addingTimeInterval(400)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 98, resetsAt: resetsAt)
        )

        // No samples needed — analyze() computes rate from utilization + resetsAt alone.
        let analysis = UsageHistory.analyze(entry: entry, samples: [], now: now)

        // Verify intermediate values before feeding to scheduler.
        // elapsed=17600, rate=98/17600, ttl=(2/rate)=~359s — inside the 600s Priority 1 window.
        #expect(analysis.timeToLimit != nil, "timeToLimit must be non-nil for 98% util on 400s horizon")
        let ttl = try #require(analysis.timeToLimit)
        #expect(ttl > 0 && ttl < 600, "timeToLimit \(ttl) must be in Priority 1 range (0, 600)")

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        // Priority 1 formula: max(minInterval, ttl / 5).
        let expected = max(Constants.Polling.minInterval, ttl / 5)
        #expect(scheduler.effectivePollingInterval == expected,
                "interval \(scheduler.effectivePollingInterval) should equal max(24, ttl/5)=\(expected)")

        // The interval is PROPORTIONAL to timeToLimit (varies with ttl, not a fixed constant).
        // With ttl ≈ 359s the result is ~71.8s, which is above baseInterval (60s).
        #expect(scheduler.effectivePollingInterval > Constants.Polling.baseInterval,
                "approaching-limit interval should be > baseInterval when ttl is moderate")
        #expect(scheduler.effectivePollingInterval < Constants.Polling.maxIdleInterval,
                "approaching-limit interval must not reach idle cap")
    }

    // MARK: - Test 2: Significantly outpacing (Priority 2) — half base interval

    /// Full chain: real WindowEntry with rapid utilization (50% at 20% elapsed) →
    /// analyze() → projectedAtReset ≈ 250% → Priority 2 → interval = max(24, 60/2) = 30s.
    ///
    /// Setup: 5h window (18000s), 50% utilization, resetsAt 14400s away (80% remaining).
    ///   elapsed    = 18000 - 14400 = 3600s   (20% of window elapsed)
    ///   rate       = 50 / 3600 ≈ 0.01389/s
    ///   projected  = 50 + 0.01389 * 14400 = 50 + 200 = 250%   (≥ criticalThreshold=120 ✓)
    ///   timeToLimit = (100-50)/rate = 3600s   (< 14400s remaining, so non-nil, but ≥ 600s)
    ///   → Priority 1 does NOT fire (ttl=3600 ≥ 600)
    ///   → Priority 2 fires: interval = max(24, 60/2) = 30s
    @Test func realSignificantlyOutpacingYieldsHalfBaseInterval() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(14400)  // 80% remaining on 18000s window
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 50, resetsAt: resetsAt)
        )

        let analysis = UsageHistory.analyze(entry: entry, samples: [], now: now)

        // Verify projection before feeding to scheduler.
        #expect(analysis.projectedAtReset >= Constants.Projection.criticalThreshold,
                "projected \(analysis.projectedAtReset) should be ≥ criticalThreshold=120")

        // timeToLimit should be non-nil (rate > 0, util < 100), but ≥ 600s (Priority 1 must NOT fire).
        let ttl = analysis.timeToLimit
        if let ttl {
            #expect(ttl >= 600,
                    "timeToLimit \(ttl) must be ≥ 600s so Priority 1 does not pre-empt Priority 2")
        }

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        let expected = max(Constants.Polling.minInterval, Constants.Polling.baseInterval / 2)
        #expect(scheduler.effectivePollingInterval == expected,
                "Priority 2 should set interval to max(24, 30)=\(expected)")
        #expect(scheduler.effectivePollingInterval < Constants.Polling.baseInterval,
                "Priority 2 interval must be below baseInterval")
    }

    // MARK: - Test 3: Cooldown via real UsageHistory.record() → samples() → analyze()

    /// Tests the full persistence path through UsageHistory:
    ///   record() accumulates samples → samples(for:) retrieves them → analyze() computes
    ///   timeSinceLastChange → adjustPollingRate() extends interval to idle cap.
    ///
    /// This differs from CompositionTests.testSchedulerCooldownFromRealAnalysis (which
    /// builds samples manually and calls analyze() directly) by exercising record()
    /// and samples(for:) as the data source — the path the coordinator actually uses.
    ///
    /// Setup: stable at 20% for 66 minutes via 67 record() calls spaced 60s apart.
    ///   timeSinceLastChange ≈ 66 * 60 = 3960s  (> cooldownEnd=3600s → t=1 → maxIdleInterval)
    @Test func cooldownViaUsageHistoryRecordAndSamplesPath() throws {
        let history = UsageHistory()

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 20, resetsAt: resetsAt)
        )

        // Record 67 samples spaced 60s apart, ending at `now`.
        // Earliest sample is 66 * 60 = 3960s before now.
        // All at 20% → timeSinceLastChange = time since first sample ≈ 3960s.
        let sampleCount = 67
        for i in 0..<sampleCount {
            let sampleTime = now.addingTimeInterval(TimeInterval(i - (sampleCount - 1)) * 60)
            // record() deduplicates samples within deduplicationInterval (30s) with same utilization.
            // Spacing them 60s apart (> 30s) ensures every sample is stored.
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

        // All samples are at 20% → timeSinceLastChange = time since first sample ≈ 3960s.
        #expect(analysis.timeSinceLastChange != nil, "timeSinceLastChange must be non-nil")
        let tslc = try #require(analysis.timeSinceLastChange)
        #expect(tslc >= Constants.Polling.cooldownEnd,
                "tslc \(tslc) must reach cooldownEnd=3600s for full idle cap")

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        #expect(scheduler.effectivePollingInterval == Constants.Polling.maxIdleInterval,
                "at full cooldown the interval should be capped at maxIdleInterval=300s")
        #expect(scheduler.effectivePollingInterval > Constants.Polling.baseInterval,
                "cooldown interval must exceed baseInterval=60s")

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
        defer {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            try? FileManager.default.removeItem(at: base.appendingPathComponent("ClaudeMonitor/usage/\(orgAlpha)"))
            try? FileManager.default.removeItem(at: base.appendingPathComponent("ClaudeMonitor/usage/\(orgBeta)"))
        }
        final class OrgIdBox: @unchecked Sendable { var value: String; init(_ v: String) { value = v } }
        let orgIdBox = OrgIdBox(orgAlpha)
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
            }
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
    }

    // MARK: - Test 5: UsageHistory.switchOrganization clears history and analyses

    /// Tests UsageHistory.switchOrganization() directly: verifies that switching org ID
    /// clears in-memory samples, preventing data from org-A bleeding into org-B analyses.
    ///
    /// Uses time-based unique org IDs to avoid cross-run disk pollution, and clears
    /// disk state before and after. switchOrganization() calls load() which reads from
    /// disk, so we must ensure no stale files exist for either org ID.
    @Test func switchOrganizationClearsHistoryAndProducesEmptyAnalysis() async {
        // Generate unique org IDs for this test run to prevent cross-run interference.
        // switchOrganization() calls load() which reads from disk, so org IDs must be fresh.
        let runId = Int(Date().timeIntervalSince1970)
        let orgA = "test-org-a-\(runId)"
        let orgB = "test-org-b-\(runId)"

        let history = UsageHistory()

        // Start on orgA and clear any stale disk state for it.
        history.switchOrganization(orgA)
        history.clearAll()
        try? await Task.sleep(for: .milliseconds(200))

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

        // Cleanup both orgs' disk state.
        history.clearAll()  // clears orgB
        history.switchOrganization(orgA)
        history.clearAll()  // clears orgA
        try? await Task.sleep(for: .milliseconds(200))
    }
}
