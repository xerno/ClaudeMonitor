import Testing
import Foundation
import AppKit
@testable import ClaudeMonitor

@MainActor struct CompositionTests {

    private let mockStatus = MockStatusService()
    private let mockUsage = MockUsageService()

    private func coordinator(
        fixture: UsageHistoryTestFixture,
        testOrgId: String = UUID().uuidString,
        credentials: [String: String]? = nil
    ) -> (DataCoordinator, String) {
        makeCoordinator(
            fixture: fixture,
            status: mockStatus,
            usage: mockUsage,
            testOrgId: testOrgId,
            credentials: credentials
        )
    }

    // MARK: - JSON decode → WindowKeyParser → WindowEntry → analyze → scheduler

    @Test func testCriticalProjectionFromDecodedAPIResponse() async throws {
        let resetsAt = Date().addingTimeInterval(9000)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let resetsAtString = formatter.string(from: resetsAt)

        let json = """
        {"five_hour": {"utilization": 65, "resets_at": "\(resetsAtString)"}}
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: data)

        #expect(decoded.entries.count == 1)
        #expect(decoded.entries[0].key == "five_hour")
        #expect(decoded.entries[0].duration == 18000)
        #expect(decoded.entries[0].window.utilization == 65)

        mockUsage.result = .success(decoded)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        // One sample gives no recentRate (needs two), so the interval stays at baseInterval.
        let monitor = try #require(coordinator.activeMonitor)
        #expect(monitor.scheduler.effectivePollingInterval == Constants.Polling.baseInterval)
        // 65% at the window midpoint projects to 130%, independent of sample history.
        let analyses = coordinator.monitorState.usage.windowAnalyses
        #expect(!analyses.isEmpty)
        #expect(analyses[0].projectedAtReset >= Constants.Projection.criticalThreshold)
    }

    // MARK: - WindowAnalysis accumulates history across refreshes

    @Test func testWindowAnalysisAccumulatesHistoryAcrossRefreshes() async throws {
        let resetsAt = Date().addingTimeInterval(9000)
        let firstUsage = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 30, resetsAt: resetsAt)),
        ])
        mockUsage.result = .success(firstUsage)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        await coordinator.refresh()

        let secondUsage = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 45, resetsAt: resetsAt)),
        ])
        mockUsage.result = .success(secondUsage)

        await coordinator.refresh()

        let analyses = coordinator.monitorState.usage.windowAnalyses
        #expect(!analyses.isEmpty)
        let analysis = analyses[0]

        #expect(analysis.timeSinceLastChange != nil)

        // Measured from the 45% change point, which the back-to-back refresh recorded moments ago.
        let tslc = try #require(analysis.timeSinceLastChange)
        #expect(tslc < 1.0, "timeSinceLastChange should be nearly zero (< 1s) for back-to-back refreshes; got \(tslc)s")
    }

    // MARK: - monitorState.currentPollInterval reflects scheduler state

    @Test func testMonitorStateCurrentPollIntervalReflectsSchedulerState() async throws {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        let state = coordinator.monitorState

        #expect(state.polling.currentPollInterval != nil)

        // nextPollInterval(usage:) returns effectivePollingInterval unless a reset is due within it.
        let monitor = try #require(coordinator.activeMonitor)
        #expect(state.polling.currentPollInterval! == monitor.scheduler.effectivePollingInterval)
    }

    // MARK: - usageTitle always shows first entry regardless of projection

    @Test func testUsageTitleAlwaysShowsFirstEntryRegardlessOfProjection() {
        let resetsAt = Date().addingTimeInterval(18000 * 0.95)
        let usage = UsageResponse(entries: [
            WindowEntry.make(key: "five_hour", utilization: 2, resetsAt: resetsAt)!,
        ])

        let title = StatusBarRenderer.usageTitle(usage: usage)

        #expect(title.string.contains("2%"))

        let font = title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor

        #expect(font == StatusBarRenderer.regularFont)
        #expect(color == .labelColor)
    }

    // MARK: - Scheduler cooldown from real WindowAnalysis with stable history

    @Test func testSchedulerCooldownFromRealAnalysis() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 20, resetsAt: resetsAt)
        )

        // 95 one-minute gaps span exactly cooldownEnd (5700s).
        let sampleCount = 96
        let samples = (0..<sampleCount).map { i in
            UtilizationSample(
                utilization: 20,
                timestamp: now.addingTimeInterval(TimeInterval(-(sampleCount - 1 - i) * 60))
            )
        }

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.timeSinceLastChange != nil)
        #expect(analysis.timeSinceLastChange! > Constants.Polling.cooldownStart)
        #expect(analysis.timeSinceLastChange! >= Constants.Polling.cooldownEnd)

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        #expect(scheduler.effectivePollingInterval > Constants.Polling.baseInterval)
        #expect(scheduler.effectivePollingInterval == Constants.Polling.maxIdleInterval)
    }

    // MARK: - Scheduler cooldown mid-ramp is strictly between bounds

    /// Guards against the ramp collapsing into a step from baseInterval to maxIdleInterval at cooldownStart.
    @Test func testSchedulerCooldownMidRampIsStrictlyBetweenBounds() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 20, resetsAt: resetsAt)
        )

        let midRampTslc = (Constants.Polling.cooldownStart + Constants.Polling.cooldownEnd) / 2
        let samples = [
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-midRampTslc)),
            UtilizationSample(utilization: 20, timestamp: now),
        ]

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.timeSinceLastChange != nil)
        #expect(analysis.timeSinceLastChange! > Constants.Polling.cooldownStart)
        #expect(analysis.timeSinceLastChange! < Constants.Polling.cooldownEnd)

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        #expect(scheduler.effectivePollingInterval > Constants.Polling.baseInterval,
                "mid-ramp interval must be strictly greater than the pre-cooldown baseInterval")
        #expect(scheduler.effectivePollingInterval < Constants.Polling.maxIdleInterval,
                "mid-ramp interval must be strictly less than the fully-idle cap")
    }

    // MARK: - restartPolling resets currentPollInterval in MonitorState

    @Test func testRestartPollingResetsCurrentPollIntervalInMonitorState() async throws {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        let stateAfterRefresh = coordinator.monitorState
        #expect(stateAfterRefresh.polling.currentPollInterval != nil)

        coordinator.restartPolling()
        let monitor = try #require(coordinator.activeMonitor)
        #expect(monitor.scheduler.effectivePollingInterval == Constants.Polling.baseInterval)
    }

    // MARK: - windowAnalyses consistency with currentUsage

    @Test func testWindowAnalysesClearedAfterAuthFailure() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        let firstState = coordinator.monitorState
        #expect(firstState.usage.currentUsage != nil)
        #expect(!firstState.usage.windowAnalyses.isEmpty)

        mockUsage.result = .failure(ServiceError.unauthorized)
        await coordinator.refresh()

        let secondState = coordinator.monitorState
        #expect(secondState.usage.currentUsage == nil)
        #expect(secondState.usage.windowAnalyses.isEmpty, "windowAnalyses must be cleared after auth failure")
    }
}
