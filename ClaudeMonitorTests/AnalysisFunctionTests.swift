import Testing
import Foundation
@testable import ClaudeMonitor

// MARK: - SegmentSamplesBehaviorTests
//
// segmentSamples is internal and testable directly.
// gapThreshold = 300s (Constants.History.gapThreshold).
// An "inferred" leading segment is added when the first sample is > 60s after windowStart.

@Suite @MainActor struct SegmentSamplesBehaviorTests {

    // No samples → empty result (degenerate input).
    @Test func emptySamplesProducesNoSegments() {
        let windowStart = Date()
        let result = UsageHistory.segmentSamples([], windowStart: windowStart)
        #expect(result.isEmpty)
    }

    // Single sample that arrives > 60s after window start → produces one inferred segment
    // (windowStart→sample) and one tracked segment (just the sample itself).
    @Test func singleSampleLateArrivalProducesInferredPlusTracked() {
        let windowStart = Date()
        let sample = UtilizationSample(utilization: 30, timestamp: windowStart.addingTimeInterval(120))
        let result = UsageHistory.segmentSamples([sample], windowStart: windowStart)

        // inferred: [windowStart@0%, sample@30%], tracked: [sample@30%]
        #expect(result.count == 2)
        #expect(result[0].kind == .inferred)
        #expect(result[1].kind == .tracked)
        #expect(result[0].samples.count == 2)
        #expect(result[0].samples[0].utilization == 0)   // inferred start is always 0%
        #expect(result[0].samples[1].utilization == 30)
        #expect(result[1].samples.count == 1)
        #expect(result[1].samples[0].utilization == 30)
    }

    // Single sample that arrives within 60s of window start → no inferred segment; just tracked.
    @Test func singleSampleEarlyArrivalProducesOnlyTracked() {
        let windowStart = Date()
        let sample = UtilizationSample(utilization: 10, timestamp: windowStart.addingTimeInterval(30))
        let result = UsageHistory.segmentSamples([sample], windowStart: windowStart)

        #expect(result.count == 1)
        #expect(result[0].kind == .tracked)
    }

    // Continuous samples (all gaps < gapThreshold=300s) → single tracked segment, no gaps.
    @Test func continuousSamplesProduceSingleTrackedSegment() {
        let windowStart = Date()
        // 5 samples, 60s apart — well within the 300s gap threshold.
        let samples = (0..<5).map { i in
            UtilizationSample(utilization: i * 10, timestamp: windowStart.addingTimeInterval(Double(i) * 60))
        }

        let result = UsageHistory.segmentSamples(samples, windowStart: windowStart)

        // First sample is 0s after windowStart — within 60s grace → no inferred segment.
        let trackedSegments = result.filter { $0.kind == .tracked }
        let gapSegments     = result.filter { $0.kind == .gap }
        #expect(gapSegments.isEmpty)
        #expect(trackedSegments.count == 1)
        #expect(trackedSegments[0].samples.count == 5)
    }

    // Two samples with a gap exactly at the threshold (300s) → NOT a gap (gap > threshold, not >=).
    @Test func gapAtExactThresholdIsNotDetectedAsGap() {
        let windowStart = Date()
        let s1 = UtilizationSample(utilization: 20, timestamp: windowStart)
        let s2 = UtilizationSample(utilization: 40, timestamp: windowStart.addingTimeInterval(300))
        // gap == gapThreshold (not strictly greater) → should NOT produce a gap segment
        let result = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart, gapThreshold: 300)

