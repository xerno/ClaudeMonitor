import Testing
import Foundation
@testable import ClaudeMonitor

/// JSON-decoded input pipeline tests: verify the full path from raw JSON strings through
/// JSONDecoder + WindowKeyParser into DataCoordinator, UsageHistory, and MonitorState.
/// These catch bugs that only surface when real decoding is in the path — e.g., wrong duration
/// constants, parser regressions, or divergence between analyze() and usageStyle() code paths.
/// Contrast with CompositionTests, which uses hand-crafted UsageResponse values and focuses
/// on coordinator wiring (MonitorState, scheduler, callbacks, org switching).
@MainActor struct CoordinatorCompositionTests {

    // MARK: - Helpers

    private var testUsage: UsageResponse {
        UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(9000))),
        ])
    }

    // MARK: - Test 1: JSON decode → coordinator pipeline

    /// Full pipeline: JSON string → UsageResponse decoder → WindowKeyParser → WindowEntry.duration →
    /// DataCoordinator.refresh() → monitorState.windowAnalyses.
    ///
    /// Catches bugs where a hand-crafted WindowEntry bypasses parsing (e.g., wrong duration constant).
    @Test func jsonDecodeFlowsThroughCoordinatorWithCorrectDuration() async throws {
        let resetsAt = Date().addingTimeInterval(9000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetsAtString = formatter.string(from: resetsAt)

        let json = """
        {"five_hour": {"utilization": 42, "resets_at": "\(resetsAtString)"}}
        """

        // Decode through the real pipeline — same path as live network responses.
        let decoded = try JSONDecoder.iso8601WithFractionalSeconds.decode(
            UsageResponse.self, from: Data(json.utf8)
        )

        // WindowKeyParser must produce 18000s for "five_hour".
        #expect(decoded.entries.count == 1)
        #expect(decoded.entries[0].key == "five_hour")
        #expect(decoded.entries[0].duration == 18000)
        #expect(decoded.entries[0].window.utilization == 42)

        // Feed the decoded response through DataCoordinator.
        let mockUsage = MockUsageService()
        mockUsage.result = .success(decoded)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = makeCoordinator(fixture: fixture, usage: mockUsage)
        await coordinator.refresh()

        // The coordinator's windowAnalyses must carry the same duration that came from the parser.
        let analyses = coordinator.monitorState.usage.windowAnalyses
        #expect(analyses.count == 1)
        #expect(analyses[0].entry.duration == 18000)
        #expect(analyses[0].entry.key == "five_hour")
        #expect(analyses[0].entry.window.utilization == 42)
    }

    // MARK: - Test 2: onCriticalReset callback wiring via coordinator

    /// Tests that onCriticalReset is called by the coordinator when detectCriticalReset fires.
    ///
    /// Sequence:
    ///   Refresh 1 — critical utilization + resetsAt in the future (triggers critical projection).
    ///   Refresh 2 — same key, resetsAt advanced by a full window duration (reset detected), low utilization.
    ///
    /// Verifies the callback is called exactly once and the wiring from detectCriticalReset → onCriticalReset
    /// is intact end-to-end through the coordinator (not just through the Formatting function alone).
    @Test func onCriticalResetCallbackFiredExactlyOnceAfterReset() async {
        let duration: TimeInterval = 18000
        let now = Date()

        // Refresh 1: critical projection — 65% util, 50% remaining → projected ≈ 130%.
        let prevResetsAt = now.addingTimeInterval(9000)
        let firstResponse = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 65, resetsAt: prevResetsAt))
        ])

        // Refresh 2: same key, resetsAt advanced by full window duration → detectCriticalReset returns true.
        let nextResetsAt = prevResetsAt.addingTimeInterval(duration)
        let secondResponse = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 3, resetsAt: nextResetsAt))
        ])

        // MockUsageService that serves different responses per call.
        final class SequencedMockUsage: UsageFetching, @unchecked Sendable {
            private var responses: [UsageResponse]
            private var index = 0
            init(responses: [UsageResponse]) { self.responses = responses }
            func fetch(organizationId: String, cookieString: String) async throws -> UsageResponse {
                let r = responses[min(index, responses.count - 1)]
                index += 1
                return r
            }
        }

        let sequencedUsage = SequencedMockUsage(responses: [firstResponse, secondResponse])
        var criticalResetCount = 0
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = makeCoordinator(fixture: fixture, usage: sequencedUsage)
        coordinator.onCriticalReset = { criticalResetCount += 1 }

        await coordinator.refresh(now: now) // Refresh 1: establishes critical baseline, no previous usage.
        #expect(criticalResetCount == 0, "No reset on first refresh — no previous usage to compare against.")

        // Refresh 2 must run at a `now` past prevResetsAt for the resets_at jump to be a
        // genuine boundary (not drift on a window that hasn't ended yet).
        let refresh2Now = prevResetsAt.addingTimeInterval(10)
        await coordinator.refresh(now: refresh2Now) // Refresh 2: detects reset from critical state.
        #expect(criticalResetCount == 1, "onCriticalReset must fire exactly once when reset is detected.")

        await coordinator.refresh(now: refresh2Now.addingTimeInterval(1)) // Refresh 3: same resetsAt, no new reset.
        #expect(criticalResetCount == 1, "onCriticalReset must not fire again when no new reset occurred.")

    }

    // MARK: - Test 2b: Task 5 regression — a 90s resets_at nudge must not fire a critical reset

    /// The previous (defective) implementation used the 60s `resetBoundaryTolerance` to
    /// decide whether a critical reset fired, so a 90s server-side nudge (comfortably inside
    /// the old duration-derived 9000s band, but just above the 60s tolerance) spuriously
    /// fired the user-visible critical-reset sound/animation. This band had zero coverage
    /// before this fix — that is why the regression escaped review.
    @Test func ninetySecondResetsAtNudgeDoesNotFireCriticalReset() async {
        let duration: TimeInterval = 18000
        let now = Date()

        // Critical baseline: 65% used, 50% remaining → projected ≈ 130%.
        let prevResetsAt = now.addingTimeInterval(9000)
        let firstResponse = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 65, resetsAt: prevResetsAt))
        ])
        // A 90s forward nudge — not a genuine boundary: the old window (prevResetsAt) has
        // not actually arrived yet at the time of this poll.
        let nudgedResetsAt = prevResetsAt.addingTimeInterval(90)
        let secondResponse = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 66, resetsAt: nudgedResetsAt))
        ])

        final class SequencedMockUsage: UsageFetching, @unchecked Sendable {
            private var responses: [UsageResponse]
            private var index = 0
            init(responses: [UsageResponse]) { self.responses = responses }
            func fetch(organizationId: String, cookieString: String) async throws -> UsageResponse {
                let r = responses[min(index, responses.count - 1)]
                index += 1
                return r
            }
        }

        let sequencedUsage = SequencedMockUsage(responses: [firstResponse, secondResponse])
        var criticalResetCount = 0
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = makeCoordinator(fixture: fixture, usage: sequencedUsage)
        coordinator.onCriticalReset = { criticalResetCount += 1 }

        await coordinator.refresh(now: now)
        await coordinator.refresh(now: now.addingTimeInterval(60)) // well before prevResetsAt

        #expect(criticalResetCount == 0, "A 90s resets_at nudge that isn't a genuine boundary must never fire the critical reset.")
    }

    // MARK: - Test 3: Style equivalence between analyze() and inline usageStyle()

    /// Verifies that UsageHistory.analyze() and Formatting.usageStyle() produce identical styles
    /// at the same boundary utilization values. Any divergence indicates the two code paths have drifted.
    ///
    /// analyze() calls usageStyle(projectedAtReset:utilization:resetsAt:timeRemaining:).
    /// The original-signature usageStyle(utilization:resetsAt:windowDuration:) recomputes projection internally.
    /// Both must agree at every threshold boundary.
    @Test func analyzeAndUsageStyleProduceEquivalentStylesAtBoundaries() {
        let now = Date()
        let duration: TimeInterval = 18000
        // 50% elapsed (9000s passed), 50% remaining (9000s left).
        let resetsAt = now.addingTimeInterval(9000)

        // Boundary utilization values that straddle each threshold.
        // With 9000s elapsed and 9000s remaining: projected = util + util*(9000/9000) = util*2.
        //   util=40  → projected=80  (bold threshold ≥ 80%)
        //   util=50  → projected=100 (warning threshold ≥ 100%)
        //   util=60  → projected=120 (critical threshold ≥ 120%)
        // Also test direct-block case (util ≥ 100).
        let utilizations = [39, 40, 49, 50, 59, 60, 99, 100]

        for util in utilizations {
            let entry = WindowEntry(
                key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                window: UsageWindow(utilization: util, resetsAt: resetsAt)
            )

            // Path A: original-signature usageStyle() computes projection internally.
            let styleA = Formatting.usageStyle(
                utilization: util,
                resetsAt: resetsAt,
                windowDuration: duration,
                now: now
            )

            // Path B: analyze() computes projection then calls the pre-computed overload.
            let analysis = UsageHistory.analyze(entry: entry, samples: [], now: now)
            let styleB = analysis.style

            #expect(styleA == styleB,
                    "Style mismatch at utilization=\(util): usageStyle()=\(styleA), analyze().style=\(styleB)")
        }
    }

    // MARK: - Test 4: Multi-entry reset isolates only the affected key

    /// Verifies that detectAndHandleReset for one key does not clear samples for a different key.
    @Test func detectAndHandleResetDoesNotAffectOtherKeys() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history

        let now = Date()
        let fiveHourResetsAt = now.addingTimeInterval(9000)
        let sevenDayResetsAt = now.addingTimeInterval(302_400) // 3.5 days remaining

        let fiveHourEntry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 40, resetsAt: fiveHourResetsAt)
        )
        let sevenDayEntry = WindowEntry(
            key: "seven_day", duration: 604_800, durationLabel: "7d", modelScope: nil,
            window: UsageWindow(utilization: 20, resetsAt: sevenDayResetsAt)
        )

        // Record samples for both keys.
        history.record(entries: [fiveHourEntry, sevenDayEntry], at: now.addingTimeInterval(-300))
        history.record(entries: [fiveHourEntry, sevenDayEntry], at: now)

        // Both keys must have samples before the reset.
        #expect(!history.samples(for: fiveHourEntry).isEmpty)
        #expect(!history.samples(for: sevenDayEntry).isEmpty)

        // Simulate a reset for five_hour only — advance its resetsAt by more than duration/2,
        // and pass `at:` past fiveHourResetsAt so this is a genuine boundary, not drift.
        let newFiveHourResetsAt = fiveHourResetsAt.addingTimeInterval(18000)
        await history.detectAndHandleReset(
            entry: fiveHourEntry,
            newResetsAt: newFiveHourResetsAt,
            at: fiveHourResetsAt.addingTimeInterval(10)
        )

        // five_hour samples are cleared by archiveWindow() (called inside detectAndHandleReset).
        #expect(history.samples(for: fiveHourEntry).isEmpty,
                "five_hour samples must be cleared after its reset")

        // seven_day samples must be completely unaffected.
        #expect(!history.samples(for: sevenDayEntry).isEmpty,
                "seven_day samples must not be affected by the five_hour reset")

    }

    // MARK: - Test 5: reloadCredentials org switch clears state

    /// Verifies that switching to a different org ID via reloadCredentials:
    ///   - clears windowAnalyses
    ///   - switches the history to the new org (samples from the old org are gone)
    ///
    /// Edits the active profile's organization in an isolated ProfileStore to simulate the
    /// credential change.
    @Test func reloadCredentialsWithNewOrgClearsWindowAnalyses() async throws {
        let orgA = "test-org-a-\(UUID().uuidString)"
        let orgB = "test-org-b-\(UUID().uuidString)"

        let defaults = makeTestDefaults("coord-composition")
        let store = makeTestProfileStore(secrets: InMemorySecrets(), defaults: defaults)
        let profile = try store.addProfile(name: "Acct", organizationId: orgA, cookie: "test-cookie")
        store.setActive(id: profile.id)

        let mockUsage = MockUsageService()
        mockUsage.result = .success(testUsage)
        let fixture = UsageHistoryTestFixture()
        let coordinator = DataCoordinator(
            statusService: MockStatusService(),
            usageService: mockUsage,
            systemIdleProvider: MockSystemIdleProvider(),
            profileStore: store,
            defaults: defaults,
            usageHistory: fixture.history
        )

        // First refresh under orgA — populates windowAnalyses.
        await coordinator.refresh()
        #expect(!coordinator.monitorState.usage.windowAnalyses.isEmpty,
                "windowAnalyses must be populated after a successful refresh")

        // Switch to orgB and call restartPolling() which calls reloadCredentials() internally.
        try store.updateProfile(id: profile.id, name: "Acct", organizationId: orgB, cookie: "test-cookie")
        coordinator.restartPolling()

        // After reloadCredentials detects a different org ID, windowAnalyses must be cleared.
        #expect(coordinator.monitorState.usage.windowAnalyses.isEmpty,
                "windowAnalyses must be cleared after switching to a different org ID")

    }
}
