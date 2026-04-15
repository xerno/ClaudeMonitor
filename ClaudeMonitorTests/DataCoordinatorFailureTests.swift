import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct DataCoordinatorFailureTests {
    private let mockStatus = MockStatusService()
    private let mockUsage = MockUsageService()
    private let mockIdleProvider = MockSystemIdleProvider()

    private func makeCoordinator(
        credentials: [String: String] = [
            Constants.Keychain.cookieString: "test-cookie",
            Constants.Keychain.organizationId: "test-org-id",
        ]
    ) -> DataCoordinator {
        DataCoordinator(
            statusService: mockStatus,
            usageService: mockUsage,
            systemIdleProvider: mockIdleProvider,
            loadCredential: { credentials[$0] }
        )
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

    // MARK: - Multiple Refreshes

    @Test func multipleRefreshesAccumulateFailures() async {
        mockStatus.result = .failure(ServiceError.rateLimited)
        let coordinator = makeCoordinator()

        await coordinator.refresh()
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 1)

        await coordinator.refresh()
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 2)
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