        let gapSegments = result.filter { $0.kind == .gap }
        #expect(gapSegments.isEmpty)
    }

    // Two samples with a gap just above the threshold → gap segment produced.
    @Test func gapAboveThresholdProducesGapSegment() {
        let windowStart = Date()
        let s1 = UtilizationSample(utilization: 20, timestamp: windowStart)
        // 301s gap — strictly greater than 300s threshold
        let s2 = UtilizationSample(utilization: 40, timestamp: windowStart.addingTimeInterval(301))

        let result = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart, gapThreshold: 300)

        let gapSegments = result.filter { $0.kind == .gap }
        #expect(gapSegments.count == 1)
        // Gap segment endpoints are the samples on either side of the gap
        #expect(gapSegments[0].samples[0].utilization == 20)
        #expect(gapSegments[0].samples[1].utilization == 40)
    }

    // Multiple gaps across a longer timeline → each gap produces its own gap segment,
    // and tracked segments appear between gaps.
    @Test func multipleGapsProduceMultipleGapAndTrackedSegments() {
        let windowStart = Date()
        // Layout: [s0]—60s—[s1]  —600s gap—  [s2]—60s—[s3]  —900s gap—  [s4]
        let s0 = UtilizationSample(utilization:  5, timestamp: windowStart)
        let s1 = UtilizationSample(utilization: 10, timestamp: windowStart.addingTimeInterval(60))
        let s2 = UtilizationSample(utilization: 15, timestamp: windowStart.addingTimeInterval(660))   // 600s after s1
        let s3 = UtilizationSample(utilization: 20, timestamp: windowStart.addingTimeInterval(720))
        let s4 = UtilizationSample(utilization: 30, timestamp: windowStart.addingTimeInterval(1620))  // 900s after s3

        let result = UsageHistory.segmentSamples([s0, s1, s2, s3, s4], windowStart: windowStart)

        let kinds = result.map(\.kind)
        // Expected: [.tracked(s0,s1), .gap(s1,s2), .tracked(s2,s3), .gap(s3,s4), .tracked(s4)]
        #expect(kinds == [.tracked, .gap, .tracked, .gap, .tracked])

        // First tracked segment contains s0 and s1
        #expect(result[0].samples.count == 2)
        #expect(result[0].samples[0].utilization == 5)
        #expect(result[0].samples[1].utilization == 10)

        // Second tracked segment contains s2 and s3
        #expect(result[2].samples.count == 2)

        // Final tracked segment is a single sample (s4)
        #expect(result[4].samples.count == 1)
        #expect(result[4].samples[0].utilization == 30)
    }

    // Inferred segment is added even when a gap exists later — the inferred segment
    // represents the app being absent at window start, not a mid-session gap.
    @Test func inferredSegmentPrecededByLaterGap() {
        let windowStart = Date()
        // First sample arrives 200s after windowStart → inferred segment added.
        // Then a 600s gap appears between s1 and s2.
        let s1 = UtilizationSample(utilization: 10, timestamp: windowStart.addingTimeInterval(200))
        let s2 = UtilizationSample(utilization: 25, timestamp: windowStart.addingTimeInterval(800))  // 600s after s1

        let result = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart)

        let kinds = result.map(\.kind)
        // [.inferred, .tracked(s1), .gap(s1,s2), .tracked(s2)]
        #expect(kinds == [.inferred, .tracked, .gap, .tracked])
        // Inferred segment starts at 0% (windowStart) and ends at first real sample
        #expect(result[0].samples[0].utilization == 0)
        #expect(result[0].samples[1].utilization == 10)
    }

    // Custom gapThreshold parameter overrides the default.
    @Test func customGapThresholdIsRespected() {
        let windowStart = Date()
        let s1 = UtilizationSample(utilization: 10, timestamp: windowStart)
        // 100s gap — below default 300s but above custom 60s threshold
        let s2 = UtilizationSample(utilization: 20, timestamp: windowStart.addingTimeInterval(100))

        // With default threshold (300s): no gap
        let resultDefault = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart, gapThreshold: 300)
        #expect(resultDefault.filter { $0.kind == .gap }.isEmpty)

        // With custom threshold (60s): gap detected
        let resultCustom = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart, gapThreshold: 60)
        #expect(resultCustom.filter { $0.kind == .gap }.count == 1)
    }
}

// MARK: - ComputeRateEdgeCaseTests
//
// Core happy-path and obvious edges already covered in UsageHistoryTests.swift
// (RateComputationTests). This suite covers boundary and less-obvious cases.

@Suite @MainActor struct ComputeRateEdgeCaseTests {

    // When now is past resetsAt (window has already expired), timeElapsed can exceed windowDuration.
    // The formula still computes a finite rate — it doesn't clamp timeElapsed.
    @Test func rateWhenNowIsAfterResetsAt() {
        let now = Date()
        // resetsAt is 60s in the past → timeElapsed = 18000 + 60 = 18060s
        let resetsAt = now.addingTimeInterval(-60)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 50,
            resetsAt: resetsAt,
            now: now
        )
        // timeElapsed = 18000 - max(0, -60) = 18000 - 0 = 18000
        // rate = 50 / 18000 ≈ 0.002778
        #expect(source == .implied)
        let expectedRate = 50.0 / 18000.0
        #expect(abs(rate - expectedRate) < 0.0001)
    }

    // Maximum utilization (100%) gives maximum rate — used to compute blocking projection.
    @Test func rateAtFullUtilization() {
        let now = Date()
        // 3600s remaining on 18000s window → elapsed = 14400s
        let resetsAt = now.addingTimeInterval(3600)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 100,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .implied)
        // rate = 100 / 14400 ≈ 0.006944
        let expected = 100.0 / 14400.0
        #expect(abs(rate - expected) < 0.0001)
    }

    // resetsAt exactly equals now + windowDuration → elapsed = 0 → insufficient.
    // (This is tested in RateComputationTests as "insufficientWhenWindowJustStarted"
    //  for utilization=0; verify it also holds for non-zero utilization.)
    @Test func insufficientWhenWindowJustStartedNonZeroUtilization() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(18000) // elapsed = 0
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 75,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .insufficient)
        #expect(rate == 0)
    }
}

