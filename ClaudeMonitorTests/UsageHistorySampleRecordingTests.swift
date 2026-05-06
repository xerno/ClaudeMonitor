import Foundation
import Testing
@testable import ClaudeMonitor

@Suite struct SampleRecordingTests {

    @Test @MainActor func recordAddsSample() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)
        let samples = history.samples(for: entry)
        #expect(samples.count == 1)
        #expect(samples[0].utilization == 42)
        await fixture.cleanup()
    }

    @Test @MainActor func recordDeduplicatesSameUtilization() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)
        let soon = now.addingTimeInterval(10)
        let entry2 = makeEntry(key: "five_hour", utilization: 42, resetsAt: soon.addingTimeInterval(3600))
        history.record(entries: [entry2], at: soon)
        let samples = history.samples(for: entry2)
        #expect(samples.count == 1)
        await fixture.cleanup()
    }

    @Test @MainActor func recordAllowsSameUtilizationAfterDeduplicationInterval() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry], at: now)
        let later = now.addingTimeInterval(Constants.History.deduplicationInterval + 1)
        let entry2 = makeEntry(key: "five_hour", utilization: 42, resetsAt: later.addingTimeInterval(3600))
        history.record(entries: [entry2], at: later)
        let samples = history.samples(for: entry2)
        #expect(samples.count == 2)
        await fixture.cleanup()
    }

    @Test @MainActor func recordDifferentUtilizationAlwaysAdded() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let entry1 = makeEntry(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [entry1], at: now)
        let soon = now.addingTimeInterval(10)
        let entry2 = makeEntry(key: "five_hour", utilization: 55, resetsAt: soon.addingTimeInterval(3600))
        history.record(entries: [entry2], at: soon)
        let samples = history.samples(for: entry2)
        #expect(samples.count == 2)
        await fixture.cleanup()
    }

    @Test @MainActor func pruneRemovesOldSamples() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let duration: TimeInterval = 18000
        let now = Date()
        let oldDate = now.addingTimeInterval(-(duration + 100))
        let oldEntry = makeEntry(key: "five_hour", utilization: 10, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [oldEntry], at: oldDate)

        let freshEntry = makeEntry(key: "five_hour", utilization: 20, resetsAt: now.addingTimeInterval(3600))
        history.record(entries: [freshEntry], at: now)

        let samples = history.samples(for: freshEntry)
        #expect(samples.count == 1)
        #expect(samples[0].utilization == 20)
        await fixture.cleanup()
    }
}
