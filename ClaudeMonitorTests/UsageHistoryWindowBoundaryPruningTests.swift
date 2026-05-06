import Foundation
import Testing
@testable import ClaudeMonitor

@Suite struct WindowBoundaryPruningTests {

    @Test @MainActor func recordPrunesSamplesFromPreviousWindowAfterReset() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let duration: TimeInterval = 18000
        let oldResetsAt = now.addingTimeInterval(1800)

        let t1 = now.addingTimeInterval(-900)
        let t2 = now.addingTimeInterval(-600)
        let t3 = now.addingTimeInterval(-300)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 30, resetsAt: oldResetsAt)], at: t1)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 40, resetsAt: oldResetsAt)], at: t2)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 50, resetsAt: oldResetsAt)], at: t3)

        let newResetsAt = now.addingTimeInterval(duration)
        let newEntry = makeEntry(key: "five_hour", utilization: 5, resetsAt: newResetsAt)
        history.record(entries: [newEntry], at: now.addingTimeInterval(60))

        let samples = history.samples(for: newEntry)
        #expect(samples.count == 1)
        #expect(samples[0].utilization == 5)
        await fixture.cleanup()
    }

    @Test @MainActor func samplesForEntryFiltersOldWindowData() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let duration: TimeInterval = 18000

        let oldResetsAt = now.addingTimeInterval(1800)
        let oldEntry = makeEntry(key: "five_hour", utilization: 60, resetsAt: oldResetsAt)
        let t1 = now.addingTimeInterval(-900)
        let t2 = now.addingTimeInterval(-600)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 55, resetsAt: oldResetsAt)], at: t1)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 60, resetsAt: oldResetsAt)], at: t2)
        _ = oldEntry

        let newResetsAt = now.addingTimeInterval(duration)
        let newEntry = makeEntry(key: "five_hour", utilization: 60, resetsAt: newResetsAt)
        let samples = history.samples(for: newEntry)
        #expect(samples.isEmpty)
        await fixture.cleanup()
    }

    @Test @MainActor func recordKeepsSamplesWithinCurrentWindow() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)

        let t1 = now.addingTimeInterval(-600)
        let t2 = now.addingTimeInterval(-300)
        let t3 = now

        history.record(entries: [makeEntry(key: "five_hour", utilization: 30, resetsAt: resetsAt)], at: t1)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 40, resetsAt: resetsAt)], at: t2)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 50, resetsAt: resetsAt)], at: t3)

        let entry = makeEntry(key: "five_hour", utilization: 50, resetsAt: resetsAt)
        let samples = history.samples(for: entry)
        #expect(samples.count == 3)
        await fixture.cleanup()
    }
}
