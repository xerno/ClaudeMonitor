import Testing
import Foundation
@testable import ClaudeMonitor

struct PollingRateTests {

    // MARK: - Helpers

    private func makeEntry(utilization: Int = 50, resetsIn: TimeInterval = 3600) -> WindowEntry {
        WindowEntry(
            key: "five_hour",
            duration: 18000,
            durationLabel: "5h",
            modelScope: nil,
            window: UsageWindow(utilization: utilization, resetsAt: Date().addingTimeInterval(resetsIn))
        )
    }

    private func makeAnalysis(
        utilization: Int = 50,
        resetsIn: TimeInterval = 3600,
        timeSinceLastChange: TimeInterval? = nil,
        recentRate: Double? = nil
    ) -> WindowAnalysis {
        WindowAnalysis(
            entry: makeEntry(utilization: utilization, resetsIn: resetsIn),
            samples: [],
            consumptionRate: 0,
            projectedAtReset: 50,
            timeToLimit: nil,
            rateSource: .insufficient,
            style: Formatting.UsageStyle(level: .normal, isBold: false),
            segments: [],
            timeSinceLastChange: timeSinceLastChange,
            recentRate: recentRate
        )
    }

    // MARK: - Empty / nil

    @Test func emptyWindowAnalysesResetsToBase() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func nilRecentRateStaysAtBaseline() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: nil, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
        #expect(!scheduler.isAwayMode)
    }

    @Test func zeroRecentRateStaysAtBaseline() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: nil, recentRate: 0)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    // MARK: - Rate-driven ramp-up (activityFactor = 1.0, tslc ≤ grace)

    @Test func lowRateStaysAtBase() {
        // recentRate=0.01 %/s → desired=1/0.01=100s → clamped to base 60s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.01)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func moderateRateGivesExactInterval() {
        // recentRate=0.02 %/s → desired=1/0.02=50s (50 > minInterval=24, < base=60) → 50s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(abs(scheduler.nextPollInterval(usage: nil) - 50.0) < 0.01)
    }

    @Test func highRateHitsMinFloor() {
        // recentRate=0.1 %/s → desired=1/0.1=10s → clamped to minInterval=24s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.1)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.minInterval)
    }

    @Test func maxRateAcrossWindowsWins() {
        // Two windows: 0.005 and 0.02. Max=0.02 → desired=50s
        var scheduler = PollingScheduler()
        let a1 = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.005)
        let a2 = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [a1, a2])
        #expect(abs(scheduler.nextPollInterval(usage: nil) - 50.0) < 0.01)
    }

    // MARK: - activityFactor decay

    @Test func graceFullFactor() {
        // tslc=200s (< grace=300s) → factor=1.0, recentRate=0.02 → desired=50s → 50s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 200, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(abs(scheduler.nextPollInterval(usage: nil) - 50.0) < 0.01)
    }

    @Test func midDecayHalfFactor() {
        // tslc=900s: afterGrace=600, decay=1200 → factor=0.5
        // effectiveRate=0.02*0.5=0.01 → desired=100s → clamped to base 60s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 900, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func postDecayZeroFactor() {
        // tslc=1800s > grace+decay(1500s) → factor=0 → desired=∞
        // cooldownInterval(1800): 1800 < cooldownStart(2100) → base=60s → 60s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 1800, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func graceBoundaryIncludesEndpoint() {
        // tslc = exactly activityGrace (300s) → factor=1.0 (inclusive upper bound of grace).
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.activityGrace, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(abs(scheduler.nextPollInterval(usage: nil) - 50.0) < 0.01)
    }

    @Test func decayEndBoundaryReachesZeroFactor() {
        // tslc = exactly activityGrace + activityDecay (1500s) → factor=0 (inclusive upper bound of decay).
        // effectiveRate=0 → desired=∞, upperBound=baseInterval (tslc < cooldownStart).
        var scheduler = PollingScheduler()
        let tslc = Constants.Polling.activityGrace + Constants.Polling.activityDecay
        let analysis = makeAnalysis(timeSinceLastChange: tslc, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    // MARK: - Cooldown (tslc ≥ cooldownStart)

    @Test func cooldownStartBoundary() {
        // tslc=2100 → exactly at cooldownStart → t=0 → baseInterval=60s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownStart, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func cooldownMidpoint() {
        // tslc=3900: midpoint of cooldownStart(2100)..cooldownEnd(5700) → t=0.5 → 60+0.5*240=180s
        var scheduler = PollingScheduler()
        let midpoint = (Constants.Polling.cooldownStart + Constants.Polling.cooldownEnd) / 2
        let analysis = makeAnalysis(timeSinceLastChange: midpoint, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        let expected = Constants.Polling.baseInterval + 0.5 * (Constants.Polling.maxIdleInterval - Constants.Polling.baseInterval)
        #expect(abs(scheduler.nextPollInterval(usage: nil) - expected) < 0.01)
    }

    @Test func cooldownEndReachesMaxIdle() {
        // tslc=5700 (cooldownEnd) → t=1 → maxIdleInterval=300s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.maxIdleInterval)
    }

    // MARK: - Safety cap (near limit, not Away)

    @Test func nearLimitCapsAt120sInCooldown() {
        // tslc=5700 (cooldown max=300s), util=85% (≥bold=80), systemIdle=100 (not away)
        // upperBound = min(300, nearLimitCooldownCap=120) = 120s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 85, timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.nearLimitCooldownCap)
    }

    @Test func nearLimitDoesNotAffectBaseCooldownBelowCap() {
        // tslc=2700: cooldown t=(2700-2100)/3600=1/6 → 60+(1/6)*240=100s < cap=120 → 100s unchanged
        var scheduler = PollingScheduler()
        let tslc: TimeInterval = 2700
        let t = (tslc - Constants.Polling.cooldownStart) / (Constants.Polling.cooldownEnd - Constants.Polling.cooldownStart)
        let expected = Constants.Polling.baseInterval + t * (Constants.Polling.maxIdleInterval - Constants.Polling.baseInterval)
        let analysis = makeAnalysis(utilization: 85, timeSinceLastChange: tslc, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(abs(scheduler.nextPollInterval(usage: nil) - expected) < 0.01)
    }

    @Test func belowBoldThresholdNoCap() {
        // tslc=5700, util=70% (< bold=80) → no cap → 300s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 70, timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.maxIdleInterval)
    }

    @Test func safetyCapAtExactBoldThreshold() {
        // tslc=5700, util=80 (exactly at bold=80) → cap applies → 120s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 80, timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.nearLimitCooldownCap)
    }

    @Test func highRampUpOverridesSafetyCap() {
        // tslc=200 (< grace=300), recentRate=0.1, util=85%
        // desired=10s, baseCooldown=60 (below cooldownStart), nearLimitCap=min(60,120)=60
        // combined=min(10,60)=10, clamped to minInterval=24s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 85, timeSinceLastChange: 200, recentRate: 0.1)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.minInterval)
    }

    // MARK: - Away mode

    @Test func awayModeActivatesAtCooldownCapAndSystemIdle() {
        // tslc=5700 → baseCooldown=300=maxIdleInterval → atCooldownCap=true
        // systemIdle=600 > awayThreshold=300 → awayMode=true, interval > maxIdle
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode)
        #expect(scheduler.nextPollInterval(usage: nil) > Constants.Polling.maxIdleInterval)
    }

    @Test func awayModeRampsToMax() {
        // tslc=5700, systemIdle=7200 (= awayRampEnd) → awayT=1 → maxAwayInterval=3600s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: Constants.Polling.awayRampEnd)
        #expect(scheduler.isAwayMode)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.maxAwayInterval)
    }

    @Test func awayModeDoesNotActivateBelowCooldownCap() {
        // tslc=3000: cooldown t=(3000-2100)/3600=0.25 → 60+0.25*240=120s < 300 → atCooldownCap=false
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 3000)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(!scheduler.isAwayMode)
    }

    @Test func awayModeDoesNotActivateWhenSystemActive() {
        // tslc=5700 → atCooldownCap=true, but systemIdle=100 < awayThreshold=300 → NOT away
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(!scheduler.isAwayMode)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.maxIdleInterval)
    }

    @Test func awayModeIgnoresNearLimitCap() {
        // tslc=5700, systemIdle=600, util=85% → Away mode → interval from away ramp (not capped at 120s)
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 85, timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode)
        // Away mode: awayT=(600-300)/6900≈0.0435 → upperBound≈300+0.0435*3300≈443s > nearLimitCap(120s)
        #expect(scheduler.nextPollInterval(usage: nil) > Constants.Polling.nearLimitCooldownCap)
    }

    // MARK: - Near-reset snap

    @Test func nearResetSchedulesAfterReset() {
        let scheduler = PollingScheduler()
        let resetsIn: TimeInterval = 5
        let entry = makeEntry(resetsIn: resetsIn)
        let usage = UsageResponse(entries: [entry])
        let interval = scheduler.nextPollInterval(usage: usage)
        #expect(abs(interval - (resetsIn + 1)) < 0.01)
    }

    @Test func nearResetSnappingInCooldown() {
        // Put scheduler into cooldown state (tslc=cooldownEnd → effectiveInterval=300s)
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.effectivePollingInterval > Constants.Polling.baseInterval)

        // Reset in 120s: 60 < 120 < 300 → near-reset snap fires
        let resetsIn: TimeInterval = 120
        let entry = WindowEntry.make(
            key: "five_hour",
            utilization: 40,
            resetsAt: Date().addingTimeInterval(resetsIn)
        )
        let usage = UsageResponse(entries: [entry])
        let interval = scheduler.nextPollInterval(usage: usage)
        #expect(abs(interval - (resetsIn + 1)) < 0.5)
        #expect(interval < scheduler.effectivePollingInterval)
    }

    // MARK: - Failure backoff

    @Test func failureBackoffUsesExponential() {
        var scheduler = PollingScheduler()
        let threshold = Constants.Retry.failureThreshold
        for _ in 0..<threshold {
            scheduler.recordUsageFailure(category: .transient)
            scheduler.recordStatusFailure(category: .transient)
        }
        // initialBackoff=10, doubled threshold times: 10*2^threshold
        let expectedBackoff = Constants.Retry.initialBackoff * pow(2.0, Double(threshold))
        #expect(scheduler.nextPollInterval(usage: nil) == min(expectedBackoff, Constants.Retry.maxBackoff))
    }

    @Test func failureBackoffStaysUnderMax() {
        var scheduler = PollingScheduler()
        for _ in 0..<20 {
            scheduler.recordUsageFailure(category: .transient)
        }
        #expect(scheduler.nextPollInterval(usage: nil) <= Constants.Retry.maxBackoff)
    }

    @Test func authFailureFallsBackToEffective() {
        var scheduler = PollingScheduler()
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .authFailure)
        }
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func bothNonRetryableFlooredAtBase() {
        var scheduler = PollingScheduler()
        // Drive effectivePollingInterval below baseInterval using high recentRate within grace
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.1) // desired=10s → minInterval=24s
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.effectivePollingInterval < Constants.Polling.baseInterval,
                "precondition: ramp-up must drive interval below base")

        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .authFailure)
            scheduler.recordStatusFailure(category: .permanent)
        }
        #expect(scheduler.nextPollInterval(usage: nil) >= Constants.Polling.baseInterval)
    }

    @Test func mixedHealthyAndAuthFailedDoesNotFloor() {
        var scheduler = PollingScheduler()
        // Drive effectivePollingInterval below baseInterval using high recentRate within grace
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.1) // desired=10s → minInterval=24s
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.effectivePollingInterval < Constants.Polling.baseInterval,
                "precondition: ramp-up must drive interval below base")

        // Only usage hits the threshold with non-retryable auth failure; status is healthy
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .authFailure)
        }
        // retryInterval(for: usageState)==nil (authFailure non-retryable),
        // retryInterval(for: statusState)==nil (below threshold → healthy)
        // → picks effectivePollingInterval < baseInterval
        #expect(scheduler.nextPollInterval(usage: nil) < Constants.Polling.baseInterval)
    }

    @Test func picksShorterOfTwoBackoffs() {
        var scheduler = PollingScheduler()
        let threshold = Constants.Retry.failureThreshold
        for _ in 0..<threshold {
            scheduler.recordStatusFailure(category: .transient)
            scheduler.recordUsageFailure(category: .transient)
        }
        let thresholdBackoff = Constants.Retry.initialBackoff * pow(2.0, Double(threshold))
        #expect(scheduler.nextPollInterval(usage: nil) == thresholdBackoff)

        scheduler.recordStatusFailure(category: .transient)
        #expect(scheduler.nextPollInterval(usage: nil) == thresholdBackoff,
                "status backoff doubles but usage stays at threshold → min picks usage")
    }

    @Test func mixedErrorCategories() {
        var scheduler = PollingScheduler()
        // Status: auth failure (no backoff / nil retryInterval)
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordStatusFailure(category: .authFailure)
        }
        // Usage: transient (exponential backoff)
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .transient)
        }
        let usageBackoff = Constants.Retry.initialBackoff * pow(2.0, Double(Constants.Retry.failureThreshold))
        #expect(scheduler.nextPollInterval(usage: nil) == min(Constants.Polling.baseInterval, usageBackoff))
    }

    // MARK: - Reset

    @Test func resetClearsState() {
        var scheduler = PollingScheduler()
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .transient)
        }
        let highRateAnalysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [highRateAnalysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode)

        scheduler.reset()

        #expect(!scheduler.isAwayMode)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
        #expect(scheduler.statusState.consecutiveFailures == 0)
        #expect(scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - Integration: Steady State Triggers Cooldown

    @Test @MainActor func steadyUtilizationWithSamplesEntersCooldown() {
        let now = Date()
        let entry = WindowEntry(
            key: "five_hour",
            duration: 18000,
            durationLabel: "5h",
            modelScope: nil,
            window: UsageWindow(utilization: 45, resetsAt: now.addingTimeInterval(3600))
        )
        // Constant utilization for >cooldownStart seconds
        let samples = (0..<40).map { i in
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(TimeInterval(-2400 + i * 60)))
        }
        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [analysis])

        #expect(analysis.timeSinceLastChange != nil)
        #expect(analysis.timeSinceLastChange! > Constants.Polling.cooldownStart)
        #expect(scheduler.nextPollInterval(usage: nil) > Constants.Polling.baseInterval)
    }
}
