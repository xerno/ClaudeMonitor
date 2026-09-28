import Foundation
import Testing
@testable import ClaudeMonitor

// Server lag at a real reset: the API drops utilization to 0 one poll before it advances
// `resets_at`. The drop must not survive as a credit, and the 0% sample belongs to the new window.
@Suite struct UsageHistoryBoundaryLagTests {

    private let identity = "18000" // storageIdentity for "five_hour"
    private let duration: TimeInterval = 18000

    @Test @MainActor func serverLagAtBoundaryPartitionsSamplesAndDropsStraddlingCredit() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let stored = Date(timeIntervalSince1970: 1_786_984_799)
        let tPeak = stored.addingTimeInterval(-2)
        let tAfter = stored.addingTimeInterval(2)

        // record() already logged the 80 -> 0 drop as a credit while resets_at was still `stored`.
        history.storage[identity] = WindowInstance(
            id: UUID(),
            storageIdentity: identity,
            resetsAt: stored,
            firstObservedAt: stored.addingTimeInterval(-3600),
            samples: [
                UtilizationSample(utilization: 30, timestamp: stored.addingTimeInterval(-1800)),
                UtilizationSample(utilization: 80, timestamp: tPeak),
                UtilizationSample(utilization: 0, timestamp: tAfter),
            ],
            events: [
                UsageEvent(at: tAfter, kind: .credit, from: 80, to: 0, fromTimestamp: tPeak),
            ]
        )

        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: stored.addingTimeInterval(duration))
        let newResetsAt = stored.addingTimeInterval(duration)
        let now = tAfter.addingTimeInterval(55)
        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: now)
        #expect(didReset)

        let newInstance = history.storage[identity]
        #expect(newInstance?.samples.map(\.utilization) == [0])
        #expect(newInstance?.samples.first?.timestamp == tAfter)
        #expect(newInstance?.firstObservedAt == tAfter)
        #expect(newInstance?.events.isEmpty == true)

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.samples.map(\.utilization) == [30, 80])
        #expect(decoded.samples.last?.utilization == 80)
        #expect(decoded.events.isEmpty, "The 80 -> 0 drop spans the boundary and must not survive as a credit event.")
    }

    @Test @MainActor func genuineMidWindowCreditWithUnchangedResetsAtStillReported() async {
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
        let didReset = await history.detectAndHandleReset(entry: e3, newResetsAt: resetsAt)

        #expect(didReset == false)
        let instance = history.storage[identity]
        #expect(instance?.samples.map(\.utilization) == [30, 32, 0])
        #expect(instance?.events == [UsageEvent(at: t3, kind: .credit, from: 32, to: 0, fromTimestamp: t2)])

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(archiveFiles.isEmpty, "A mid-window credit must never produce an archive.")
    }

    @Test @MainActor func boundaryInstantInclusivitySemantics() async throws {
        // A sample at exactly `stored` belongs to the new instance; only samples strictly before it are archived.
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let stored = Date(timeIntervalSince1970: 1_786_984_799)
        let tBefore = stored.addingTimeInterval(-1)
        let tAt = stored

        history.storage[identity] = WindowInstance(
            id: UUID(),
            storageIdentity: identity,
            resetsAt: stored,
            firstObservedAt: stored.addingTimeInterval(-3600),
            samples: [
                UtilizationSample(utilization: 79, timestamp: tBefore),
                UtilizationSample(utilization: 0, timestamp: tAt),
            ],
            events: []
        )

        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: stored.addingTimeInterval(duration))
        let newResetsAt = stored.addingTimeInterval(duration)
        let now = tAt.addingTimeInterval(55)
        _ = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: now)

        let newInstance = history.storage[identity]
        #expect(newInstance?.samples.map(\.utilization) == [0])
        #expect(newInstance?.samples.first?.timestamp == tAt)

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.samples.map(\.utilization) == [79])
    }

    @Test @MainActor func duplicateSampleValuesDoNotMisassociateAnEvent() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let stored = Date(timeIntervalSince1970: 1_786_984_799)
        let t0 = stored.addingTimeInterval(-500)
        let tFrom = stored.addingTimeInterval(100)
        let tTo = stored.addingTimeInterval(200)

        let event = UsageEvent(at: tTo, kind: .credit, from: 50, to: 0, fromTimestamp: tFrom)
        history.storage[identity] = WindowInstance(
            id: UUID(),
            storageIdentity: identity,
            resetsAt: stored,
            firstObservedAt: t0,
            samples: [
                UtilizationSample(utilization: 99, timestamp: t0),
                UtilizationSample(utilization: 0, timestamp: tTo),                       // decoy duplicate
                UtilizationSample(utilization: 50, timestamp: stored.addingTimeInterval(50)),
                UtilizationSample(utilization: 50, timestamp: tFrom),
                UtilizationSample(utilization: 0, timestamp: tTo),                       // true landing sample
            ],
            events: [event]
        )

        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: stored.addingTimeInterval(duration))
        let newResetsAt = stored.addingTimeInterval(duration)
        let now = tTo.addingTimeInterval(55)
        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: now)

        #expect(didReset)
        // tFrom and tTo are both at/after `stored`; resolving the decoy (preceded by `t0`) would read as a straddle.
        #expect(history.storage[identity]?.events == [event],
                "The duplicate sample must not cause this genuine current-window credit to be misclassified or dropped.")
    }

    @Test @MainActor func legacyEventWithUnknownOriginIsPartitionedByAtAloneAtABoundary() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let stored = Date(timeIntervalSince1970: 1_786_984_799)
        let tBefore = stored.addingTimeInterval(-1800)
        let tAfter = stored.addingTimeInterval(2)

        let legacyEvent = UsageEvent(at: tAfter, kind: .credit, from: 80, to: 0, fromTimestamp: nil)

        history.storage[identity] = WindowInstance(
            id: UUID(),
            storageIdentity: identity,
            resetsAt: stored,
            firstObservedAt: tBefore,
            samples: [
                UtilizationSample(utilization: 30, timestamp: tBefore),
                UtilizationSample(utilization: 0, timestamp: tAfter),
            ],
            events: [legacyEvent]
        )

        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: stored.addingTimeInterval(duration))
        let newResetsAt = stored.addingTimeInterval(duration)
        let now = tAfter.addingTimeInterval(55)
        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: now)

        #expect(didReset)
        #expect(history.storage[identity]?.events == [legacyEvent],
                "A legacy event with unknown origin, whose `at` lands at/after the boundary, must be retained in the current partition, not dropped.")

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.events.isEmpty,
                "The event's `at` is at/after the boundary, so it must not end up in the archived (prior) partition.")
    }

    @Test @MainActor func legacyEventWithUnknownOriginBeforeBoundaryIsArchived() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let stored = Date(timeIntervalSince1970: 1_786_984_799)
        let tBefore = stored.addingTimeInterval(-1800)
        let tEvent = stored.addingTimeInterval(-5)
        let tAfter = stored.addingTimeInterval(2)

        let legacyEvent = UsageEvent(at: tEvent, kind: .credit, from: 80, to: 30, fromTimestamp: nil)

        history.storage[identity] = WindowInstance(
            id: UUID(),
            storageIdentity: identity,
            resetsAt: stored,
            firstObservedAt: tBefore,
            samples: [
                UtilizationSample(utilization: 80, timestamp: tBefore),
                UtilizationSample(utilization: 30, timestamp: tEvent),
                UtilizationSample(utilization: 0, timestamp: tAfter),
            ],
            events: [legacyEvent]
        )

        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: stored.addingTimeInterval(duration))
        let newResetsAt = stored.addingTimeInterval(duration)
        let now = tAfter.addingTimeInterval(55)
        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: now)

        #expect(didReset)
        #expect(history.storage[identity]?.events.isEmpty == true,
                "The event's `at` is before the boundary, so it must not survive in the current partition.")

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.events == [legacyEvent],
                "A legacy event with unknown origin whose `at` precedes the boundary must be archived, not dropped.")
    }

    // MARK: - A dedup-skipped observation must not stale-date a credit event's origin

    @Test @MainActor func dedupSkippedObservationDoesNotStaleDateACreditAcrossABoundary() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let stored = Date(timeIntervalSince1970: 1_786_984_799)
        let t1 = stored.addingTimeInterval(-20)
        let t2 = stored.addingTimeInterval(5)   // deduped: within Constants.History.deduplicationInterval of t1, never appended
        let t3 = stored.addingTimeInterval(40)

        let e1 = makeEntry(key: "five_hour", utilization: 50, resetsAt: stored)
        let e2 = makeEntry(key: "five_hour", utilization: 50, resetsAt: stored)
        let e3 = makeEntry(key: "five_hour", utilization: 30, resetsAt: stored)

        history.record(entries: [e1], at: t1)
        history.record(entries: [e2], at: t2)
        history.record(entries: [e3], at: t3)

        #expect(history.samples(for: e3).map(\.timestamp) == [t1, t3])

        let recordedEvents = history.storage[identity]?.events ?? []
        #expect(recordedEvents.count == 1)
        #expect(recordedEvents.first?.fromTimestamp == t2,
                "fromTimestamp must be the true most-recent same-value observation (t2), not the stale array-last timestamp (t1) that a deduped poll leaves behind.")

        let newResetsAt = stored.addingTimeInterval(duration)
        let entry = makeEntry(key: "five_hour", utilization: 30, resetsAt: newResetsAt)
        let now = t3.addingTimeInterval(60)
        let didReset = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: now)

        #expect(didReset)
        #expect(history.storage[identity]?.events == recordedEvents,
                "The event must survive in the current partition, not be wrongly dropped as a false straddle.")

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.events.isEmpty, "The event must not end up archived either — it belongs entirely to the current window.")
    }

    // MARK: - A straddling event against a derived boundary is kept, not dropped

    @Test @MainActor func legacyReconstructionKeepsStraddlingEventAssignedByAtRatherThanDropping() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let windowStart = Date(timeIntervalSince1970: 1_786_984_799)
        let newResetsAt = windowStart.addingTimeInterval(duration)

        let tBeforeSample = windowStart.addingTimeInterval(-1800)
        let tAfterSample = windowStart.addingTimeInterval(1800)
        let tFrom = windowStart.addingTimeInterval(-10)
        let tTo = windowStart.addingTimeInterval(10)

        let straddlingEvent = UsageEvent(at: tTo, kind: .credit, from: 80, to: 30, fromTimestamp: tFrom)

        // resetsAt nil selects the legacy-reconstruction branch, whose boundary is derived, not observed.
        history.storage[identity] = WindowInstance(
            id: UUID(),
            storageIdentity: identity,
            resetsAt: nil,
            firstObservedAt: tBeforeSample,
            samples: [
                UtilizationSample(utilization: 80, timestamp: tBeforeSample),
                UtilizationSample(utilization: 30, timestamp: tAfterSample),
            ],
            events: [straddlingEvent]
        )

        let entry = makeEntry(key: "five_hour", utilization: 30, resetsAt: newResetsAt)
        let now = tAfterSample.addingTimeInterval(60)
        _ = await history.detectAndHandleReset(entry: entry, newResetsAt: newResetsAt, at: now)

        #expect(history.storage[identity]?.events == [straddlingEvent],
                "A straddling event against a DERIVED (legacy-reconstruction) boundary must be kept, not discarded — the boundary itself is unproven.")

        let archiveDir = history.archiveDirectory.appendingPathComponent(identity)
        let archiveFiles = try FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        #expect(archiveFiles.count == 1)
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: archiveFiles[0]))
        #expect(decoded.events.isEmpty, "The event lands in CURRENT (by `at`), so it must not also appear archived.")
    }
}
