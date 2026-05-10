import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct DataCoordinatorFailureTests {
    private let mockStatus = MockStatusService()
    private let mockUsage = MockUsageService()

    private func coordinator(
        fixture: UsageHistoryTestFixture,
        testOrgId: String = UUID().uuidString,
        credentials: [String: String]? = nil
    ) -> (DataCoordinator, String) {
        makeCoordinator(
            fixture: fixture,
            status: mockStatus,
            usage: mockUsage,
            testOrgId: testOrgId,
            credentials: credentials
        )
    }

    // MARK: - Status Failure

    @Test func statusFailureBelowThresholdDoesNotSetError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.statusError == nil)
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 1)
    }

    @Test func statusFailureAtThresholdSetsError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        await fixture.cleanup()

        #expect(coordinator.statusError != nil)
    }

    @Test func statusSuccessAfterFailureClearsError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        #expect(coordinator.statusError != nil)

        mockStatus.result = .success(TestFixtures.status())
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.statusError == nil)
        #expect(coordinator.currentStatus == (try? mockStatus.result.get()))
    }

    // MARK: - Usage Failure

    @Test func usageFailureBelowThresholdDoesNotSetError() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.usageError == nil)
        #expect(coordinator.scheduler.usageState.consecutiveFailures == 1)
    }

    @Test func usageFailureAtThresholdSetsError() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }
        await fixture.cleanup()

        #expect(coordinator.usageError != nil)
    }

    // MARK: - Auth Failure

    @Test func authFailureNilsOutUsage() async {
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        #expect(coordinator.currentUsage != nil)

        mockUsage.result = .failure(ServiceError.unauthorized)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.currentUsage == nil)
    }

    @Test func authFailureClassifiedCorrectly() async {
        mockUsage.result = .failure(ServiceError.unauthorized)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.scheduler.usageState.lastError == .authFailure)
    }

    // MARK: - Multiple Refreshes

    @Test func multipleRefreshesAccumulateFailures() async {
        mockStatus.result = .failure(ServiceError.rateLimited)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        await coordinator.refresh()
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 1)

        await coordinator.refresh()
        #expect(coordinator.scheduler.statusState.consecutiveFailures == 2)

        await fixture.cleanup()
    }

    // MARK: - Mixed Service Results

    @Test func statusFailureDoesNotAffectUsage() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(503))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.currentStatus == nil)
        #expect(coordinator.currentUsage == (try? mockUsage.result.get()))
    }

    @Test func usageFailureDoesNotAffectStatus() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(503))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()
        await fixture.cleanup()

        #expect(coordinator.currentStatus == (try? mockStatus.result.get()))
        #expect(coordinator.currentUsage == nil)
    }
}
