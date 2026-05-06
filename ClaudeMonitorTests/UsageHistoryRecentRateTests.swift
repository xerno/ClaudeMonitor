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

    @Test func computeRecentRateLinearGrowthMatchesExpected() {
        let now = Date()
        let samples = (0..<25).map { i in
            UtilizationSample(utilization: i, timestamp: now.addingTimeInterval(Double(i) * 60))
        }
        let rate = UsageHistory.computeRecentRate(samples: samples)
        #expect(rate != nil)
        let expected = 1.0 / 60.0
        #expect(abs(rate! - expected) < 0.001)
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
