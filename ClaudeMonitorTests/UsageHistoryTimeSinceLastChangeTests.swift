import Foundation
import Testing
@testable import ClaudeMonitor

@Suite @MainActor struct TimeSinceLastChangeTests {

    @Test func timeSinceLastChangeWithRecentChange() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-600)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-300)),
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-60)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 45, samples: samples, now: now)
        #expect(result != nil)
        #expect(abs(result! - 60) < 1)
    }

    @Test func timeSinceLastChangeAllSame() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-1800)),
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-900)),
            UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-60)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 45, samples: samples, now: now)
        #expect(result != nil)
        #expect(abs(result! - 1800) < 1)
    }

    @Test func timeSinceLastChangeNoSamples() {
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 45, samples: [])
        #expect(result == nil)
    }

    @Test func timeSinceLastChangeSingleSample() {
        let now = Date()
        let samples = [UtilizationSample(utilization: 45, timestamp: now.addingTimeInterval(-300))]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 45, samples: samples, now: now)
        #expect(result != nil)
        #expect(abs(result! - 300) < 1)
    }

    @Test func timeSinceLastChangeMultipleChanges() {
        let now = Date()
        let samples = [
            UtilizationSample(utilization: 10, timestamp: now.addingTimeInterval(-600)),
            UtilizationSample(utilization: 20, timestamp: now.addingTimeInterval(-400)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-200)),
            UtilizationSample(utilization: 30, timestamp: now.addingTimeInterval(-60)),
        ]
        let result = UsageHistory.computeTimeSinceLastChange(currentUtilization: 30, samples: samples, now: now)
        #expect(result != nil)
        #expect(abs(result! - 200) < 1)
    }
}
