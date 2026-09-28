import Foundation
import Testing
@testable import ClaudeMonitor

@Suite @MainActor struct RecentRateTests {

    @Test func computeRecentRateReturnsNilForInsufficientSamples() {
        let now = Date()
        #expect(UsageHistory.computeRecentRate(samples: []) == nil)
        let single = [UtilizationSample(utilization: 50, timestamp: now)]
        #expect(UsageHistory.computeRecentRate(samples: single) == nil)
    }

    @Test func computeRecentRateConstantUtilizationIsZero() {
        let now = Date()
        let samples = (0..<10).map { i in
            UtilizationSample(utilization: 50, timestamp: now.addingTimeInterval(Double(i) * 60))
        }
        let rate = UsageHistory.computeRecentRate(samples: samples)
        #expect(rate != nil)
        #expect(abs(rate! - 0.0) < 0.0001)
    }

    @Test func computeRecentRateConstantNonzeroRateConvergesToRate() {
        let now = Date()
        let samples = (0..<25).map { i in
            UtilizationSample(utilization: i, timestamp: now.addingTimeInterval(Double(i) * 60))
        }
        let rate = UsageHistory.computeRecentRate(samples: samples)
        #expect(rate != nil)
        let expected = 1.0 / 60.0
        #expect(abs(rate! - expected) < 0.001)
    }

    private func buildSamples(start: Int, steps: [(du: Int, dt: TimeInterval)], startTime: Date) -> [UtilizationSample] {
        var samples = [UtilizationSample(utilization: start, timestamp: startTime)]
        var t = startTime
        var u = start
        for step in steps {
            t = t.addingTimeInterval(step.dt)
            u += step.du
            samples.append(UtilizationSample(utilization: u, timestamp: t))
        }
        return samples
    }

    @Test func computeRecentRateWeightsRecentRateChangeOverOlderHistory() {
        let now = Date()
        let slowSteps: [(Int, TimeInterval)] = Array(repeating: (0, 60.0), count: 15)
        let fastSteps: [(Int, TimeInterval)] = Array(repeating: (6, 60.0), count: 5)
        let samples = buildSamples(start: 0, steps: slowSteps + fastSteps, startTime: now)

        let rate = UsageHistory.computeRecentRate(samples: samples)
        #expect(rate != nil)

        let fastRate = 0.1
        let arithmeticMean = (15 * 0.0 + 5 * fastRate) / 20.0
        #expect(rate! > arithmeticMean, "a recency-weighted EMA must land above the plain average of all steps")
        #expect(rate! < fastRate, "a true EMA with alpha < 1 must not fully reach the most recent instantaneous rate")
        #expect(rate! > fastRate * 0.9, "the recent fast stretch should dominate, landing close to its own rate")
    }

    @Test func computeRecentRateOrderOfStepsChangesResult() {
        let now = Date()
        let slowSteps: [(Int, TimeInterval)] = Array(repeating: (0, 60.0), count: 15)
        let fastSteps: [(Int, TimeInterval)] = Array(repeating: (6, 60.0), count: 5)

        let slowThenFast = buildSamples(start: 0, steps: slowSteps + fastSteps, startTime: now)
        let fastThenSlow = buildSamples(start: 0, steps: fastSteps + slowSteps, startTime: now)

        let rateSlowThenFast = UsageHistory.computeRecentRate(samples: slowThenFast)
        let rateFastThenSlow = UsageHistory.computeRecentRate(samples: fastThenSlow)
        #expect(rateSlowThenFast != nil)
        #expect(rateFastThenSlow != nil)

        #expect(rateSlowThenFast! - rateFastThenSlow! > 0.05)
    }

    @Test func computeRecentRateDeltaTimeAffectsWeighting() {
        let now = Date()
        let slowSteps: [(Int, TimeInterval)] = Array(repeating: (0, 60.0), count: 15)
        // Both fast phases run at 0.1/s; alpha = 1 - exp(-dt/tau) is small at dt=10s, large at dt=120s.
        let fastStepsShortDt: [(Int, TimeInterval)] = Array(repeating: (1, 10.0), count: 5)
        let fastStepsLongDt: [(Int, TimeInterval)] = Array(repeating: (12, 120.0), count: 5)

        let samplesShortDt = buildSamples(start: 0, steps: slowSteps + fastStepsShortDt, startTime: now)
        let samplesLongDt = buildSamples(start: 0, steps: slowSteps + fastStepsLongDt, startTime: now)

        let rateShortDt = UsageHistory.computeRecentRate(samples: samplesShortDt)
        let rateLongDt = UsageHistory.computeRecentRate(samples: samplesLongDt)
        #expect(rateShortDt != nil)
        #expect(rateLongDt != nil)

        #expect(rateLongDt! > rateShortDt!)
    }

    @Test func computeRecentRateShortBurstBarelyMovesEma() {
        let now = Date()
        var samples: [UtilizationSample] = (0..<20).map { i in
            UtilizationSample(utilization: 0, timestamp: now.addingTimeInterval(Double(i) * 60))
        }
        samples.append(UtilizationSample(utilization: 1, timestamp: now.addingTimeInterval(Double(19) * 60 + 2)))
        let rate = UsageHistory.computeRecentRate(samples: samples)
        #expect(rate != nil)
        #expect(rate! > 0.01 && rate! < 0.025,
                "ema after short 2s burst should be ~0.016, got \(rate!)")
    }

    @Test func computeRecentRateResetsOnNegativeDelta() {
        let now = Date()
        let utils = [90, 95, 0, 1, 2]
        let samples = utils.enumerated().map { (i, u) in
            UtilizationSample(utilization: u, timestamp: now.addingTimeInterval(Double(i) * 60))
        }
        let rate = UsageHistory.computeRecentRate(samples: samples)
        #expect(rate != nil)
        #expect(rate! >= 0)
        #expect(rate! < 0.083)
    }

    @Test func computeRecentRateSkipsZeroDeltaTime() {
        let now = Date()
        let s1 = UtilizationSample(utilization: 50, timestamp: now)
        let s2 = UtilizationSample(utilization: 60, timestamp: now)
        let s3 = UtilizationSample(utilization: 61, timestamp: now.addingTimeInterval(60))
        let rate = UsageHistory.computeRecentRate(samples: [s1, s2, s3])
        #expect(rate != nil)
        #expect(abs(rate! - 1.0/60.0) < 0.001)
    }

    @Test func computeRecentRateCustomTau() {
        let now = Date()
        var samples: [UtilizationSample] = (0..<10).map { i in
            UtilizationSample(utilization: i, timestamp: now.addingTimeInterval(Double(i) * 60))
        }
        samples.append(UtilizationSample(utilization: 15, timestamp: now.addingTimeInterval(9 * 60 + 1)))

        let rateFastTau = UsageHistory.computeRecentRate(samples: samples, tau: 1)
        let rateSlowTau = UsageHistory.computeRecentRate(samples: samples, tau: 600)

        #expect(rateFastTau != nil)
        #expect(rateSlowTau != nil)
        #expect(rateFastTau! > rateSlowTau!)
    }
}
