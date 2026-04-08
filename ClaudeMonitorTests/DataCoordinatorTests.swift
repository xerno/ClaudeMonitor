import Testing
import Foundation
@testable import ClaudeMonitor

private let testStatus = StatusSummary(
    components: [StatusComponent(id: "1", name: "API", status: .operational)],
    incidents: [],
    status: PageStatus(indicator: "none", description: "All Systems Operational")
)

private let testUsage = UsageResponse(entries: [
    WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                window: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(3600))),
    WindowEntry(key: "seven_day", duration: 604_800, durationLabel: "7d", modelScope: nil,
                window: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(86400))),
])

private final class MockStatusService: StatusFetching, @unchecked Sendable {
    var result: Result<StatusSummary, Error> = .success(testStatus)
    var fetchCount = 0

    func fetch() async throws -> StatusSummary {
        fetchCount += 1
        return try result.get()
    }
}

private final class MockUsageService: UsageFetching, @unchecked Sendable {
    var result: Result<UsageResponse, Error> = .success(testUsage)
    var fetchCount = 0
    var lastOrgId: String?
    var lastCookie: String?

    func fetch(organizationId: String, cookieString: String) async throws -> UsageResponse {
        fetchCount += 1
        lastOrgId = organizationId
        lastCookie = cookieString
        return try result.get()
    }
}

@MainActor struct DataCoordinatorTests {
    private let mockStatus = MockStatusService()
    private let mockUsage = MockUsageService()

    private func makeCoordinator(
        credentials: [String: String] = [
            Constants.Keychain.cookieString: "test-cookie",
            Constants.Keychain.organizationId: "test-org-id",
        ]
    ) -> DataCoordinator {
        DataCoordinator(
            statusService: mockStatus,
            usageService: mockUsage,
            loadCredential: { credentials[$0] }
        )
    }

    // MARK: - Successful Fetch

    @Test func refreshUpdatesStateOnSuccess() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(coordinator.currentStatus == testStatus)
        #expect(coordinator.currentUsage == testUsage)
        #expect(coordinator.usageError == nil)
        #expect(coordinator.statusError == nil)
        #expect(coordinator.lastRefreshed != nil)
    }

    @Test func refreshCallsBothServices() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(mockStatus.fetchCount == 1)
        #expect(mockUsage.fetchCount == 1)
    }

    @Test func refreshPassesCredentialsToUsageService() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(mockUsage.lastOrgId == "test-org-id")
        #expect(mockUsage.lastCookie == "test-cookie")
    }

    @Test func refreshCallsOnUpdate() async {
        let coordinator = makeCoordinator()
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()

        #expect(updateCount == 1)
    }

    @Test func refreshRecordsSchedulerSuccess() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(coordinator.scheduler.statusState.lastSuccess != nil)
        #expect(coordinator.scheduler.usageState.lastSuccess != nil)
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 0)
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - No Credentials

    @Test func refreshWithNoCredentialsSetsUsageError() async {
        let coordinator = makeCoordinator(credentials: [:])
        await coordinator.refresh()

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func refreshWithEmptyCredentialsSetsUsageError() async {
        let coordinator = makeCoordinator(credentials: [
            Constants.Keychain.cookieString: "",
            Constants.Keychain.organizationId: "org",
        ])
        await coordinator.refresh()

        #expect(coordinator.usageError == "Configure credentials in Preferences")
        #expect(mockUsage.fetchCount == 0)
    }

    @Test func noCredentialsStillFetchesStatus() async {
        let coordinator = makeCoordinator(credentials: [:])
        await coordinator.refresh()

        #expect(mockStatus.fetchCount == 1)
        #expect(coordinator.currentStatus == testStatus)
    }

    @Test func hasCredentialsReturnsFalseWhenMissing() {
        let coordinator = makeCoordinator(credentials: [:])
        #expect(!coordinator.hasCredentials)
    }

    @Test func hasCredentialsReturnsTrueWhenPresent() {
        let coordinator = makeCoordinator()
        #expect(coordinator.hasCredentials)
    }

    // MARK: - Status Failure

    @Test func statusFailureBelowThresholdDoesNotSetError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()

        await coordinator.refresh()

        #expect(coordinator.statusError == nil)
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 1)
    }

    @Test func statusFailureAtThresholdSetsError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }

        #expect(coordinator.statusError != nil)
    }

    @Test func statusSuccessAfterFailureClearsError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()
        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        #expect(coordinator.statusError != nil)

        mockStatus.result = .success(testStatus)
        await coordinator.refresh()

        #expect(coordinator.statusError == nil)
        #expect(coordinator.currentStatus == testStatus)
    }

    // MARK: - Usage Failure

    @Test func usageFailureBelowThresholdDoesNotSetError() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()

        await coordinator.refresh()

        #expect(coordinator.usageError == nil)
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 1)
    }

    @Test func usageFailureAtThresholdSetsError() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }

        #expect(coordinator.usageError != nil)
    }

    // MARK: - Auth Failure

    @Test func authFailureNilsOutUsage() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()
        #expect(coordinator.currentUsage != nil)

        mockUsage.result = .failure(ServiceError.unauthorized)
        await coordinator.refresh()

        #expect(coordinator.currentUsage == nil)
    }

    @Test func authFailureClassifiedCorrectly() async {
        mockUsage.result = .failure(ServiceError.unauthorized)
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(coordinator.scheduler.usageState.lastError == .authFailure)
    }

    // MARK: - MonitorState

    @Test func monitorStateReflectsCurrentData() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        let state = coordinator.monitorState
        #expect(state.currentUsage == testUsage)
        #expect(state.currentStatus == testStatus)
        #expect(state.hasCredentials)
        #expect(state.usageError == nil)
        #expect(state.statusError == nil)
        #expect(state.lastRefreshed != nil)
    }

    @Test func monitorStateWithNoCredentials() {
        let coordinator = makeCoordinator(credentials: [:])
        let state = coordinator.monitorState

        #expect(!state.hasCredentials)
        #expect(state.currentUsage == nil)
    }

    // MARK: - Restart

    @Test func restartResetsScheduler() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()
        await coordinator.refresh()
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 1)

        mockUsage.result = .success(testUsage)
        coordinator.restartPolling()
        try? await Task.sleep(for: .milliseconds(100))

        #expect(coordinator.scheduler.usageState.consecutiveFailures == 0)
    }

    // MARK: - Multiple Refreshes

    @Test func multipleRefreshesAccumulateFailures() async {
        mockStatus.result = .failure(ServiceError.rateLimited)
        let coordinator = makeCoordinator()

        await coordinator.refresh()
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 1)

        await coordinator.refresh()
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 2)
    }

    @Test func onUpdateCalledOnEveryRefresh() async {
        let coordinator = makeCoordinator()
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()
        await coordinator.refresh()
        await coordinator.refresh()

        #expect(updateCount == 3)
    }

    // MARK: - Mixed Service Results

    @Test func statusFailureDoesNotAffectUsage() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(503))
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(coordinator.currentStatus == nil)
        #expect(coordinator.currentUsage == testUsage)
    }

    @Test func usageFailureDoesNotAffectStatus() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(503))
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        #expect(coordinator.currentStatus == testStatus)
        #expect(coordinator.currentUsage == nil)
    }
}
