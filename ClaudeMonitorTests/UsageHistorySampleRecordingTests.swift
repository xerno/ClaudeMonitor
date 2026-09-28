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
    }

    @Test @MainActor func recordNeverPrunesOldSamplesByAge() async {
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
        #expect(samples.count == 2)
        #expect(samples.map(\.utilization) == [10, 20])
    }

    @Test @MainActor func recordedEventCarriesPreviousSampleTimestampAsOrigin() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)

        let t1 = now.addingTimeInterval(-600)
        let t2 = now

        let e1 = makeEntry(key: "five_hour", utilization: 50, resetsAt: resetsAt)
        let e2 = makeEntry(key: "five_hour", utilization: 40, resetsAt: resetsAt)

        history.record(entries: [e1], at: t1)
        history.record(entries: [e2], at: t2)

        let samples = history.samples(for: e2)
        #expect(samples.map(\.timestamp) == [t1, t2], "Sanity check: the previous sample really is at t1.")

        let events = history.storage[e2.storageIdentity]?.events ?? []
        #expect(events.count == 1)
        #expect(events.first?.kind == .credit, "A utilization drop must be recorded as a credit event, never a reset.")
        #expect(events.first?.from == 50, "Event must carry the utilization it dropped FROM.")
        #expect(events.first?.to == 40, "Event must carry the utilization it dropped TO.")
        #expect(events.first?.at == t2)
        #expect(events.first?.fromTimestamp == t1, "fromTimestamp must equal the immediately preceding sample's own timestamp.")
    }
}
