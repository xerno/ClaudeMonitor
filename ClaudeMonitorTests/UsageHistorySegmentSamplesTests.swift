import Foundation
import Testing
@testable import ClaudeMonitor

@Suite @MainActor struct SegmentSamplesTests {

    @Test func emptySamplesReturnsEmpty() {
        let now = Date()
        let result = UsageHistory.segmentSamples([], windowStart: now.addingTimeInterval(-3600))
        #expect(result.isEmpty)
    }

    @Test func singleSampleProducesInferredThenTracked() {
        let now = Date()
        let windowStart = now.addingTimeInterval(-3600)
        let sample = UtilizationSample(utilization: 50, timestamp: now)
        let result = UsageHistory.segmentSamples([sample], windowStart: windowStart)

        #expect(result.count == 2)
        #expect(result[0].kind == .inferred)
        #expect(result[0].samples.count == 2)
        #expect(result[0].samples[0].utilization == 0)
        #expect(result[0].samples[1].utilization == 50)
        #expect(result[1].kind == .tracked)
        #expect(result[1].samples.count == 1)
        #expect(result[1].samples[0].utilization == 50)
    }

    @Test func allSamplesWithinGapThresholdProduceSingleTrackedSegment() {
        let now = Date()
        let windowStart = now.addingTimeInterval(-50)
        let samples = [
            UtilizationSample(utilization: 10, timestamp: now),
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(60)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(120)),
            UtilizationSample(utilization: 40, timestamp: now.addingTimeInterval(180)),
        ]
        let result = UsageHistory.segmentSamples(samples, windowStart: windowStart)

        let tracked = result.filter { $0.kind == .tracked }
        let inferred = result.filter { $0.kind == .inferred }
        let gaps = result.filter { $0.kind == .gap }

        #expect(inferred.isEmpty)
        #expect(gaps.isEmpty)
        #expect(tracked.count == 1)
        #expect(tracked[0].samples.count == 4)
    }

    @Test func multipleConsecutiveGapsProduceMultipleGapSegments() {
        let now = Date()
        let windowStart = now.addingTimeInterval(-50)

        let g1s1 = UtilizationSample(utilization: 10, timestamp: now)
        let g1s2 = UtilizationSample(utilization: 15, timestamp: now.addingTimeInterval(60))

        let gap1 = TimeInterval(600)
        let g2Start = now.addingTimeInterval(60 + gap1)
        let g2s1 = UtilizationSample(utilization: 20, timestamp: g2Start)
        let g2s2 = UtilizationSample(utilization: 25, timestamp: g2Start.addingTimeInterval(60))

        let gap2 = TimeInterval(600)
        let g3Start = g2Start.addingTimeInterval(60 + gap2)
        let g3s1 = UtilizationSample(utilization: 30, timestamp: g3Start)
        let g3s2 = UtilizationSample(utilization: 35, timestamp: g3Start.addingTimeInterval(60))

        let samples = [g1s1, g1s2, g2s1, g2s2, g3s1, g3s2]
        let result = UsageHistory.segmentSamples(samples, windowStart: windowStart)

        let trackedSegments = result.filter { $0.kind == .tracked }
        let gapSegments = result.filter { $0.kind == .gap }

        #expect(trackedSegments.count == 3)
        #expect(gapSegments.count == 2)

        for gapSeg in gapSegments {
            #expect(gapSeg.samples.count == 2)
            let duration = gapSeg.samples[1].timestamp.timeIntervalSince(gapSeg.samples[0].timestamp)
            #expect(duration > Constants.History.gapThreshold)
        }

        #expect(trackedSegments[0].samples.count == 2)
        #expect(trackedSegments[1].samples.count == 2)
        #expect(trackedSegments[2].samples.count == 2)
    }
}