// MARK: - ProjectEdgeCaseTests
//
// Core cases already covered in UsageHistoryTests.swift (ProjectionTests).
// This suite covers boundary conditions not present there.

@Suite @MainActor struct ProjectEdgeCaseTests {

    // timeToLimit should be nil when TTL would exceed timeRemaining
    // (user won't hit the limit before reset even at current rate).
    @Test func timeToLimitNilWhenLimitNotReachedBeforeReset() {
        // util=50, rate=0.005/s, timeRemaining=3600
        // TTL = (100-50)/0.005 = 10000s > 3600s → timeToLimit = nil
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 50,
            rate: 0.005,
            timeRemaining: 3600
        )
        // projected = 50 + 0.005*3600 = 68
        #expect(abs(projected - 68.0) < 0.01)
        #expect(timeToLimit == nil)
    }

    // timeToLimit equals timeRemaining when the limit is hit exactly at the reset moment.
    // TTL = (100-util)/rate must equal timeRemaining.
    @Test func timeToLimitEqualsTimeRemainingAtBoundary() {
        // util=50, timeRemaining=3600
        // For TTL == timeRemaining: rate = (100-50)/3600 = 50/3600 ≈ 0.013889
        let rate = 50.0 / 3600.0
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 50,
            rate: rate,
            timeRemaining: 3600
        )
        // projected = 50 + (50/3600)*3600 = 100
        #expect(abs(projected - 100.0) < 0.01)
        // TTL = 3600s == timeRemaining → timeToLimit is set (TTL <= timeRemaining)
        #expect(timeToLimit != nil)
        #expect(abs(timeToLimit! - 3600.0) < 0.01)
    }

    // Negative rate (utilization decreasing) → projected < current utilization.
    // timeToLimit is nil since rate <= 0.
    @Test func negativeRateProjectsBelow() {
        // util=50, rate=-0.01/s, timeRemaining=1000
        // projected = 50 + (-0.01)*1000 = 40
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 50,
            rate: -0.01,
            timeRemaining: 1000
        )
        #expect(abs(projected - 40.0) < 0.01)
        #expect(timeToLimit == nil) // rate not > 0
    }

    // Zero time remaining → projection equals current utilization (rate * 0 = 0).
    @Test func zeroTimeRemainingProjectsCurrentUtilization() {
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 70,
            rate: 0.1,
            timeRemaining: 0
        )
        #expect(abs(projected - 70.0) < 0.01)
        // TTL = (100-70)/0.1 = 300s > timeRemaining(0) → timeToLimit nil
        #expect(timeToLimit == nil)
    }
}

// MARK: - ComputeTimeSinceLastChangeEdgeCaseTests
//
// Core cases already covered in UsageHistoryTests.swift (TimeSinceLastChangeTests).
// This suite covers the edge case where the last sample IS the change point.

@Suite @MainActor struct ComputeTimeSinceLastChangeEdgeCaseTests {

