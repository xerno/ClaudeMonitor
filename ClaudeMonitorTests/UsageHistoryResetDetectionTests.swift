import Foundation
import Testing
@testable import ClaudeMonitor

@Suite struct ResetDetectionTests {

    // MARK: - Task 1: genuine boundary requires BOTH a forward move AND that the old
    // reset moment has actually passed.

    @Test @MainActor func forwardMoveWithNowPastStoredIsGenuineBoundaryAndArchives() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)
        history.record(entries: [entry], at: now)
        #expect(history.samples(for: entry).count == 1)

        let newResetsAt = resetsAt.addingTimeInterval(300)
        let didReset = await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt),
            newResetsAt: newResetsAt,
            at: resetsAt.addingTimeInterval(10)
        )
        #expect(didReset)
        #expect(history.samples(for: makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt)).isEmpty)
    }

    @Test @MainActor func forwardMoveWithNowBeforeStoredIsDriftNotABoundary() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)
        history.record(entries: [entry], at: now)

        let newResetsAt = resetsAt.addingTimeInterval(300)
        let didReset = await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 42, resetsAt: newResetsAt),
            newResetsAt: newResetsAt,
            at: now
        )
        #expect(!didReset)
        #expect(history.samples(for: entry).count == 1)
        #expect(history.storage[entry.storageIdentity]?.resetsAt == newResetsAt)
    }

    @Test @MainActor func jitterWithinToleranceKeepsSameInstance() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)
        history.record(entries: [entry], at: now)

        let newResetsAt = resetsAt.addingTimeInterval(30)
        let didReset = await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 42, resetsAt: newResetsAt),
            newResetsAt: newResetsAt
        )
        #expect(!didReset)
        #expect(history.samples(for: entry).count == 1)
    }

    @Test @MainActor func backwardMoveKeepsSameInstanceAndNeverArchives() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)
        history.record(entries: [entry], at: now)

        let newResetsAt = resetsAt.addingTimeInterval(-300)
        let didReset = await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 42, resetsAt: newResetsAt),
            newResetsAt: newResetsAt
        )
        #expect(!didReset)
        #expect(history.samples(for: entry).count == 1)
    }

    @Test @MainActor func nilResetsAtDoesNotClearOrChangeStoredResetsAt() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: nil)
        history.record(entries: [entry], at: now)

        let didReset = await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 0, resetsAt: nil),
            newResetsAt: nil
        )
        #expect(!didReset)
        #expect(history.samples(for: entry).count == 1)
    }

    // MARK: - Task 2: stored == nil (no persisted boundary state)

    @Test @MainActor func unverifiedNilStoredResetsAtWithEmptySamplesIsAdopted() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: nil)
        history.storage[entry.storageIdentity] = WindowInstance(
            id: UUID(), storageIdentity: entry.storageIdentity, resetsAt: nil,
            firstObservedAt: now, samples: [], events: []
        )

        let newResetsAt = now.addingTimeInterval(3600)
        let didReset = await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 42, resetsAt: newResetsAt),
            newResetsAt: newResetsAt
        )
        #expect(!didReset)
        #expect(history.storage[entry.storageIdentity]?.resetsAt == newResetsAt)
    }

    @Test @MainActor func unverifiedNilStoredResetsAtWithSamplesInsideCurrentWindowIsRetainedNotArchived() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let now = Date()
        let entry = makeEntry(key: "five_hour", utilization: 95, resetsAt: nil)
        history.record(entries: [entry], at: now)
        #expect(history.samples(for: entry).count == 1)

        // windowStart (newResetsAt - 18000) precedes `now`, so the sample lies inside the reconstructed window.
        let newResetsAt = now.addingTimeInterval(3600)
        let didReset = await history.detectAndHandleReset(
            entry: makeEntry(key: "five_hour", utilization: 3, resetsAt: newResetsAt),
            newResetsAt: newResetsAt
        )
        #expect(!didReset, "No prior partition exists, so no archive is written.")
        #expect(history.storage[entry.storageIdentity]?.samples.count == 1)
        #expect(history.storage[entry.storageIdentity]?.samples.first?.utilization == 95)
        #expect(history.storage[entry.storageIdentity]?.resetsAt == newResetsAt)

        let archiveDir = history.archiveDirectory.appendingPathComponent(entry.storageIdentity)
        let archiveFiles = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(archiveFiles.isEmpty, "Nothing precedes windowStart, so nothing is archived.")
    }

    // MARK: - Defect 2: the GENUINE-boundary branch must report `false` when nothing archives

    /// The return value triggers critical-reset detection, so it must be false when nothing is archived.
    @Test @MainActor func genuineBoundaryWithEmptyPriorPartitionArchivesNothingAndReturnsFalse() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let identity = "18000"
        let stored = Date(timeIntervalSince1970: 1_786_984_799)
        // The only sample sits exactly at `stored`, so under `>=` the prior partition is empty.
        history.storage[identity] = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: stored,
            firstObservedAt: stored, samples: [UtilizationSample(utilization: 0, timestamp: stored)], events: []
        )

        let newResetsAt = stored.addingTimeInterval(18000)
        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt)
        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: stored.addingTimeInterval(1))

        #expect(!didReset, "Nothing was archived (the prior partition is empty), so this must not report a genuine boundary.")
        #expect(history.storage[identity]?.samples.count == 1, "The lone sample is retained in the new instance.")
        #expect(history.storage[identity]?.resetsAt == newResetsAt)

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(archiveFiles.isEmpty, "Nothing should be archived when the prior partition is empty.")
    }
}
