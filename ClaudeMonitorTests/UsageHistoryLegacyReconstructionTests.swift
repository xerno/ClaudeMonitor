import Foundation
import Testing
@testable import ClaudeMonitor

/// Instances with samples but no persisted `resetsAt` (legacy/restored data). The first test
/// mirrors a real damaged 5-hour history: 68 samples over ~3h, all in the running window.
@Suite struct UsageHistoryLegacyReconstructionTests {

    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    @Test @MainActor func allSamplesInsideCurrentWindowAreRetainedWithNoArchive() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let identity = "18000" // five_hour, no model scope
        let samples = makeSamples(count: 68, startUtilization: 0, endUtilization: 60, span: 3 * 3600, endDate: base)
        history.storage[identity] = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: samples.first!.timestamp, samples: samples, events: []
        )

        // windowStart (newResetsAt - 5h) lands 1s before the first sample.
        let newResetsAt = samples.first!.timestamp.addingTimeInterval(18000 - 1)
        let entry = makeEntry(key: "five_hour", utilization: 60, resetsAt: newResetsAt)

        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt)

        #expect(!didReset, "Nothing precedes windowStart, so this must not be reported as a boundary.")
        #expect(history.storage[identity]?.samples.count == 68, "All samples retained.")
        #expect(history.storage[identity]?.resetsAt == newResetsAt, "resetsAt adopted.")
        #expect(history.storage[identity]?.firstObservedAt == samples.first!.timestamp,
                "firstObservedAt is the earliest retained sample.")

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(archiveFiles.isEmpty, "No archive file must be created when nothing precedes windowStart.")
    }

    @Test @MainActor func samplesStraddlingBoundaryArchiveOnlyThosePrecedingWindowStart() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let identity = "18000"
        let duration: TimeInterval = 18000

        var samples: [UtilizationSample] = []
        for i in 0..<10 {
            samples.append(UtilizationSample(utilization: i * 5, timestamp: base.addingTimeInterval(TimeInterval(-9 + i) * 3600)))
        }
        history.storage[identity] = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: samples.first!.timestamp, samples: samples, events: []
        )

        // windowStart (t-4.5h) falls between sample[4] (t-5h) and sample[5] (t-4h).
        let windowStart = base.addingTimeInterval(-4.5 * 3600)
        let newResetsAt = windowStart.addingTimeInterval(duration)
        let entry = makeEntry(key: "five_hour", utilization: 45, resetsAt: newResetsAt)

        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt)

        #expect(didReset)
        #expect(history.storage[identity]?.samples.count == 5, "Exactly the post-windowStart samples are retained.")
        #expect(history.storage[identity]?.samples.map(\.utilization) == [25, 30, 35, 40, 45])
        #expect(history.storage[identity]?.resetsAt == newResetsAt)

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.samples.count == 5, "Exactly the pre-windowStart samples were archived.")
        #expect(decoded.samples.map(\.utilization) == [0, 5, 10, 15, 20])
        #expect(decoded.samples.last?.timestamp == samples[4].timestamp, "Archive span ends at the last pre-boundary sample.")
        #expect(decoded.resetsAt == windowStart, "Archived window's end is approximated by windowStart, not `now` or a fabricated value.")
    }

    @Test @MainActor func allSamplesBeforeCurrentWindowAreArchivedAndCurrentStartsEmpty() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let identity = "18000"
        let duration: TimeInterval = 18000

        var samples: [UtilizationSample] = []
        for i in 0..<5 {
            samples.append(UtilizationSample(utilization: 50 + i, timestamp: base.addingTimeInterval(TimeInterval(-10 + i) * 3600)))
        }
        history.storage[identity] = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: samples.first!.timestamp, samples: samples, events: []
        )

        // windowStart = base, after every sample.
        let newResetsAt = base.addingTimeInterval(duration)
        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt)

        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt)

        #expect(didReset)
        #expect(history.storage[identity]?.samples.isEmpty == true, "Current instance legitimately starts fresh.")
        #expect(history.storage[identity]?.resetsAt == newResetsAt)

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.samples.count == 5, "All 5 samples archived.")
    }

    @Test @MainActor func eventsStraddlingWindowStartArePartitionedLikeSamples() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let identity = "18000"
        let duration: TimeInterval = 18000

        var samples: [UtilizationSample] = []
        for i in 0..<10 {
            samples.append(UtilizationSample(utilization: i * 5, timestamp: base.addingTimeInterval(TimeInterval(-9 + i) * 3600)))
        }
        let priorEvent = UsageEvent(at: base.addingTimeInterval(-7 * 3600), kind: .credit, from: 20, to: 10, fromTimestamp: base.addingTimeInterval(-8 * 3600))
        let currentEvent = UsageEvent(at: base.addingTimeInterval(-2 * 3600), kind: .credit, from: 40, to: 30, fromTimestamp: base.addingTimeInterval(-3 * 3600))
        history.storage[identity] = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: samples.first!.timestamp, samples: samples, events: [priorEvent, currentEvent]
        )

        let windowStart = base.addingTimeInterval(-4.5 * 3600)
        let newResetsAt = windowStart.addingTimeInterval(duration)
        let entry = makeEntry(key: "five_hour", utilization: 45, resetsAt: newResetsAt)

        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt)

        #expect(didReset)
        #expect(history.storage[identity]?.events == [currentEvent],
                "Only the post-windowStart event is retained in the current instance.")

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.events == [priorEvent],
                "The pre-windowStart event is archived alongside the pre-windowStart samples, not dropped.")
    }
}
