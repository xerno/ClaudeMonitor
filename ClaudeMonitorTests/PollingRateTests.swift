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
        resetsIn: TimeInterval = 3600,
        timeSinceLastChange: TimeInterval? = nil,
        style: Formatting.UsageStyle = Formatting.UsageStyle(level: .normal, isBold: false)
    ) -> WindowAnalysis {
        WindowAnalysis(
            entry: makeEntry(resetsIn: resetsIn),
            samples: [],
            consumptionRate: consumptionRate,
            projectedAtReset: projectedAtReset,
            timeToLimit: timeToLimit,
            rateSource: .insufficient,
            style: style,
            segments: [],
            timeSinceLastChange: timeSinceLastChange
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

    // MARK: - Recent Activity

    @Test func recentActivityStaysAtBaseline() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 120)  // 2 min
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
        #expect(!scheduler.isAwayMode)
    }

    @Test func nilTimeSinceLastChangeStaysAtBaseline() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
        #expect(!scheduler.isAwayMode)
    }

    // MARK: - Idle at Desk Cooldown

    @Test func idleAtDeskInterpolatesInterval() {
        var scheduler = PollingScheduler()
        // 30 min since last change, normal severity → midpoint of cooldown ramp
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 1800)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        let interval = scheduler.nextPollInterval(usage: nil)
        // Should be between baseline (60) and maxIdleInterval (300)
        #expect(interval > Constants.Polling.baseInterval)
        #expect(interval < Constants.Polling.maxIdleInterval)
        #expect(!scheduler.isAwayMode)
    }

    @Test func idleAtDeskReachesCap() {
        var scheduler = PollingScheduler()
        // 60 min (3600s) since last change → fully cooled down
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 3600)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        let interval = scheduler.nextPollInterval(usage: nil)
        #expect(interval == Constants.Polling.maxIdleInterval)
        #expect(!scheduler.isAwayMode)
    }

    @Test func idleAtDeskBoundaryAtCooldownStart() {
        var scheduler = PollingScheduler()
        // Exactly 5 min (300s) → just at cooldown start → should be baseline
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 300)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        let interval = scheduler.nextPollInterval(usage: nil)
        #expect(interval == Constants.Polling.baseInterval)
    }

    // MARK: - Severity Dampener

    @Test func severityDampenerBoldSlowsCooldown() {
        var scheduler = PollingScheduler()
        let boldStyle = Formatting.UsageStyle(level: .normal, isBold: true)
        // 30 min since last change, bold severity (cooldownSpeed = 0.7)
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 1800, style: boldStyle)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        let boldInterval = scheduler.nextPollInterval(usage: nil)

        var scheduler2 = PollingScheduler()
        let normalAnalysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 1800)
        scheduler2.adjustPollingRate(windowAnalyses: [normalAnalysis])
        let normalInterval = scheduler2.nextPollInterval(usage: nil)

        // Bold severity should result in shorter interval (slower cooldown)
        #expect(boldInterval < normalInterval)
    }

    @Test func severityDampenerWarningSlowsCooldownMore() {
        var scheduler = PollingScheduler()
        let warningStyle = Formatting.UsageStyle(level: .warning, isBold: true)
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 1800, style: warningStyle)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        let warningInterval = scheduler.nextPollInterval(usage: nil)

        var scheduler2 = PollingScheduler()
        let boldStyle = Formatting.UsageStyle(level: .normal, isBold: true)
        let boldAnalysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 1800, style: boldStyle)
        scheduler2.adjustPollingRate(windowAnalyses: [boldAnalysis])
        let boldInterval = scheduler2.nextPollInterval(usage: nil)

        // Warning should cool down even slower than bold
        #expect(warningInterval < boldInterval)
    }

    // MARK: - Away Mode

    @Test func awayModeActivatesWhenIdleAndSystemIdle() {
        var scheduler = PollingScheduler()
        // 60 min tslc → at idle cap, systemIdle > 300 → should be Away
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 3600)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode)
        let interval = scheduler.nextPollInterval(usage: nil)
        #expect(interval > Constants.Polling.maxIdleInterval)
    }

    @Test func awayModeDoesNotActivateWhenSystemActive() {
        var scheduler = PollingScheduler()
        // 60 min tslc → at idle cap, but systemIdle = 100 < 300 → NOT Away
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 3600)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(!scheduler.isAwayMode)
        let interval = scheduler.nextPollInterval(usage: nil)
        #expect(interval == Constants.Polling.maxIdleInterval)
    }

    @Test func awayModeDoesNotActivateBeforeIdleCap() {
        var scheduler = PollingScheduler()
        // 15 min tslc → NOT at idle cap yet, even though systemIdle is high
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 900)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(!scheduler.isAwayMode)
    }

    @Test func awayModeReachesCap() {
        var scheduler = PollingScheduler()
        // 60 min tslc, systemIdle = 7200s (2h) → max Away
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 3600)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 7200)
        #expect(scheduler.isAwayMode)
        let interval = scheduler.nextPollInterval(usage: nil)
        #expect(interval == Constants.Polling.maxAwayInterval)
    }

    @Test func awayModeExitsWhenSystemIdleDrops() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 3600)
        // Enter Away
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode)
        // System idle drops → exit Away
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(!scheduler.isAwayMode)
    }

    // MARK: - Integration: Steady State Triggers Cooldown

    @Test @MainActor func steadyUtilizationWithSamplesEntersCooldown() {
        // This is the test that would have caught the original bug:
        // constant utilization across multiple polls must eventually increase the interval
        let now = Date()
        let entry = WindowEntry(
            key: "five_hour",
            duration: 18000,
            durationLabel: "5h",
            modelScope: nil,
            window: UsageWindow(utilization: 45, resetsAt: now.addingTimeInterval(3600))
        )
        // Simulate samples: utilization has been 45% for 30 minutes
        let samples = (0..<30).map { i in
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(TimeInterval(-1800 + i * 60)))
        }
        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        // timeSinceLastChange should be ~30 min (all samples at 45%)
        // This should trigger cooldown → interval > baseline
        #expect(analysis.timeSinceLastChange != nil)
        #expect(analysis.timeSinceLastChange! > Constants.Polling.cooldownStart)
        #expect(scheduler.nextPollInterval(usage: nil) > Constants.Polling.baseInterval)
    }

    @Test func resetClearsAwayMode() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(projectedAtReset: 50, timeSinceLastChange: 3600)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode)
        scheduler.reset()
        #expect(!scheduler.isAwayMode)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }
}
