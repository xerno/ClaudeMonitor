import Foundation
import Testing
@testable import ClaudeMonitor

/// A simulated restart reloads against the real clock, which clamps future values, so fixed dates lie in the past.
@Suite struct UsageHistoryManifestTests {

    private let identity = "18000" // five_hour

    @Test @MainActor func missingWindowSinceSurvivesSimulatedRestart() async throws {
        let fixture = UsageHistoryTestFixture()
        let orgId = UUID().uuidString
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        do {
            let history = fixture.history
            history.switchOrganization(orgId)
            history.storage[identity] = WindowInstance(
                id: UUID(), storageIdentity: identity, resetsAt: nil,
                firstObservedAt: t0, samples: [UtilizationSample(utilization: 5, timestamp: t0)], events: []
            )
            await history.archiveMissingWindows(currentIdentities: [], at: t0)
            #expect(history.missingWindowSince[identity] == t0)
        }

        let restarted = UsageHistory(baseDirectory: fixture.baseDirectory)
        restarted.switchOrganization(orgId)
        #expect(restarted.missingWindowSince[identity] == t0,
                "The missing-since clock must survive a restart, not reset to nil/now.")
    }

    @Test @MainActor func keyReappearingClearsTheMissingSinceEntry() async {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)

        history.storage[identity] = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: t0, samples: [UtilizationSample(utilization: 5, timestamp: t0)], events: []
        )
        await history.archiveMissingWindows(currentIdentities: [], at: t0)
        #expect(history.missingWindowSince[identity] == t0)

        await history.archiveMissingWindows(currentIdentities: [identity], at: t0.addingTimeInterval(10))
        #expect(history.missingWindowSince[identity] == nil, "A reappearing key must clear its missing-since entry.")
    }

    @Test @MainActor func futureDatedStoredValueIsClampedAndDoesNotArchivePrematurely() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let now = Date(timeIntervalSince1970: 1_700_000_000)
        history.storage[identity] = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: now, samples: [UtilizationSample(utilization: 10, timestamp: now)], events: []
        )

        let future = now.addingTimeInterval(999_999)
        let manifest = HistoryManifest(v: Constants.History.manifestVersion, missingWindowSince: [identity: future])
        let data = try #require(UsageHistory.encodeManifest(manifest))
        try FileManager.default.createDirectory(at: history.manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: history.manifestURL)

        history.loadMissingWindowSince(at: now)
        #expect(history.missingWindowSince[identity] == now, "A future timestamp must be clamped down to `now`.")

        await history.archiveMissingWindows(currentIdentities: [], at: now)
        #expect(history.storage[identity] != nil, "Clamped to `now`, elapsed time is 0 — must not archive prematurely.")
        #expect(history.missingWindowSince[identity] == now)
    }

    @Test @MainActor func manifestWithoutMissingWindowSinceFieldLoadsFine() throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let json = Data("{\"v\":1}".utf8)
        try FileManager.default.createDirectory(at: history.manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: history.manifestURL)

        history.loadMissingWindowSince()
        #expect(history.missingWindowSince.isEmpty)
    }

    @Test @MainActor func manifestWithUnrecognizedKeysFieldStillLoadsWithoutWipingData() throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let json = Data("{\"v\":1,\"keys\":{\"five_hour\":\"18000\"}}".utf8)
        try FileManager.default.createDirectory(at: history.manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: history.manifestURL)

        history.loadMissingWindowSince()
        #expect(history.missingWindowSince.isEmpty, "No missingWindowSince field present, so nothing should be populated.")
    }
}
