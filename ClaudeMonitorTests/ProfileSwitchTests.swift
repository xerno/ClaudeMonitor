import Foundation
import Testing
@testable import ClaudeMonitor

@MainActor
@Suite struct ProfileSwitchTests {
    private struct TwoProfileSetup {
        let coordinator: DataCoordinator
        let store: ProfileStore
        let fixture: UsageHistoryTestFixture
        let a: Profile
        let b: Profile
    }

    private func makeTwoProfileSetup(usage: MockUsageService) throws -> TwoProfileSetup {
        let defaults = makeTestDefaults("switch")
        let store = makeTestProfileStore(secrets: InMemorySecrets(), defaults: defaults)
        let a = try store.addProfile(name: "A", organizationId: UUID().uuidString, cookie: "cookie-a")
        let b = try store.addProfile(name: "B", organizationId: UUID().uuidString, cookie: "cookie-b")
        store.setActive(id: a.id)
        let fixture = UsageHistoryTestFixture()
        let coordinator = DataCoordinator(
            statusService: MockStatusService(),
            usageService: usage,
            systemIdleProvider: MockSystemIdleProvider(),
            pathMonitor: MockPathMonitor(),
            profileStore: store,
            defaults: defaults,
            usageHistory: fixture.history
        )
        return TwoProfileSetup(coordinator: coordinator, store: store, fixture: fixture, a: a, b: b)
    }

    @Test func switchUsesNewProfileCredentialsOnNextRefresh() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        await coordinator.refresh()
        #expect(mockUsage.lastOrgId == setup.a.organizationId)
        #expect(mockUsage.lastCookie == "cookie-a")

        coordinator.switchToProfile(id: setup.b.id)
        coordinator.pollTask?.cancel()
        await coordinator.refresh()

        #expect(mockUsage.lastOrgId == setup.b.organizationId)
        #expect(mockUsage.lastCookie == "cookie-b")
    }

    @Test func switchClearsPreviousAccountUsage() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        await coordinator.refresh()
        #expect(coordinator.currentUsage != nil)
        #expect(!coordinator.windowAnalyses.isEmpty)

        coordinator.switchToProfile(id: setup.b.id)
        coordinator.pollTask?.cancel()

        #expect(coordinator.currentUsage == nil)
        #expect(coordinator.windowAnalyses.isEmpty)
    }

    @Test func switchResetsSchedulerSoBackoffDoesNotLeakBetweenAccounts() async throws {
        let mockUsage = MockUsageService()
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        #expect(coordinator.scheduler.isAnyServiceStale,
                "account A must be marked stale after reaching the failure threshold")

        coordinator.switchToProfile(id: setup.b.id)
        #expect(!coordinator.scheduler.isAnyServiceStale,
                "switching accounts must reset the scheduler — A's stale/backoff state must not carry to B")
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
        coordinator.pollTask?.cancel()
    }

    @Test func switchingToActiveProfileIsANoOp() async throws {
        let mockUsage = MockUsageService()
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        #expect(coordinator.scheduler.isAnyServiceStale)
        #expect(coordinator.pollTask == nil)

        coordinator.switchToProfile(id: setup.a.id)

        #expect(coordinator.scheduler.isAnyServiceStale)
        #expect(coordinator.pollTask == nil)
        #expect(setup.store.activeId == setup.a.id)
    }

    @Test func switchingToUnknownProfileIsANoOp() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        await coordinator.refresh()
        coordinator.switchToProfile(id: "does-not-exist")

        #expect(coordinator.pollTask == nil)
        #expect(coordinator.currentUsage != nil)
        #expect(setup.store.activeId == setup.a.id)
    }

    @Test func staleFetchDuringProfileSwitchDoesNotBleed() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        let entryA = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 91, resetsAt: Date().addingTimeInterval(3600))
        )
        mockUsage.result = .success(UsageResponse(entries: [entryA]))

        let fetchStarted = Gate()
        let releaseFetch = Gate()
        mockUsage.beforeReturn = {
            await fetchStarted.open()
            await releaseFetch.wait()
        }

        let refreshTask = Task { await coordinator.refresh() }
        await fetchStarted.wait()

        coordinator.switchToProfile(id: setup.b.id)
        coordinator.pollTask?.cancel()

        await releaseFetch.open()
        await refreshTask.value

        #expect(coordinator.currentUsage == nil)
        #expect(coordinator.windowAnalyses.isEmpty)
        #expect(!setup.fixture.history.samples(for: entryA).contains { $0.utilization == 91 })
    }

    @Test func removingLastProfileClearsCredentials() async throws {
        let mockUsage = MockUsageService()
        let defaults = makeTestDefaults("remove-last")
        let store = makeTestProfileStore(secrets: InMemorySecrets(), defaults: defaults)
        let only = try store.addProfile(name: "Only", organizationId: UUID().uuidString, cookie: "cookie")
        store.setActive(id: only.id)
        let fixture = UsageHistoryTestFixture()
        let coordinator = DataCoordinator(
            statusService: MockStatusService(),
            usageService: mockUsage,
            systemIdleProvider: MockSystemIdleProvider(),
            pathMonitor: MockPathMonitor(),
            profileStore: store,
            defaults: defaults,
            usageHistory: fixture.history
        )
        await coordinator.refresh()
        #expect(coordinator.hasCredentials)
        #expect(coordinator.currentUsage != nil)

        store.removeProfile(id: only.id)
        coordinator.restartPolling()
        coordinator.pollTask?.cancel()

        #expect(!coordinator.hasCredentials)
        #expect(coordinator.loadedCredentials == nil)
        #expect(coordinator.currentUsage == nil)
        #expect(coordinator.windowAnalyses.isEmpty)
    }
}
