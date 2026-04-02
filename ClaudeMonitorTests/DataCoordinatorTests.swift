import XCTest
@testable import ClaudeMonitor

private let testStatus = StatusSummary(
    components: [StatusComponent(id: "1", name: "API", status: .operational)],
    incidents: [],
    status: PageStatus(indicator: "none", description: "All Systems Operational")
)

private let testUsage = UsageResponse(
    fiveHour: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(3600)),
    sevenDay: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(86400)),
    sevenDaySonnet: nil
)

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

@MainActor
final class DataCoordinatorTests: XCTestCase {
    private var mockStatus: MockStatusService!
    private var mockUsage: MockUsageService!

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

    override func setUp() {
        mockStatus = MockStatusService()
        mockUsage = MockUsageService()
    }

    // MARK: - Successful Fetch

    func testRefreshUpdatesStateOnSuccess() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        XCTAssertEqual(coordinator.currentStatus, testStatus)
        XCTAssertEqual(coordinator.currentUsage, testUsage)
        XCTAssertNil(coordinator.usageError)
        XCTAssertNil(coordinator.statusError)
        XCTAssertNotNil(coordinator.lastRefreshed)
    }

    func testRefreshCallsBothServices() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        XCTAssertEqual(mockStatus.fetchCount, 1)
        XCTAssertEqual(mockUsage.fetchCount, 1)
    }

    func testRefreshPassesCredentialsToUsageService() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        XCTAssertEqual(mockUsage.lastOrgId, "test-org-id")
        XCTAssertEqual(mockUsage.lastCookie, "test-cookie")
    }

    func testRefreshCallsOnUpdate() async {
        let coordinator = makeCoordinator()
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()

        XCTAssertEqual(updateCount, 1)
    }

    func testRefreshRecordsSchedulerSuccess() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        XCTAssertNotNil(coordinator.scheduler.statusState.lastSuccess)
        XCTAssertNotNil(coordinator.scheduler.usageState.lastSuccess)
        XCTAssertEqual(coordinator.scheduler.statusState.consecutiveFailures, 0)
        XCTAssertEqual(coordinator.scheduler.usageState.consecutiveFailures, 0)
    }

    // MARK: - No Credentials

    func testRefreshWithNoCredentialsSetsUsageError() async {
        let coordinator = makeCoordinator(credentials: [:])
        await coordinator.refresh()

        XCTAssertEqual(coordinator.usageError, "Configure credentials in Preferences")
        XCTAssertEqual(mockUsage.fetchCount, 0)
    }

    func testRefreshWithEmptyCredentialsSetsUsageError() async {
        let coordinator = makeCoordinator(credentials: [
            Constants.Keychain.cookieString: "",
            Constants.Keychain.organizationId: "org",
        ])
        await coordinator.refresh()

        XCTAssertEqual(coordinator.usageError, "Configure credentials in Preferences")
        XCTAssertEqual(mockUsage.fetchCount, 0)
    }

    func testNoCredentialsStillFetchesStatus() async {
        let coordinator = makeCoordinator(credentials: [:])
        await coordinator.refresh()

        XCTAssertEqual(mockStatus.fetchCount, 1)
        XCTAssertEqual(coordinator.currentStatus, testStatus)
    }

    func testHasCredentialsReturnsFalseWhenMissing() {
        let coordinator = makeCoordinator(credentials: [:])
        XCTAssertFalse(coordinator.hasCredentials)
    }

    func testHasCredentialsReturnsTrueWhenPresent() {
        let coordinator = makeCoordinator()
        XCTAssertTrue(coordinator.hasCredentials)
    }

    // MARK: - Status Failure

    func testStatusFailureBelowThresholdDoesNotSetError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()

        await coordinator.refresh()

        XCTAssertNil(coordinator.statusError)
        XCTAssertEqual(coordinator.scheduler.statusState.consecutiveFailures, 1)
    }

    func testStatusFailureAtThresholdSetsError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }

        XCTAssertNotNil(coordinator.statusError)
    }

    func testStatusSuccessAfterFailureClearsError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()
        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        XCTAssertNotNil(coordinator.statusError)

        mockStatus.result = .success(testStatus)
        await coordinator.refresh()

        XCTAssertNil(coordinator.statusError)
        XCTAssertEqual(coordinator.currentStatus, testStatus)
    }

    // MARK: - Usage Failure

    func testUsageFailureBelowThresholdDoesNotSetError() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()

        await coordinator.refresh()

        XCTAssertNil(coordinator.usageError)
        XCTAssertEqual(coordinator.scheduler.usageState.consecutiveFailures, 1)
    }

    func testUsageFailureAtThresholdSetsError() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }

        XCTAssertNotNil(coordinator.usageError)
    }

    // MARK: - Auth Failure

    func testAuthFailureNilsOutUsage() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()
        XCTAssertNotNil(coordinator.currentUsage)

        mockUsage.result = .failure(ServiceError.unauthorized)
        await coordinator.refresh()

        XCTAssertNil(coordinator.currentUsage)
    }

    func testAuthFailureClassifiedCorrectly() async {
        mockUsage.result = .failure(ServiceError.unauthorized)
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        XCTAssertEqual(coordinator.scheduler.usageState.lastError, .authFailure)
    }

    // MARK: - MonitorState

    func testMonitorStateReflectsCurrentData() async {
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        let state = coordinator.monitorState
        XCTAssertEqual(state.currentUsage, testUsage)
        XCTAssertEqual(state.currentStatus, testStatus)
        XCTAssertTrue(state.hasCredentials)
        XCTAssertNil(state.usageError)
        XCTAssertNil(state.statusError)
        XCTAssertNotNil(state.lastRefreshed)
    }

    func testMonitorStateWithNoCredentials() {
        let coordinator = makeCoordinator(credentials: [:])
        let state = coordinator.monitorState

        XCTAssertFalse(state.hasCredentials)
        XCTAssertNil(state.currentUsage)
    }

    // MARK: - Restart

    func testRestartResetsScheduler() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let coordinator = makeCoordinator()
        await coordinator.refresh()
        XCTAssertEqual(coordinator.scheduler.usageState.consecutiveFailures, 1)

        mockUsage.result = .success(testUsage)
        coordinator.restartPolling()
        // Give the polling task a moment to run its first refresh
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(coordinator.scheduler.usageState.consecutiveFailures, 0)
    }

    // MARK: - Multiple Refreshes

    func testMultipleRefreshesAccumulateFailures() async {
        mockStatus.result = .failure(ServiceError.rateLimited)
        let coordinator = makeCoordinator()

        await coordinator.refresh()
        XCTAssertEqual(coordinator.scheduler.statusState.consecutiveFailures, 1)

        await coordinator.refresh()
        XCTAssertEqual(coordinator.scheduler.statusState.consecutiveFailures, 2)
    }

    func testOnUpdateCalledOnEveryRefresh() async {
        let coordinator = makeCoordinator()
        var updateCount = 0
        coordinator.onUpdate = { updateCount += 1 }

        await coordinator.refresh()
        await coordinator.refresh()
        await coordinator.refresh()

        XCTAssertEqual(updateCount, 3)
    }

    // MARK: - Mixed Service Results

    func testStatusFailureDoesNotAffectUsage() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(503))
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        XCTAssertNil(coordinator.currentStatus)
        XCTAssertEqual(coordinator.currentUsage, testUsage)
    }

    func testUsageFailureDoesNotAffectStatus() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(503))
        let coordinator = makeCoordinator()
        await coordinator.refresh()

        XCTAssertEqual(coordinator.currentStatus, testStatus)
        XCTAssertNil(coordinator.currentUsage)
    }
}
