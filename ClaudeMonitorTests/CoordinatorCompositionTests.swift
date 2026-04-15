import Testing
import Foundation
@testable import ClaudeMonitor

/// Composition tests that verify cross-component wiring and data flow.
/// These specifically target seams between components where isolated unit tests cannot catch bugs.
@MainActor struct CoordinatorCompositionTests {

    // MARK: - Helpers

    private func makeCoordinator(
        status: any StatusFetching = MockStatusService(),
        usage: any UsageFetching = MockUsageService(),
        idle: MockSystemIdleProvider = MockSystemIdleProvider(),
        testOrgId: String = UUID().uuidString,
        credentials: [String: String]? = nil
    ) -> (DataCoordinator, String) {
        let creds = credentials ?? [
            Constants.Keychain.cookieString: "test-cookie",
            Constants.Keychain.organizationId: testOrgId,
        ]
        let coordinator = DataCoordinator(
            statusService: status,
            usageService: usage,
            systemIdleProvider: idle,
            loadCredential: { creds[$0] }
        )
        return (coordinator, testOrgId)
    }

    private func cleanupTestOrg(_ orgId: String) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let orgDir = base.appendingPathComponent("ClaudeMonitor/usage/\(orgId)")
        try? FileManager.default.removeItem(at: orgDir)
    }

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
        let (coordinator, orgId) = makeCoordinator(usage: mockUsage)
        defer { cleanupTestOrg(orgId) }
        await coordinator.refresh()

        // The coordinator's windowAnalyses must carry the same duration that came from the parser.
        let analyses = coordinator.monitorState.windowAnalyses
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
        let (coordinator, orgId) = makeCoordinator(usage: sequencedUsage)
        defer { cleanupTestOrg(orgId) }
        coordinator.onCriticalReset = { criticalResetCount += 1 }

        await coordinator.refresh() // Refresh 1: establishes critical baseline, no previous usage.
        #expect(criticalResetCount == 0, "No reset on first refresh — no previous usage to compare against.")

        await coordinator.refresh() // Refresh 2: detects reset from critical state.
        #expect(criticalResetCount == 1, "onCriticalReset must fire exactly once when reset is detected.")

        await coordinator.refresh() // Refresh 3: second response served again; same resetsAt, no new reset.
        #expect(criticalResetCount == 1, "onCriticalReset must not fire again when no new reset occurred.")
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
        let history = UsageHistory()
        let testOrgId = "test-reset-\(UUID().uuidString)"
        history.switchOrganization(testOrgId)
        defer {
            history.clearAll()
            let orgDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("ClaudeMonitor/usage/\(testOrgId)")
            try? FileManager.default.removeItem(at: orgDir)
        }

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

        // Simulate a reset for five_hour only — advance its resetsAt by more than duration/2.
        let newFiveHourResetsAt = fiveHourResetsAt.addingTimeInterval(18000)
        history.detectAndHandleReset(
            entry: fiveHourEntry,
            newResetsAt: newFiveHourResetsAt,
            previousResetsAt: fiveHourResetsAt
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
    /// Uses a mutable credentials store (reference type) to simulate the credential change
    /// without violating Sendable requirements on the closure capture.
    @Test func reloadCredentialsWithNewOrgClearsWindowAnalyses() async {
        // Reference-type credential store so the @Sendable closure can capture it safely.
        final class CredentialStore: @unchecked Sendable {
            var dict: [String: String]
            init(_ dict: [String: String]) { self.dict = dict }
        }
        let orgA = "test-org-a-\(UUID().uuidString)"
        let orgB = "test-org-b-\(UUID().uuidString)"
        defer {
            cleanupTestOrg(orgA)
            cleanupTestOrg(orgB)
        }

        let store = CredentialStore([
            Constants.Keychain.cookieString: "test-cookie",
            Constants.Keychain.organizationId: orgA,
        ])

        let mockUsage = MockUsageService()
        mockUsage.result = .success(testUsage)
        let coordinator = DataCoordinator(
            statusService: MockStatusService(),
            usageService: mockUsage,
            systemIdleProvider: MockSystemIdleProvider(),
            loadCredential: { store.dict[$0] }
        )

        // First refresh under orgA — populates windowAnalyses.
        await coordinator.refresh()
        #expect(!coordinator.monitorState.windowAnalyses.isEmpty,
                "windowAnalyses must be populated after a successful refresh")

        // Switch to orgB and call restartPolling() which calls reloadCredentials() internally.
        store.dict[Constants.Keychain.organizationId] = orgB
        coordinator.restartPolling()

        // After reloadCredentials detects a different org ID, windowAnalyses must be cleared.
        #expect(coordinator.monitorState.windowAnalyses.isEmpty,
                "windowAnalyses must be cleared after switching to a different org ID")
    }
}
