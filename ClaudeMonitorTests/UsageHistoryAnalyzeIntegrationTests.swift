import Foundation
import Testing
@testable import ClaudeMonitor

@Suite struct AnalyzeIntegrationTests {

    @Test @MainActor func analyzeProducesCorrectWindowAnalysis() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(1800)
        let entry = makeEntry(key: "five_hour", utilization: 70, resetsAt: resetsAt)
        let samples = makeSamples(count: 10, startUtilization: 10, endUtilization: 70, span: 600, endDate: now)

        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        #expect(analysis.entry == entry)
        #expect(analysis.rateSource == .implied)
        let expectedRate = 70.0 / 16200.0
        #expect(abs(analysis.consumptionRate - expectedRate) < 0.001)
        let expectedProjected = 70.0 + (70.0 / 16200.0) * 1800.0
        #expect(abs(analysis.projectedAtReset - expectedProjected) < 2.0)
        #expect(analysis.timeToLimit == nil)
    }
}
