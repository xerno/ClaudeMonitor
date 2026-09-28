import Testing
import Foundation
@testable import ClaudeMonitor

// MARK: - SegmentSamplesBehaviorTests
// Default gapThreshold is 300s; a leading "inferred" segment is added when the first sample is > 60s after windowStart.

@Suite @MainActor struct SegmentSamplesBehaviorTests {

    @Test func emptySamplesProducesNoSegments() {
        let windowStart = Date()
        let result = UsageHistory.segmentSamples([], windowStart: windowStart)
        #expect(result.isEmpty)
    }

    @Test func singleSampleLateArrivalProducesInferredPlusTracked() {
        let windowStart = Date()
        let sample = UtilizationSample(utilization: 30, timestamp: windowStart.addingTimeInterval(120))
        let result = UsageHistory.segmentSamples([sample], windowStart: windowStart)

        #expect(result.count == 2)
        #expect(result[0].kind == .inferred)
        #expect(result[1].kind == .tracked)
        #expect(result[0].samples.count == 2)
        #expect(result[0].samples[0].utilization == 0)   // inferred start is always 0%
        #expect(result[0].samples[1].utilization == 30)
        #expect(result[1].samples.count == 1)
        #expect(result[1].samples[0].utilization == 30)
    }

    @Test func singleSampleEarlyArrivalProducesOnlyTracked() {
        let windowStart = Date()
        let sample = UtilizationSample(utilization: 10, timestamp: windowStart.addingTimeInterval(30))
        let result = UsageHistory.segmentSamples([sample], windowStart: windowStart)

        #expect(result.count == 1)
        #expect(result[0].kind == .tracked)
    }

    @Test func continuousSamplesProduceSingleTrackedSegment() {
        let windowStart = Date()
        let samples = (0..<5).map { i in
            UtilizationSample(utilization: i * 10, timestamp: windowStart.addingTimeInterval(Double(i) * 60))
        }

        let result = UsageHistory.segmentSamples(samples, windowStart: windowStart)

        let trackedSegments = result.filter { $0.kind == .tracked }
        let gapSegments     = result.filter { $0.kind == .gap }
        #expect(gapSegments.isEmpty)
        #expect(trackedSegments.count == 1)
        #expect(trackedSegments[0].samples.count == 5)
    }

    @Test func gapAtExactThresholdIsNotDetectedAsGap() {
        let windowStart = Date()
        let s1 = UtilizationSample(utilization: 20, timestamp: windowStart)
        let s2 = UtilizationSample(utilization: 40, timestamp: windowStart.addingTimeInterval(300))
        let result = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart, gapThreshold: 300)

        let gapSegments = result.filter { $0.kind == .gap }
        #expect(gapSegments.isEmpty)
    }

    @Test func gapAboveThresholdProducesGapSegment() {
        let windowStart = Date()
        let s1 = UtilizationSample(utilization: 20, timestamp: windowStart)
        let s2 = UtilizationSample(utilization: 40, timestamp: windowStart.addingTimeInterval(301))

        let result = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart, gapThreshold: 300)

        let gapSegments = result.filter { $0.kind == .gap }
        #expect(gapSegments.count == 1)
        #expect(gapSegments[0].samples[0].utilization == 20)
        #expect(gapSegments[0].samples[1].utilization == 40)
    }

    @Test func multipleGapsProduceMultipleGapAndTrackedSegments() {
        let windowStart = Date()
        // Layout: [s0]—60s—[s1]  —600s gap—  [s2]—60s—[s3]  —900s gap—  [s4]
        let s0 = UtilizationSample(utilization:  5, timestamp: windowStart)
        let s1 = UtilizationSample(utilization: 10, timestamp: windowStart.addingTimeInterval(60))
        let s2 = UtilizationSample(utilization: 15, timestamp: windowStart.addingTimeInterval(660))
        let s3 = UtilizationSample(utilization: 20, timestamp: windowStart.addingTimeInterval(720))
        let s4 = UtilizationSample(utilization: 30, timestamp: windowStart.addingTimeInterval(1620))

        let result = UsageHistory.segmentSamples([s0, s1, s2, s3, s4], windowStart: windowStart)

        let kinds = result.map(\.kind)
        #expect(kinds == [.tracked, .gap, .tracked, .gap, .tracked])

        #expect(result[0].samples.count == 2)
        #expect(result[0].samples[0].utilization == 5)
        #expect(result[0].samples[1].utilization == 10)

        #expect(result[2].samples.count == 2)

        #expect(result[4].samples.count == 1)
        #expect(result[4].samples[0].utilization == 30)
    }

    @Test func inferredSegmentPrecededByLaterGap() {
        let windowStart = Date()
        let s1 = UtilizationSample(utilization: 10, timestamp: windowStart.addingTimeInterval(200))
        let s2 = UtilizationSample(utilization: 25, timestamp: windowStart.addingTimeInterval(800))

        let result = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart)

        let kinds = result.map(\.kind)
        #expect(kinds == [.inferred, .tracked, .gap, .tracked])
        #expect(result[0].samples[0].utilization == 0)
        #expect(result[0].samples[1].utilization == 10)
    }

    @Test func customGapThresholdIsRespected() {
        let windowStart = Date()
        let s1 = UtilizationSample(utilization: 10, timestamp: windowStart)
        let s2 = UtilizationSample(utilization: 20, timestamp: windowStart.addingTimeInterval(100))

        let resultDefault = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart, gapThreshold: 300)
        #expect(resultDefault.filter { $0.kind == .gap }.isEmpty)

        let resultCustom = UsageHistory.segmentSamples([s1, s2], windowStart: windowStart, gapThreshold: 60)
        #expect(resultCustom.filter { $0.kind == .gap }.count == 1)
    }
}

