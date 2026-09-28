import Foundation
import Testing
@testable import ClaudeMonitor

/// `legacyEventArchiveV2Base64` is the only real file found with a genuine legacy event
/// (`fromTimestamp` absent because it predates the field), so it proves old-code output
/// decodes, beyond encoder/decoder self-consistency.
@Suite struct UsageHistoryRealFixtureTests {

    @Test func realLegacyEventArchiveDecodesSuccessfully() throws {
        let data = try #require(Data(base64Encoded: RealV2Fixtures.legacyEventArchiveV2Base64))
        #expect(data.count == 561, "Sanity check on the exact byte count of the extracted fixture.")

        let decoded = try WindowInstanceCodec.decode(data)

        #expect(decoded.id == UUID(uuidString: "9AB2D39D-D38B-4EF3-8FA5-8FC21BD95748"))
        #expect(decoded.resetsAt == Date(timeIntervalSince1970: 1786984799.729439))
        #expect(decoded.firstObservedAt == Date(timeIntervalSince1970: 1786966819))

        #expect(decoded.events.count == 1)
        let event = try #require(decoded.events.first)
        #expect(event.kind == .credit)
        #expect(event.from == 80)
        #expect(event.to == 0)
        #expect(event.at == Date(timeIntervalSince1970: 1786984801.9382381))
        #expect(event.fromTimestamp == nil, "This is exactly the real legacy event: written before `fromTimestamp` existed.")

        #expect(decoded.samples.count == 145)
        let timestamps = decoded.samples.map(\.timestamp)
        #expect(timestamps == timestamps.sorted(), "Samples must be in non-decreasing timestamp order.")
        #expect(decoded.samples.first?.timestamp == Date(timeIntervalSince1970: 1786966819))
        #expect(decoded.samples.first?.utilization == 30)
        #expect(decoded.samples.last?.timestamp == Date(timeIntervalSince1970: 1786984801))
        #expect(decoded.samples.last?.utilization == 0)
        #expect(decoded.samples.map(\.utilization).max() == 80)
    }

    @Test @MainActor func realLegacyEventIsPartitionedByAtNotDroppedAtAGenuineBoundary() async throws {
        let data = try #require(Data(base64Encoded: RealV2Fixtures.legacyEventArchiveV2Base64))
        let decoded = try WindowInstanceCodec.decode(data)
        let realEvent = try #require(decoded.events.first)
        #expect(realEvent.fromTimestamp == nil)

        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let identity = "18000"
        let stored = try #require(decoded.resetsAt)
        #expect(realEvent.at > stored)

        history.storage[identity] = WindowInstance(
            id: decoded.id,
            storageIdentity: identity,
            resetsAt: stored,
            firstObservedAt: decoded.firstObservedAt,
            samples: [
                UtilizationSample(utilization: 80, timestamp: stored.addingTimeInterval(-60)),
                UtilizationSample(utilization: 0, timestamp: stored.addingTimeInterval(5)),
            ],
            events: [realEvent]
        )

        let duration: TimeInterval = 18000
        let newResetsAt = stored.addingTimeInterval(duration)
        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: newResetsAt)
        let now = stored.addingTimeInterval(65)
        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: now)

        #expect(didReset)
        #expect(history.storage[identity]?.events == [realEvent],
                "The real event must be retained in the current partition (its `at` is after `stored`), never dropped.")

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let archived = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(archived.events.isEmpty, "The event's `at` is after `stored`, so it must not end up archived.")
    }
}
