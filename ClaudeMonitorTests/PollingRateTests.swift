import Testing
import Foundation
@testable import ClaudeMonitor

struct PollingRateTests {

    // MARK: - Helpers

    private func makeEntry(resetsIn: TimeInterval = 3600) -> WindowEntry {
        WindowEntry(
            key: "five_hour",
            duration: 18000,
            durationLabel: "5h",
            modelScope: nil,
            window: UsageWindow(utilization: 50, resetsAt: Date().addingTimeInterval(resetsIn))
        )
    }

    private func makeAnalysis(
        projectedAtReset: Double = 50,
        consumptionRate: Double = 0,
        timeToLimit: TimeInterval? = nil,
        resetsIn: TimeInterval = 3600
    ) -> WindowAnalysis {
        WindowAnalysis(
            entry: makeEntry(resetsIn: resetsIn),
            samples: [],
            consumptionRate: consumptionRate,
            projectedAtReset: projectedAtReset,
            timeToLimit: timeToLimit,
            rateSource: .insufficient,
            style: Formatting.UsageStyle(level: .normal, isBold: false),
            segments: []
        )
    }

    // MARK: - Priority 1: Approaching Limit

    @Test func approachingLimitShortensInterval() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeToLimit: 300) // 300s < 600s threshold
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        // max(minInterval=24, 300/5=60) = 60
        #expect(scheduler.nextPollInterval(usage: nil) == max(Constants.Polling.minInterval, 300.0 / 5))
    }

    @Test func approachingLimitRespectsMinInterval() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeToLimit: 10) // 10/5=2, below minInterval
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.minInterval)
    }

    // MARK: - Priority 2: Significantly Outpacing

    @Test func significantlyOutpacingUsesHalfBase() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 130, consumptionRate: 0.01)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        // max(minInterval=24, baseInterval/2=30) = 30
        let expected = max(Constants.Polling.minInterval, Constants.Polling.baseInterval / 2)
        #expect(scheduler.nextPollInterval(usage: nil) == expected)
    }

    // MARK: - Priority 3: Mildly Outpacing

    @Test func mildlyOutpacingUsesBase() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 110, consumptionRate: 0.005)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    // MARK: - Priority 4: Active Consumption

    @Test func activeConsumptionUsesBase() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 70, consumptionRate: 0.001)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    // MARK: - Priority 5: Idle Cooldown

    @Test func idleCooldownGraduallyIncreasesInterval() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 50, consumptionRate: 0)

        // First get to base
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        let baseInterval = scheduler.nextPollInterval(usage: nil)
        #expect(baseInterval == Constants.Polling.baseInterval)

        // Drive through cooldownCycles iterations to trigger slowdown
        for _ in 0..<Constants.Polling.cooldownCycles {
            scheduler.adjustPollingRate(windowAnalyses: [analysis])
        }
        let slowedInterval = scheduler.nextPollInterval(usage: nil)
        #expect(slowedInterval > baseInterval)
    }

    @Test func idleCooldownCapsAt300Seconds() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 50, consumptionRate: 0)

        for _ in 0..<100 {
            scheduler.adjustPollingRate(windowAnalyses: [analysis])
        }
        #expect(scheduler.nextPollInterval(usage: nil) <= Constants.Retry.maxBackoff)
    }

    // MARK: - Near Reset

    @Test func nearResetSchedulesAfterReset() {
        let scheduler = PollingScheduler()
        let resetsIn: TimeInterval = 5 // resets in 5 seconds
        let entry = makeEntry(resetsIn: resetsIn)
        let usage = UsageResponse(entries: [entry])

        // effectivePollingInterval is base (60), so resetsIn < effectivePollingInterval
        let interval = scheduler.nextPollInterval(usage: usage)
        // Should be resetsIn + 1 padding ≈ 6 (allow small floating point tolerance)
        #expect(abs(interval - (resetsIn + 1)) < 0.01)
    }

    // MARK: - Failure Backoff

    @Test func failureBackoffUsesExponentialBackoff() {
        var scheduler = PollingScheduler()

        // Record enough failures to trigger backoff (each doubles: 10→20→40)
        let threshold = Constants.Retry.failureThreshold
        for _ in 0..<threshold {
            scheduler.recordUsageFailure(category: .transient)
        }

        let interval = scheduler.nextPollInterval(usage: nil)
        // initialBackoff=10, doubled threshold=2 times: 10*2=20, 20*2=40
        let expectedBackoff = Constants.Retry.initialBackoff * pow(2.0, Double(threshold))
        #expect(interval == min(expectedBackoff, Constants.Retry.maxBackoff))
    }

    @Test func failureBackoffStaysUnderMaxBackoff() {
        var scheduler = PollingScheduler()

        // Record many failures to saturate backoff
        for _ in 0..<20 {
            scheduler.recordUsageFailure(category: .transient)
        }

        let interval = scheduler.nextPollInterval(usage: nil)
        // nextPollInterval returns min(statusRetry=effectiveInterval, usageRetry=maxBackoff)
        #expect(interval <= Constants.Retry.maxBackoff)
    }

    // MARK: - Empty WindowAnalyses Resets to Base

    @Test func emptyWindowAnalysesResetsToBase() {
        var scheduler = PollingScheduler()
        // No window analyses → reset to base
        scheduler.adjustPollingRate(windowAnalyses: [])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }
}