    // Edge case documented in source: last sample differs from currentUtilization
    // and there's no sample after it → returns 0 ("change is now").
    @Test func lastSampleDiffersWithNoSubsequentSampleReturnsZero() {
        let now = Date()
        // samples: [..., 30%], currentUtilization=45 (i.e., the current value just changed
        // and the samples array doesn't yet include the new value)
        let samples = [
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-600)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-60)),
        ]
        // currentUtilization (45) differs from all samples — walking back finds last (30≠45),
        // then i+1 = 2 which is out of bounds → returns 0.
        let result = UsageHistory.computeTimeSinceLastChange(
            currentUtilization: 45,
            samples: samples,
            now: now
        )
        #expect(result != nil)
        #expect(result! == 0)
    }

    // Change occurred right at the oldest sample boundary — timeSinceLastChange should
    // be time since the second sample (the first sample with the current utilization).
    @Test func changeAtOldestSampleBoundary() {
        let now = Date()
        // samples: [10% at -300s, 30% at -200s, 30% at -100s]
        // currentUtilization = 30; walk back: sample[2]=30 (skip), sample[1]=30 (skip),
        // sample[0]=10 ≠ 30 → return time since sample[1] = 200s
        let samples = [
            UtilizationSample(utilization: 10, timestamp: now.addingTimeInterval(-300)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-200)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-100)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 30, samples: samples, now: now)
        // Change was from 10→30 at -200s → timeSinceLastChange = 200s
        #expect(result != nil)
        #expect(abs(result! - 200) < 1)
    }

    // Two samples, both different from currentUtilization — the "last differing" is sample[1],
    // so i+1 = 2 is out of bounds → returns 0.
    @Test func allSamplesDifferFromCurrentReturnZero() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 10, timestamp: now.addingTimeInterval(-300)),
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-100)),
        ]
        // currentUtilization = 50, which differs from all samples.
        // Walk back: sample[1]=20≠50 → i+1=2 is out of bounds → return 0.
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 50, samples: samples, now: now)
        #expect(result != nil)
        #expect(result! == 0)
    }
}

// MARK: - AnalyzeComprehensiveTests
//
// Tests for UsageHistory.analyze() focusing on cases not covered by
// AnalyzeIntegrationTests in UsageHistoryTests.swift.

@Suite @MainActor struct AnalyzeComprehensiveTests {

