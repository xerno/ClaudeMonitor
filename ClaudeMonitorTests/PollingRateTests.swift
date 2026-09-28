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
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.01)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func moderateRateGivesExactInterval() {
        // desired = 1 / rate = 50s
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(abs(scheduler.nextPollInterval(usage: nil) - 50.0) < 0.01)
    }

    @Test func highRateHitsMinFloor() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.1)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.minInterval)
    }

    @Test func maxRateAcrossWindowsWins() {
        var scheduler = PollingScheduler()
        let a1 = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.005)
        let a2 = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [a1, a2])
        #expect(abs(scheduler.nextPollInterval(usage: nil) - 50.0) < 0.01)
    }

    // MARK: - activityFactor decay

    @Test func graceFullFactor() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 200, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(abs(scheduler.nextPollInterval(usage: nil) - 50.0) < 0.01)
    }

    @Test func midDecayHalfFactor() {
        // factor 0.5 halves the rate: desired 100s, clamped to base
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 900, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func postDecayZeroFactor() {
        // factor 0 → desired ∞; tslc < cooldownStart, so the upper bound is base
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 1800, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func graceBoundaryIncludesEndpoint() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.activityGrace, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(abs(scheduler.nextPollInterval(usage: nil) - 50.0) < 0.01)
    }

    @Test func decayEndBoundaryReachesZeroFactor() {
        var scheduler = PollingScheduler()
        let tslc = Constants.Polling.activityGrace + Constants.Polling.activityDecay
        let analysis = makeAnalysis(timeSinceLastChange: tslc, recentRate: 0.02)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    // MARK: - Cooldown (tslc ≥ cooldownStart)

    @Test func cooldownStartBoundary() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownStart, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func cooldownMidpoint() {
        var scheduler = PollingScheduler()
        let midpoint = (Constants.Polling.cooldownStart + Constants.Polling.cooldownEnd) / 2
        let analysis = makeAnalysis(timeSinceLastChange: midpoint, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        let expected = Constants.Polling.baseInterval + 0.5 * (Constants.Polling.maxIdleInterval - Constants.Polling.baseInterval)
        #expect(abs(scheduler.nextPollInterval(usage: nil) - expected) < 0.01)
    }

    @Test func cooldownEndReachesMaxIdle() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.maxIdleInterval)
    }

    // MARK: - Safety cap (near limit, not Away)

    @Test func nearLimitCapsAt120sInCooldown() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 85, timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.nearLimitCooldownCap)
    }

    @Test func nearLimitDoesNotAffectBaseCooldownBelowCap() {
        var scheduler = PollingScheduler()
        let tslc: TimeInterval = 2700
        let t = (tslc - Constants.Polling.cooldownStart) / (Constants.Polling.cooldownEnd - Constants.Polling.cooldownStart)
        let expected = Constants.Polling.baseInterval + t * (Constants.Polling.maxIdleInterval - Constants.Polling.baseInterval)
        let analysis = makeAnalysis(utilization: 85, timeSinceLastChange: tslc, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(abs(scheduler.nextPollInterval(usage: nil) - expected) < 0.01)
    }

    @Test func belowBoldThresholdNoCap() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 70, timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.maxIdleInterval)
    }

    @Test func safetyCapAtExactBoldThreshold() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 80, timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.nearLimitCooldownCap)
    }

    @Test func highRampUpOverridesSafetyCap() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 85, timeSinceLastChange: 200, recentRate: 0.1)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.minInterval)
    }

    // MARK: - Away mode

    @Test func awayModeActivatesAtCooldownCapAndSystemIdle() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode)
        #expect(scheduler.nextPollInterval(usage: nil) > Constants.Polling.maxIdleInterval)
    }

    @Test func awayModeRampsToMax() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: Constants.Polling.awayRampEnd)
        #expect(scheduler.isAwayMode)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.maxAwayInterval)
    }

    @Test func awayModeDoesNotActivateBelowCooldownCap() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: 3000)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(!scheduler.isAwayMode)
    }

    @Test func awayModeDoesNotActivateWhenSystemActive() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)
        #expect(!scheduler.isAwayMode)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.maxIdleInterval)
    }

    @Test func awayModeDeactivatesWhenSystemBecomesActive() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode, "Precondition: away mode must be active before deactivation test")

        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 100)

        #expect(!scheduler.isAwayMode)
    }

    @Test func awayModeIgnoresNearLimitCap() {
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(utilization: 85, timeSinceLastChange: Constants.Polling.cooldownEnd, recentRate: nil)
        scheduler.adjustPollingRate(windowAnalyses: [analysis], systemIdleTime: 600)
        #expect(scheduler.isAwayMode)
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
        var scheduler = PollingScheduler()
        let analysis = makeAnalysis(timeSinceLastChange: Constants.Polling.cooldownEnd)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.effectivePollingInterval > Constants.Polling.baseInterval)

        // 120s is beyond baseInterval but inside the 300s cooldown interval
        let resetsIn: TimeInterval = 120
        let entry = WindowEntry.make(
            key: "five_hour",
            utilization: 40,
            resetsAt: Date().addingTimeInterval(resetsIn)
        )!
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
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.1)
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
        let analysis = makeAnalysis(timeSinceLastChange: 60, recentRate: 0.1)
        scheduler.adjustPollingRate(windowAnalyses: [analysis])
        #expect(scheduler.effectivePollingInterval < Constants.Polling.baseInterval,
                "precondition: ramp-up must drive interval below base")

        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .authFailure)
        }
        // Both retry intervals are nil (non-retryable; healthy), but only two failed services floor at base
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
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordStatusFailure(category: .authFailure)
        }
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