// MARK: - ComputeRateEdgeCaseTests

@Suite @MainActor struct ComputeRateEdgeCaseTests {

    @Test func rateWhenNowIsAfterResetsAt() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-60)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 50,
            resetsAt: resetsAt,
            now: now
        )
        // timeRemaining clamps at 0, so timeElapsed caps at windowDuration.
        #expect(source == .implied)
        let expectedRate = 50.0 / 18000.0
        #expect(abs(rate - expectedRate) < 0.0001)
    }

    @Test func rateAtFullUtilization() {
        let now = Date()
        // elapsed = 18000 - 3600 = 14400s
        let resetsAt = now.addingTimeInterval(3600)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 100,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .implied)
        let expected = 100.0 / 14400.0
        #expect(abs(rate - expected) < 0.0001)
    }

    @Test func insufficientWhenWindowJustStartedNonZeroUtilization() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(18000)
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

@Suite @MainActor struct ProjectEdgeCaseTests {

    @Test func timeToLimitNilWhenLimitNotReachedBeforeReset() {
        // projected = 50 + 0.005*3600 = 68; TTL = 50/0.005 = 10000s > 3600s
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 50,
            rate: 0.005,
            timeRemaining: 3600
        )
        #expect(abs(projected - 68.0) < 0.01)
        #expect(timeToLimit == nil)
    }

    @Test func timeToLimitEqualsTimeRemainingAtBoundary() {
        let rate = 50.0 / 3600.0
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 50,
            rate: rate,
            timeRemaining: 3600
        )
        #expect(abs(projected - 100.0) < 0.01)
        // Inclusive: TTL <= timeRemaining
        #expect(timeToLimit != nil)
        #expect(abs(timeToLimit! - 3600.0) < 0.01)
    }

    @Test func negativeRateProjectsBelow() {
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 50,
            rate: -0.01,
            timeRemaining: 1000
        )
        #expect(abs(projected - 40.0) < 0.01)
        #expect(timeToLimit == nil) // rate not > 0
    }

    @Test func zeroTimeRemainingProjectsCurrentUtilization() {
        let (projected, timeToLimit) = UsageHistory.project(
            currentUtilization: 70,
            rate: 0.1,
            timeRemaining: 0
        )
        #expect(abs(projected - 70.0) < 0.01)
        #expect(timeToLimit == nil)
    }
}

// MARK: - ComputeTimeSinceLastChangeEdgeCaseTests

@Suite @MainActor struct ComputeTimeSinceLastChangeEdgeCaseTests {

    // No sample after the last differing one: the change is "now".
    @Test func lastSampleDiffersWithNoSubsequentSampleReturnsZero() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-600)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-60)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(
            currentUtilization: 45,
            samples: samples,
            now: now
        )
        #expect(result != nil)
        #expect(result! == 0)
    }

    // Age of the first sample holding the current value (sample[1]).
    @Test func changeAtOldestSampleBoundary() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 10, timestamp: now.addingTimeInterval(-300)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-200)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-100)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 30, samples: samples, now: now)
        #expect(result != nil)
        #expect(abs(result! - 200) < 1)
    }

    @Test func allSamplesDifferFromCurrentReturnZero() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 10, timestamp: now.addingTimeInterval(-300)),
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-100)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 50, samples: samples, now: now)
        #expect(result != nil)
        #expect(result! == 0)
    }
}

// MARK: - AnalyzeComprehensiveTests

@Suite @MainActor struct AnalyzeComprehensiveTests {