    // Zero samples → rate source is .insufficient; rateSource and other fields reflect this.
    @Test func analyzeWithZeroSamplesUsesImpliedRate() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 50, resetsAt: resetsAt)

        let analysis = UsageHistory.analyze(entry: entry, samples: [], now: now)

        // consumptionRate = 50/14400 (implied from API data alone, no polling history)
        // rateSource is .implied (computeRate uses resetsAt, not samples)
        #expect(analysis.rateSource == .implied)
        #expect(analysis.samples.isEmpty)
        #expect(analysis.segments.isEmpty) // segmentSamples([]) = []
        #expect(analysis.timeSinceLastChange == nil) // no samples → nil
    }

    // One sample → segments contains just that sample; timeSinceLastChange is non-nil.
    @Test func analyzeWithOneSample() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 40, resetsAt: resetsAt)
        // Single sample matches current utilization
        let sample = UtilizationSample(utilization: 40, timestamp: now.addingTimeInterval(-300))

        let analysis = UsageHistory.analyze(entry: entry, samples: [sample], now: now)

        #expect(analysis.samples.count == 1)
        #expect(analysis.rateSource == .implied)
        // timeSinceLastChange: one sample with same utilization → time since that sample = 300s
        #expect(analysis.timeSinceLastChange != nil)
        #expect(abs(analysis.timeSinceLastChange! - 300) < 1)
    }

    // Clear upward trend: util=40, window=5h, elapsed=14400s, remaining=3600s
    // rate = 40/14400 ≈ 0.002778/s
    // projected = 40 + 0.002778*3600 ≈ 50 → well below limit
    @Test func analyzeUpwardTrendBelowLimit() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600) // 1h remaining
        let entry = WindowEntry.make(key: "five_hour", utilization: 40, resetsAt: resetsAt)
        // 6 samples rising 0→40 over 2400s (40min) before now
        let samples = (0..<6).map { i in
            UtilizationSample(utilization: i * 8, timestamp: now.addingTimeInterval(Double(i) * 480 - 2400))
        }

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.rateSource == .implied)
        // rate = 40 / 14400 ≈ 0.002778
        let expectedRate = 40.0 / 14400.0
        #expect(abs(analysis.consumptionRate - expectedRate) < 0.0001)
        // projected ≈ 50 → below 80% bold threshold → normal style
        #expect(abs(analysis.projectedAtReset - 50.0) < 0.1)
        #expect(analysis.timeToLimit == nil)
        #expect(analysis.style.level == .normal)
        #expect(!analysis.style.isBold)
    }

    // Critical projection (≥120%): util=65, window=5h, 9000s remaining (50% of window)
    // elapsed=9000, rate=65/9000≈0.007222, projected=65+0.007222*9000=130 → critical, bold
    @Test func analyzeUpwardTrendCriticalProjection() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(9000)
        let entry = WindowEntry.make(key: "five_hour", utilization: 65, resetsAt: resetsAt)
        let samples = (0..<4).map { i in
            UtilizationSample(utilization: 20 + i * 15, timestamp: now.addingTimeInterval(Double(i) * 1000 - 3000))
        }

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        // rate = 65/9000; projected = 65 + (65/9000)*9000 = 130
        #expect(analysis.projectedAtReset > 120)
        #expect(analysis.style.level == .critical)
        #expect(analysis.style.isBold)
        // timeToLimit: TTL = (100-65)/(65/9000) = 35*9000/65 ≈ 4846s < 9000s → set
        #expect(analysis.timeToLimit != nil)
    }

    // Flat utilization (no change): projected = current utilization, no timeToLimit.
    // util=20, window=5h, remaining=9000s (elapsed=9000)
    // rate=20/9000≈0.002222, projected=20+0.002222*9000=40 → normal
    @Test func analyzeWithFlatSamples() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(9000)
        let entry = WindowEntry.make(key: "five_hour", utilization: 20, resetsAt: resetsAt)
        // All samples at 20% — timeSinceLastChange spans full sample range
        let span: TimeInterval = 3600
        let samples = (0..<5).map { i in
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-span + Double(i) * 900))
        }

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        // rate = 20/9000; projected = 20 + (20/9000)*9000 = 40
        #expect(abs(analysis.projectedAtReset - 40.0) < 0.1)
        // timeSinceLastChange: all same → time since first sample = 3600s
        #expect(analysis.timeSinceLastChange != nil)
        #expect(abs(analysis.timeSinceLastChange! - 3600) < 1)
        #expect(analysis.timeToLimit == nil)
    }

    // Blocked (utilization=100): always critical regardless of projection.
    @Test func analyzeBlockedUtilizationAlwaysCritical() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 100, resetsAt: resetsAt)
        let samples = [UtilizationSample(utilization: 100, timestamp: now.addingTimeInterval(-300))]

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.style.level == .critical)
        #expect(analysis.style.isBold)
        // project() skips timeToLimit when currentUtilization >= 100
        #expect(analysis.timeToLimit == nil)
    }

    // Samples spanning a gap (> 300s between two samples) → segments include a gap segment,
    // and analysis still computes rate from the entry's resetsAt (not from samples).
    @Test func analyzeWithGapInSamples() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 50, resetsAt: resetsAt)
        // s1→s2: 60s (no gap), s2→s3: 600s (gap), s3→s4: 60s (no gap)
        let s1 = UtilizationSample(utilization: 10, timestamp: now.addingTimeInterval(-780))
        let s2 = UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-720))
        let s3 = UtilizationSample(utilization: 40, timestamp: now.addingTimeInterval(-120))  // 600s after s2
        let s4 = UtilizationSample(utilization: 50, timestamp: now.addingTimeInterval(-60))

        let analysis = UsageHistory.analyze(entry: entry, samples: [s1, s2, s3, s4], now: now)

        // Gap segment should appear between s2 and s3
        let gapSegments = analysis.segments.filter { $0.kind == .gap }
        #expect(gapSegments.count == 1)
        #expect(gapSegments[0].samples[0].utilization == 20)
        #expect(gapSegments[0].samples[1].utilization == 40)

        // Rate still computed from resetsAt: rate = 50/14400
        let expectedRate = 50.0 / 14400.0
        #expect(abs(analysis.consumptionRate - expectedRate) < 0.0001)
    }

    // No resetsAt → rate source is .insufficient, projected = current utilization (rate=0).
    @Test func analyzeWithNoResetsAtIsInsufficient() {
        let now = Date()
        let entry = WindowEntry.make(key: "five_hour", utilization: 60, resetsAt: nil)
        let samples = [UtilizationSample(utilization: 60, timestamp: now.addingTimeInterval(-300))]

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.rateSource == .insufficient)
        #expect(analysis.consumptionRate == 0)
        // projected = util + 0 * timeRemaining = 60 → projected = 60
        // With resetsAt=nil, timeRemaining = max(0, now - now) = 0
        #expect(abs(analysis.projectedAtReset - 60.0) < 0.1)
    }

    // Window about to reset (very small timeRemaining) → style is always normal
    // regardless of projected value (special case: timeRemaining=0 → normal).
    @Test func analyzeWindowAboutToResetIsAlwaysNormal() {
        let now = Date()
        // resetsAt = now → timeRemaining = 0
        let resetsAt = now
        let entry = WindowEntry.make(key: "five_hour", utilization: 90, resetsAt: resetsAt)
        let samples = [UtilizationSample(utilization: 90, timestamp: now.addingTimeInterval(-300))]

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        // timeRemaining = 0 → style is normal regardless of utilization
        #expect(analysis.style.level == .normal)
        #expect(!analysis.style.isBold)
    }
}
