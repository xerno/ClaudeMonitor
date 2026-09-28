import Foundation
import Testing
@testable import ClaudeMonitor

// record() never prunes a WindowInstance's samples; only an explicit archive removes them.
@Suite struct WindowInstanceOwnershipTests {

    @Test @MainActor func recordingWithADifferentResetsAtDoesNotDropExistingSamples() async {
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
        #expect(samples.count == 4)
        #expect(samples.map(\.utilization) == [30, 40, 50, 5])
    }

    @Test @MainActor func samplesForEntryReturnsCurrentInstanceUnfiltered() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(1800)
        let t1 = now.addingTimeInterval(-900)
        let t2 = now.addingTimeInterval(-600)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 55, resetsAt: resetsAt)], at: t1)
        history.record(entries: [makeEntry(key: "five_hour", utilization: 60, resetsAt: resetsAt)], at: t2)

        let entry = makeEntry(key: "five_hour", utilization: 60, resetsAt: resetsAt)
        #expect(history.samples(for: entry).count == 2)
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
    }

    // MARK: - Task F regression cases

    @Test @MainActor func midWindowCreditDoesNotSplitOrArchiveTheWindow() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)

        let t1 = now.addingTimeInterval(-600)
        let t2 = now.addingTimeInterval(-300)
        let t3 = now

        let e1 = makeEntry(key: "five_hour", utilization: 30, resetsAt: resetsAt)
        let e2 = makeEntry(key: "five_hour", utilization: 32, resetsAt: resetsAt)
        let e3 = makeEntry(key: "five_hour", utilization: 0, resetsAt: resetsAt)

        history.record(entries: [e1], at: t1)
        await history.detectAndHandleReset(entry: e1, newResetsAt: resetsAt)
        history.record(entries: [e2], at: t2)
        await history.detectAndHandleReset(entry: e2, newResetsAt: resetsAt)
        history.record(entries: [e3], at: t3)
        await history.detectAndHandleReset(entry: e3, newResetsAt: resetsAt)

        let instance = history.storage[e3.storageIdentity]
        #expect(instance != nil)
        #expect(instance?.samples.map(\.utilization) == [30, 32, 0])
        #expect(instance?.events.count == 1)
        #expect(instance?.events.first == UsageEvent(at: t3, kind: .credit, from: 32, to: 0, fromTimestamp: t2))

        let archiveDir = history.archiveDirectory.appendingPathComponent(e3.storageIdentity)
        let lzmaFiles = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(lzmaFiles.isEmpty, "A mid-window credit must never produce an archive")
    }

    @Test @MainActor func nilResetsAtAcrossSeveralPollsNeverMergesOrArchives() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let now = Date()

        for i in 0..<5 {
            let t = now.addingTimeInterval(TimeInterval(i) * 60)
            let entry = makeEntry(key: "five_hour", utilization: 10 + i, resetsAt: nil)
            history.record(entries: [entry], at: t)
            await history.detectAndHandleReset(entry: entry, newResetsAt: nil)
        }

        let entry = makeEntry(key: "five_hour", utilization: 14, resetsAt: nil)
        #expect(history.samples(for: entry).count == 5)
        let archiveDir = history.archiveDirectory.appendingPathComponent(entry.storageIdentity)
        let lzmaFiles = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(lzmaFiles.isEmpty)
    }
}
