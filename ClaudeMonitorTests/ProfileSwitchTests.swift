import Foundation
import Testing
@testable import ClaudeMonitor

@MainActor
@Suite struct ProfileSwitchTests {
    @MainActor private struct TwoProfileSetup {
        let coordinator: DataCoordinator
        let store: ProfileStore
        let fixture: UsageHistoryTestFixture
        let a: Profile
        let b: Profile

        var monitorA: AccountMonitor? {
            coordinator.monitors[DataCoordinator.monitorKey(organizationId: a.organizationId)]
        }

        var monitorB: AccountMonitor? {
            coordinator.monitors[DataCoordinator.monitorKey(organizationId: b.organizationId)]
        }
    }

    private func makeTwoProfileSetup(
        usage: MockUsageService,
        status: MockStatusService = MockStatusService()
    ) throws -> TwoProfileSetup {
        let defaults = makeTestDefaults("switch")
        let store = makeTestProfileStore(secrets: InMemorySecrets(), defaults: defaults)
        let a = try store.addProfile(name: "A", organizationId: UUID().uuidString, cookie: "cookie-a")
        let b = try store.addProfile(name: "B", organizationId: UUID().uuidString, cookie: "cookie-b")
        store.setActive(id: a.id)
        let fixture = UsageHistoryTestFixture()
        let coordinator = DataCoordinator(
            statusService: status,
            usageService: usage,
            systemIdleProvider: MockSystemIdleProvider(),
            pathMonitor: MockPathMonitor(),
            profileStore: store,
            defaults: defaults,
            makeUsageHistory: { UsageHistory(baseDirectory: fixture.baseDirectory) }
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
        coordinator.stopPolling()
        await coordinator.refresh()

        #expect(mockUsage.lastOrgId == setup.b.organizationId)
        #expect(mockUsage.lastCookie == "cookie-b")
    }

    @Test func switchShowsNewAccountsOwnDataNeverPrevious() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        await coordinator.refresh()
        #expect(coordinator.currentUsage != nil)
        #expect(!coordinator.windowAnalyses.isEmpty)

        coordinator.switchToProfile(id: setup.b.id)
        coordinator.stopPolling()

        #expect(coordinator.currentUsage == nil,
                "B has never fetched yet — it shows its own (nil) data, never A's")
        #expect(coordinator.windowAnalyses.isEmpty)
    }

    @Test func eachAccountSchedulerStaleStateDoesNotLeakToTheOther() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator
        mockUsage.resultsByOrgId[setup.a.organizationId] = .failure(ServiceError.unexpectedStatus(500))

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        let monitorA = try #require(setup.monitorA)
        #expect(monitorA.scheduler.isAnyServiceStale,
                "account A must be marked stale after reaching the failure threshold")

        coordinator.switchToProfile(id: setup.b.id)
        coordinator.stopPolling()

        #expect(!coordinator.monitorState.polling.isAnyServiceStale,
                "switching to B must reflect B's own healthy scheduler and status, not A's stale one")
        #expect(monitorA.scheduler.isAnyServiceStale,
                "A's stale state must persist independently on its own monitor after switching away")
    }

    @Test func switchingToActiveProfileIsANoOp() async throws {
        let mockUsage = MockUsageService()
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        #expect(coordinator.monitorState.polling.isAnyServiceStale)
        #expect(coordinator.activeMonitor?.pollTask == nil)

        coordinator.switchToProfile(id: setup.a.id)

        #expect(coordinator.monitorState.polling.isAnyServiceStale)
        #expect(coordinator.activeMonitor?.pollTask == nil)
        #expect(setup.store.activeId == setup.a.id)
        coordinator.stopPolling()
    }

    @Test func switchingToUnknownProfileIsANoOp() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator

        await coordinator.refresh()
        coordinator.switchToProfile(id: "does-not-exist")

        #expect(coordinator.activeMonitor?.pollTask == nil)
        #expect(coordinator.currentUsage != nil)
        #expect(setup.store.activeId == setup.a.id)
        coordinator.stopPolling()
    }

    @Test func staleFetchDuringProfileSwitchLandsOnlyInItsOwnMonitor() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator
        let monitorA = try #require(setup.monitorA)
        let monitorB = try #require(setup.monitorB)

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
        coordinator.stopPolling()

        await releaseFetch.open()
        await refreshTask.value

        #expect(coordinator.currentUsage == nil,
                "B is active and never fetched — A's late response must not appear under B")
        #expect(coordinator.windowAnalyses.isEmpty)
        #expect(monitorA.currentUsage?.entries.contains { $0.window.utilization == 91 } == true,
                "A's own monitor legitimately records its own (not stale) late response")
        #expect(monitorA.usageHistory.samples(for: entryA).contains { $0.utilization == 91 })
        #expect(!monitorB.usageHistory.samples(for: entryA).contains { $0.utilization == 91 })
    }

    @Test func switchWhileStatusFetchSuspendedDoesNotShowPreviousAccountUnderNewOne() async throws {
        let mockUsage = MockUsageService()
        let mockStatus = MockStatusService()
        let setup = try makeTwoProfileSetup(usage: mockUsage, status: mockStatus)
        let coordinator = setup.coordinator
        let monitorA = try #require(setup.monitorA)
        let monitorB = try #require(setup.monitorB)

        let entryA = WindowEntry(
            key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
            window: UsageWindow(utilization: 91, resetsAt: Date().addingTimeInterval(3600))
        )
        mockUsage.result = .success(UsageResponse(entries: [entryA]))

        let usageFetchReturning = Gate()
        let statusFetchSuspended = Gate()
        let releaseStatusFetch = Gate()
        mockUsage.beforeReturn = {
            await usageFetchReturning.open()
        }
        mockStatus.beforeReturn = {
            await usageFetchReturning.wait()
            await statusFetchSuspended.open()
            await releaseStatusFetch.wait()
        }

        let refreshTask = Task { await coordinator.refresh() }
        await statusFetchSuspended.wait()
        while monitorA.currentUsage == nil {
            await Task.yield()
        }
        #expect(monitorA.currentUsage?.entries.contains { $0.window.utilization == 91 } == true)

        coordinator.switchToProfile(id: setup.b.id)
        coordinator.stopPolling()

        await releaseStatusFetch.open()
        await refreshTask.value

        #expect(monitorA.usageHistory.usageDirectory.lastPathComponent == setup.a.organizationId)
        #expect(monitorA.usageHistory.samples(for: entryA).contains { $0.utilization == 91 })
        #expect(!(coordinator.currentUsage?.entries.contains { $0.window.utilization == 91 } ?? false))
        #expect(!coordinator.windowAnalyses.contains { $0.entry.window.utilization == 91 })
        #expect(!monitorB.usageHistory.samples(for: entryA).contains { $0.utilization == 91 })
        #expect(mockUsage.lastOrgId == setup.a.organizationId)
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
            makeUsageHistory: { fixture.history }
        )
        await coordinator.refresh()
        #expect(coordinator.hasCredentials)
        #expect(coordinator.currentUsage != nil)

        store.removeProfile(id: only.id)
        coordinator.restartPolling()
        coordinator.stopPolling()

        #expect(!coordinator.hasCredentials)
        #expect(coordinator.monitors.isEmpty)
        #expect(coordinator.currentUsage == nil)
        #expect(coordinator.windowAnalyses.isEmpty)
    }

    @Test func switchingShowsBsPreviouslyFetchedDataImmediately() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator
        let monitorA = try #require(setup.monitorA)
        let monitorB = try #require(setup.monitorB)

        mockUsage.resultsByOrgId[setup.a.organizationId] = .success(UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 30, resetsAt: Date().addingTimeInterval(3600))),
        ]))
        mockUsage.resultsByOrgId[setup.b.organizationId] = .success(UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 70, resetsAt: Date().addingTimeInterval(3600))),
        ]))

        await monitorA.refresh()
        await monitorB.refresh()
        #expect(mockUsage.fetchCount == 2)

        coordinator.switchToProfile(id: setup.b.id)
        #expect(coordinator.currentUsage?.entries.first?.window.utilization == 70)
        #expect(coordinator.windowAnalyses.first?.entry.window.utilization == 70)
        coordinator.stopPolling()
    }

    @Test func eachAccountKeepsItsOwnScheduler() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let monitorA = try #require(setup.monitorA)
        let monitorB = try #require(setup.monitorB)
        mockUsage.resultsByOrgId[setup.a.organizationId] = .failure(ServiceError.unexpectedStatus(500))

        for _ in 0..<Constants.Retry.failureThreshold {
            await monitorA.refresh()
        }
        await monitorB.refresh()

        #expect(monitorA.scheduler.isAnyServiceStale)
        #expect(!monitorB.scheduler.isAnyServiceStale)
    }

    @Test func inactiveMonitorUpdatesAreNotForwarded() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator
        let monitorA = try #require(setup.monitorA)
        let monitorB = try #require(setup.monitorB)

        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        monitorB.onUpdate?()
        #expect(updateCount == 0, "B is inactive; its update must not be forwarded")

        monitorA.onUpdate?()
        #expect(updateCount == 1, "A is active; its update must be forwarded")
    }

    @Test func removingAProfileDropsAndStopsItsMonitor() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator
        let monitorB = try #require(setup.monitorB)

        setup.store.removeProfile(id: setup.b.id)
        coordinator.restartPolling()
        coordinator.stopPolling()

        #expect(coordinator.monitors.count == 1)
        #expect(monitorB.pollTask == nil)
    }

    @Test func recreatedMonitorReusesTheOrganizationsHistory() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let coordinator = setup.coordinator
        let monitorB = try #require(setup.monitorB)

        setup.store.removeProfile(id: setup.b.id)
        coordinator.restartPolling()
        _ = try setup.store.addProfile(name: "B again", organizationId: setup.b.organizationId, cookie: "cookie-b")
        coordinator.restartPolling()
        coordinator.stopPolling()

        let recreated = try #require(setup.monitorB)
        #expect(recreated !== monitorB)
        #expect(recreated.usageHistory === monitorB.usageHistory)
    }

    @Test func twoOrgsNeverShareAHistoryInstance() async throws {
        let mockUsage = MockUsageService()
        let setup = try makeTwoProfileSetup(usage: mockUsage)
        let monitorA = try #require(setup.monitorA)
        let monitorB = try #require(setup.monitorB)

        #expect(monitorA.usageHistory !== monitorB.usageHistory)
        #expect(monitorA.usageHistory.usageDirectory.lastPathComponent == setup.a.organizationId)
        #expect(monitorB.usageHistory.usageDirectory.lastPathComponent == setup.b.organizationId)
    }
}
