import Foundation
import Testing
@testable import ClaudeMonitor

/// Calls `applyArchiveReplacement` with a stale generation instead of racing `archiveWindow`
/// against `clearAll()`: the cooperative scheduler does not guarantee that interleaving.
@Suite @MainActor struct UsageHistoryArchiveReentrancyTests {

    @Test func staleGenerationAfterClearAllIsRejected() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let identity = "18000"
        let now = Date()
        let capturedGeneration = history.generation

        await history.clearAll()

        let replacement = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: now, samples: [UtilizationSample(utilization: 0, timestamp: now)], events: []
        )
        let applied = history.applyArchiveReplacement(replacement, forIdentity: identity, capturedGeneration: capturedGeneration)

        #expect(!applied, "A generation captured before clearAll() must never be treated as current afterward.")
        #expect(history.storage[identity] == nil,
                "clearAll() must win: a stale-generation replacement must never resurrect data after storage was deliberately cleared.")
    }

    @Test func staleGenerationAfterSwitchOrganizationIsRejected() throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let firstOrgId = UUID().uuidString
        let secondOrgId = UUID().uuidString
        history.switchOrganization(firstOrgId)

        let identity = "18000"
        let now = Date()
        let capturedGeneration = history.generation

        history.switchOrganization(secondOrgId)

        let replacement = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: now, samples: [UtilizationSample(utilization: 0, timestamp: now)], events: []
        )
        let applied = history.applyArchiveReplacement(replacement, forIdentity: identity, capturedGeneration: capturedGeneration)

        #expect(!applied, "A generation captured before switchOrganization() must never be treated as current afterward.")
        #expect(history.storage[identity] == nil,
                "The first organization's stale-generation replacement must never land in the second organization's storage.")
    }

    @Test func matchingGenerationIsApplied() throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let identity = "18000"
        let now = Date()
        let capturedGeneration = history.generation

        let replacement = WindowInstance(
            id: UUID(), storageIdentity: identity, resetsAt: nil,
            firstObservedAt: now, samples: [UtilizationSample(utilization: 0, timestamp: now)], events: []
        )
        let applied = history.applyArchiveReplacement(replacement, forIdentity: identity, capturedGeneration: capturedGeneration)

        #expect(applied)
        #expect(history.storage[identity] == replacement)
    }
}