    @Test func analyzeWithZeroSamplesUsesImpliedRate() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 50, resetsAt: resetsAt)!

        let analysis = UsageHistory.analyze(entry: entry, samples: [], now: now)

        // Rate is implied from resetsAt, not from samples.
        #expect(analysis.rateSource == .implied)
        #expect(analysis.samples.isEmpty)
        #expect(analysis.segments.isEmpty)
        #expect(analysis.timeSinceLastChange == nil)
    }

    @Test func analyzeWithOneSample() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 40, resetsAt: resetsAt)!
        let sample = UtilizationSample(utilization: 40, timestamp: now.addingTimeInterval(-300))

        let analysis = UsageHistory.analyze(entry: entry, samples: [sample], now: now)

        #expect(analysis.samples.count == 1)
        #expect(analysis.rateSource == .implied)
        #expect(analysis.timeSinceLastChange != nil)
        #expect(abs(analysis.timeSinceLastChange! - 300) < 1)
    }

    @Test func analyzeUpwardTrendBelowLimit() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 40, resetsAt: resetsAt)!
        let samples = (0..<6).map { i in
            UtilizationSample(utilization: i * 8, timestamp: now.addingTimeInterval(Double(i) * 480 - 2400))
        }

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.rateSource == .implied)
        let expectedRate = 40.0 / 14400.0
        #expect(abs(analysis.consumptionRate - expectedRate) < 0.0001)
        // projected = 40 + (40/14400)*3600 = 50, below the 80% bold threshold
        #expect(abs(analysis.projectedAtReset - 50.0) < 0.1)
        #expect(analysis.timeToLimit == nil)
        #expect(analysis.style.level == .normal)
        #expect(!analysis.style.isBold)
    }

    @Test func analyzeUpwardTrendCriticalProjection() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(9000)
        let entry = WindowEntry.make(key: "five_hour", utilization: 65, resetsAt: resetsAt)!
        let samples = (0..<4).map { i in
            UtilizationSample(utilization: 20 + i * 15, timestamp: now.addingTimeInterval(Double(i) * 1000 - 3000))
        }

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        // elapsed = 9000, so projected = 65 + (65/9000)*9000 = 130
        #expect(abs(analysis.projectedAtReset - 130.0) < 1.0)
        #expect(analysis.style.level == .critical)
        #expect(analysis.style.isBold)
        // TTL ≈ 4846s < 9000s
        #expect(analysis.timeToLimit != nil)
    }

    @Test func analyzeWithFlatSamples() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(9000)
        let entry = WindowEntry.make(key: "five_hour", utilization: 20, resetsAt: resetsAt)!
        let span: TimeInterval = 3600
        let samples = (0..<5).map { i in
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-span + Double(i) * 900))
        }

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        // Flat samples don't zero the rate (implied from resetsAt): projected = 20 + 20 = 40
        #expect(abs(analysis.projectedAtReset - 40.0) < 0.1)
        #expect(analysis.timeSinceLastChange != nil)
        #expect(abs(analysis.timeSinceLastChange! - 3600) < 1)
        #expect(analysis.timeToLimit == nil)
    }

    @Test func analyzeBlockedUtilizationAlwaysCritical() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 100, resetsAt: resetsAt)!
        let samples = [UtilizationSample(utilization: 100, timestamp: now.addingTimeInterval(-300))]

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.style.level == .critical)
        #expect(analysis.style.isBold)
        // project() skips timeToLimit at utilization >= 100
        #expect(analysis.timeToLimit == nil)
    }

    @Test func analyzeWithGapInSamples() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = WindowEntry.make(key: "five_hour", utilization: 50, resetsAt: resetsAt)!
        // Spacing: s1→s2 60s, s2→s3 600s, s3→s4 60s
        let s1 = UtilizationSample(utilization: 10, timestamp: now.addingTimeInterval(-780))
        let s2 = UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-720))
        let s3 = UtilizationSample(utilization: 40, timestamp: now.addingTimeInterval(-120))
        let s4 = UtilizationSample(utilization: 50, timestamp: now.addingTimeInterval(-60))

        let analysis = UsageHistory.analyze(entry: entry, samples: [s1, s2, s3, s4], now: now)

        let gapSegments = analysis.segments.filter { $0.kind == .gap }
        #expect(gapSegments.count == 1)
        #expect(gapSegments[0].samples[0].utilization == 20)
        #expect(gapSegments[0].samples[1].utilization == 40)

        // Rate still comes from resetsAt, not from samples.
        let expectedRate = 50.0 / 14400.0
        #expect(abs(analysis.consumptionRate - expectedRate) < 0.0001)
    }

    @Test func analyzeWithNoResetsAtIsInsufficient() {
        let now = Date()
        let entry = WindowEntry.make(key: "five_hour", utilization: 60, resetsAt: nil)!
        let samples = [UtilizationSample(utilization: 60, timestamp: now.addingTimeInterval(-300))]

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.rateSource == .insufficient)
        #expect(analysis.consumptionRate == 0)
        #expect(abs(analysis.projectedAtReset - 60.0) < 0.1)
    }

    @Test func analyzeWindowAboutToResetIsAlwaysNormal() {
        let now = Date()
        let resetsAt = now
        let entry = WindowEntry.make(key: "five_hour", utilization: 90, resetsAt: resetsAt)!
        let samples = [UtilizationSample(utilization: 90, timestamp: now.addingTimeInterval(-300))]

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.style.level == .normal)
        #expect(!analysis.style.isBold)
    }
}
