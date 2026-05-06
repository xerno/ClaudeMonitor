import Testing
import Foundation
@testable import ClaudeMonitor

struct PollIntervalTests {

    private func usage(utilization: Int, resetsIn: TimeInterval = 3600) -> UsageResponse {
        UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: utilization, resetsAt: Date().addingTimeInterval(resetsIn)))
        ])
    }

    // MARK: - Blocked General Window

    private func makeAnalysis(key: String, modelScope: String?, utilization: Int) -> WindowAnalysis {
        let entry = WindowEntry(
            key: key, duration: 18000, durationLabel: "5h", modelScope: modelScope,
            window: UsageWindow(utilization: utilization, resetsAt: Date().addingTimeInterval(3600))
        )
        return WindowAnalysis(
            entry: entry, samples: [], consumptionRate: 0, projectedAtReset: Double(utilization),
            timeToLimit: nil, rateSource: .insufficient,
            style: Formatting.UsageStyle(level: .normal, isBold: false),
            segments: [], timeSinceLastChange: nil, recentRate: nil
        )
    }

    @Test func blockedGeneralWindowFloorsIntervalAt300() {
        var scheduler = PollingScheduler()
        let blocked = makeAnalysis(key: "five_hour", modelScope: nil, utilization: 100)
        scheduler.adjustPollingRate(windowAnalyses: [blocked])
        #expect(scheduler.effectivePollingInterval == Constants.Polling.blockedBaseInterval)
    }

    @Test func blockedModelSpecificOnlyDoesNotFloor() {
        var scheduler = PollingScheduler()
        let blocked = makeAnalysis(key: "seven_day_sonnet", modelScope: "Sonnet", utilization: 100)
        scheduler.adjustPollingRate(windowAnalyses: [blocked])
        #expect(scheduler.effectivePollingInterval < Constants.Polling.blockedBaseInterval)
    }

    @Test func noBlockedWindowUsesNormalInterval() {
        var scheduler = PollingScheduler()
        let normal = makeAnalysis(key: "five_hour", modelScope: nil, utilization: 50)
        scheduler.adjustPollingRate(windowAnalyses: [normal])
        #expect(scheduler.effectivePollingInterval < Constants.Polling.blockedBaseInterval)
    }

    @Test func blockedGeneralWithModelSpecificAlsoBlockedStillFloors() {
        var scheduler = PollingScheduler()
        let blockedGeneral = makeAnalysis(key: "five_hour", modelScope: nil, utilization: 100)
        let blockedModel = makeAnalysis(key: "seven_day_sonnet", modelScope: "Sonnet", utilization: 100)
        scheduler.adjustPollingRate(windowAnalyses: [blockedGeneral, blockedModel])
        #expect(scheduler.effectivePollingInterval == Constants.Polling.blockedBaseInterval)
    }

    // MARK: - Near-Reset Snapping

    @Test func nextPollIntervalNearReset() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [])
        // Window resets in 30s — within 60s effective interval
        let nearResetUsage = usage(utilization: 42, resetsIn: 30)
        let interval = scheduler.nextPollInterval(usage: nearResetUsage)
        // Should be ~31s (30 + 1 padding)
        #expect(interval > 28 && interval < 35)
    }

    @Test func nextPollIntervalResetBeyondEffectiveInterval() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [])
        // Reset 300s out — well beyond 60s interval → no snapping
        let farUsage = usage(utilization: 42, resetsIn: 300)
        #expect(scheduler.nextPollInterval(usage: farUsage) == Constants.Polling.baseInterval)
    }

    @Test func nearResetWithMultipleWindowsPicksNearest() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [])
        let multiWindowUsage = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(45))),
            WindowEntry(key: "seven_day", duration: 604_800, durationLabel: "7d", modelScope: nil,
                        window: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(20))),
        ])
        let interval = scheduler.nextPollInterval(usage: multiWindowUsage)
        // Nearest is 20s → 20+1=21
        #expect(interval > 18 && interval < 25)
    }

    // MARK: - Refresh Warning

    @Test func isAnyServiceStaleBelowThreshold() {
        var scheduler = PollingScheduler()
        scheduler.recordStatusFailure(category: .transient)
        #expect(!scheduler.isAnyServiceStale)
    }

    @Test func isAnyServiceStaleAtThreshold() {
        var scheduler = PollingScheduler()
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordStatusFailure(category: .transient)
        }
        #expect(scheduler.isAnyServiceStale)
    }

    @Test func isAnyServiceStaleFromUsageOnly() {
        var scheduler = PollingScheduler()
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .rateLimited)
        }
        #expect(scheduler.isAnyServiceStale)
    }

    // MARK: - Staleness

    @Test func isUsageDataExpiredReturnsFalseWithNoSuccess() {
        let scheduler = PollingScheduler()
        #expect(!scheduler.isUsageDataExpired) // guard let fails → false
    }

    @Test func isUsageDataExpiredReturnsFalseAfterFreshSuccess() {
        var scheduler = PollingScheduler()
        scheduler.recordUsageSuccess()
        #expect(!scheduler.isUsageDataExpired)
    }

}
