import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct CoordinatorCompositionTests {

    // MARK: - Helpers

    private var testUsage: UsageResponse {
        UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(9000))),
        ])
    }

    // MARK: - Test 1: JSON decode → coordinator pipeline

    @Test func jsonDecodeFlowsThroughCoordinatorWithCorrectDuration() async throws {
        let resetsAt = Date().addingTimeInterval(9000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetsAtString = formatter.string(from: resetsAt)

        let json = """
        {"five_hour": {"utilization": 42, "resets_at": "\(resetsAtString)"}}
        """

        let decoded = try JSONDecoder.iso8601WithFractionalSeconds.decode(
            UsageResponse.self, from: Data(json.utf8)
        )

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries[0].key == "five_hour")
        #expect(decoded.entries[0].duration == 18000)
        #expect(decoded.entries[0].window.utilization == 42)

        let mockUsage = MockUsageService()
        mockUsage.result = .success(decoded)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = makeCoordinator(fixture: fixture, usage: mockUsage)
        await coordinator.refresh()

        let analyses = coordinator.monitorState.usage.windowAnalyses
        #expect(analyses.count == 1)
        #expect(analyses[0].entry.duration == 18000)
        #expect(analyses[0].entry.key == "five_hour")
        #expect(analyses[0].entry.window.utilization == 42)
    }

    // MARK: - Test 2: onCriticalReset callback wiring via coordinator

    @Test func onCriticalResetCallbackFiredExactlyOnceAfterReset() async {
        let duration: TimeInterval = 18000
        let now = Date()

        // Critical baseline: 65% at the window midpoint projects to ≈130%.
        let prevResetsAt = now.addingTimeInterval(9000)
        let firstResponse = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 65, resetsAt: prevResetsAt))
        ])

        let nextResetsAt = prevResetsAt.addingTimeInterval(duration)
        let secondResponse = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 3, resetsAt: nextResetsAt))
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
        #expect(criticalResetCount == 0, "No reset on first refresh — no previous usage to compare against.")

        // `now` must be past prevResetsAt for the resets_at jump to be a genuine boundary, not drift.
        let refresh2Now = prevResetsAt.addingTimeInterval(10)
        await coordinator.refresh(now: refresh2Now)
        #expect(criticalResetCount == 1, "onCriticalReset must fire exactly once when reset is detected.")

        await coordinator.refresh(now: refresh2Now.addingTimeInterval(1))
        #expect(criticalResetCount == 1, "onCriticalReset must not fire again when no new reset occurred.")

    }

    // MARK: - Test 2b: Task 5 regression — a 90s resets_at nudge must not fire a critical reset

    /// 90s exceeds `resetBoundaryTolerance` (60s), but the old window has not ended, so the move is drift.
    @Test func ninetySecondResetsAtNudgeDoesNotFireCriticalReset() async {
        let duration: TimeInterval = 18000
        let now = Date()

        // Critical baseline: 65% at the window midpoint projects to ≈130%.
        let prevResetsAt = now.addingTimeInterval(9000)
        let firstResponse = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 65, resetsAt: prevResetsAt))
        ])
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
        await coordinator.refresh(now: now.addingTimeInterval(60))

        #expect(criticalResetCount == 0, "A 90s resets_at nudge that isn't a genuine boundary must never fire the critical reset.")
    }

    // MARK: - Test 3: Style equivalence between analyze() and inline usageStyle()

    /// The usageStyle overload that recomputes the projection and the one analyze() feeds a precomputed
    /// projection must agree at every threshold.
    @Test func analyzeAndUsageStyleProduceEquivalentStylesAtBoundaries() {
        let now = Date()
        let duration: TimeInterval = 18000
        let resetsAt = now.addingTimeInterval(9000)

        // Mid-window, projected = 2 × utilization: 39/40, 49/50, 59/60 straddle the 80/100/120 thresholds;
        // 100 is the blocked case.
        let utilizations = [39, 40, 49, 50, 59, 60, 99, 100]

        for util in utilizations {
            let entry = WindowEntry(
                key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                window: UsageWindow(utilization: util, resetsAt: resetsAt)
            )

            let styleA = Formatting.usageStyle(
                utilization: util,
                resetsAt: resetsAt,
                windowDuration: duration,
                now: now
            )

            let analysis = UsageHistory.analyze(entry: entry, samples: [], now: now)
            let styleB = analysis.style

            #expect(styleA == styleB,
                    "Style mismatch at utilization=\(util): usageStyle()=\(styleA), analyze().style=\(styleB)")
        }
    }

    // MARK: - Test 4: Multi-entry reset isolates only the affected key

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

        history.record(entries: [fiveHourEntry, sevenDayEntry], at: now.addingTimeInterval(-300))
        history.record(entries: [fiveHourEntry, sevenDayEntry], at: now)

        #expect(!history.samples(for: fiveHourEntry).isEmpty)
        #expect(!history.samples(for: sevenDayEntry).isEmpty)

        // `at:` is past fiveHourResetsAt, so this is a genuine boundary, not drift.
        let newFiveHourResetsAt = fiveHourResetsAt.addingTimeInterval(18000)
        await history.detectAndHandleReset(
            entry: fiveHourEntry,
            newResetsAt: newFiveHourResetsAt,
            at: fiveHourResetsAt.addingTimeInterval(10)
        )

        #expect(history.samples(for: fiveHourEntry).isEmpty,
                "five_hour samples must be cleared after its reset")

        #expect(!history.samples(for: sevenDayEntry).isEmpty,
                "seven_day samples must not be affected by the five_hour reset")

    }

    // MARK: - Test 5: org change on the same profile clears state

    @Test func orgChangeOnSameProfileClearsWindowAnalyses() async throws {
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
            makeUsageHistory: { UsageHistory(baseDirectory: fixture.baseDirectory) }
        )
        let monitorA = try #require(coordinator.activeMonitor)

        await coordinator.refresh()
        #expect(!coordinator.monitorState.usage.windowAnalyses.isEmpty,
                "windowAnalyses must be populated after a successful refresh")

        // restartPolling() reconciles monitors: orgA's is dropped and a fresh one built for orgB.
        try store.updateProfile(id: profile.id, name: "Acct", organizationId: orgB, cookie: "test-cookie")
        coordinator.restartPolling()
        coordinator.stopPolling()

        #expect(coordinator.monitorState.usage.windowAnalyses.isEmpty,
                "windowAnalyses must be empty on the fresh monitor after switching to a different org ID")
        let monitorB = try #require(coordinator.activeMonitor)
        #expect(monitorB !== monitorA)
    }
}
