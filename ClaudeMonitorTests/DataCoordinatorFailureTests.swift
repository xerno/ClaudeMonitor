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

        #expect(coordinator.statusError == nil)
        #expect(coordinator.statusScheduler.statusState.consecutiveFailures == 1)
    }

    @Test func statusFailureJustBelowThresholdDoesNotSetError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        for _ in 0..<(Constants.Retry.failureThreshold - 1) {
            await coordinator.refresh()
        }

        #expect(coordinator.statusError == nil)
        #expect(coordinator.statusScheduler.statusState.consecutiveFailures == Constants.Retry.failureThreshold - 1)
    }

    @Test func statusFailureAtThresholdSetsError() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }

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

        #expect(coordinator.statusError == nil)
        #expect(coordinator.currentStatus == (try? mockStatus.result.get()))
    }

    // MARK: - Usage Failure

    @Test func usageFailureBelowThresholdDoesNotSetError() async throws {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        #expect(coordinator.usageError == nil)
        let monitor = try #require(coordinator.activeMonitor)
        #expect(monitor.scheduler.usageState.consecutiveFailures == 1)
    }

    @Test func usageFailureJustBelowThresholdDoesNotSetError() async throws {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        for _ in 0..<(Constants.Retry.failureThreshold - 1) {
            await coordinator.refresh()
        }

        #expect(coordinator.usageError == nil)
        let monitor = try #require(coordinator.activeMonitor)
        #expect(monitor.scheduler.usageState.consecutiveFailures == Constants.Retry.failureThreshold - 1)
    }

    @Test func usageFailureAtThresholdSetsError() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        for _ in 0..<Constants.Retry.failureThreshold {
            await coordinator.refresh()
        }

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

        #expect(coordinator.currentUsage == nil)
    }

    @Test func authFailureClassifiedCorrectly() async throws {
        mockUsage.result = .failure(ServiceError.unauthorized)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        let monitor = try #require(coordinator.activeMonitor)
        #expect(monitor.scheduler.usageState.lastError == .authFailure)
    }

    // MARK: - Multiple Refreshes

    @Test func multipleRefreshesAccumulateFailures() async {
        mockStatus.result = .failure(ServiceError.rateLimited)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        await coordinator.refresh()
        #expect(coordinator.statusScheduler.statusState.consecutiveFailures == 1)

        await coordinator.refresh()
        #expect(coordinator.statusScheduler.statusState.consecutiveFailures == 2)

    }

    // MARK: - Mixed Service Results

    @Test func statusFailureDoesNotAffectUsage() async {
        mockStatus.result = .failure(ServiceError.unexpectedStatus(503))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        #expect(coordinator.currentStatus == nil)
        #expect(coordinator.currentUsage == (try? mockUsage.result.get()))
    }

    @Test func usageFailureDoesNotAffectStatus() async {
        mockUsage.result = .failure(ServiceError.unexpectedStatus(503))
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)
        await coordinator.refresh()

        #expect(coordinator.currentStatus == (try? mockStatus.result.get()))
        #expect(coordinator.currentUsage == nil)
    }

    // MARK: - Task: Defect 3 — a stale retained currentUsage must never be re-recorded

    /// A successful cycle followed by a transient (non-auth) failure must NOT feed the
    /// retained-but-stale `currentUsage` into history recording a second time. Before the
    /// fix, `refresh()` decided whether to record based on `if let newUsage = currentUsage`
    /// — which stays non-nil on a transient failure (only `.authFailure` nils it out) — so a
    /// failed cycle looked identical to a fresh success and fabricated a "confirmed
    /// unchanged at now" sample that never actually happened.
    @Test func transientUsageFailureAfterSuccessDoesNotRecordAStaleSample() async throws {
        let usageResponse = TestFixtures.usage()
        mockUsage.result = .success(usageResponse)
        let fixture = UsageHistoryTestFixture()
        let (coordinator, _) = coordinator(fixture: fixture)

        await coordinator.refresh()
        #expect(coordinator.currentUsage != nil)
        let identity = try #require(usageResponse.entries.first).storageIdentity
        let monitor = try #require(coordinator.activeMonitor)
        let countAfterSuccess = monitor.usageHistory.storage[identity]?.samples.count
        #expect(countAfterSuccess == 1, "The first, genuinely fresh cycle records exactly one sample.")

        mockUsage.result = .failure(ServiceError.unexpectedStatus(503))
        await coordinator.refresh()

        // currentUsage is retained (stale) for display — the pre-fix bug's whole premise —
        // but it must not have been fed into history a second time.
        #expect(coordinator.currentUsage != nil, "Sanity check: currentUsage is indeed retained (stale), not nilled, on a transient failure.")
        #expect(monitor.usageHistory.storage[identity]?.samples.count == countAfterSuccess,
                "A failed (non-auth) cycle must never append a fabricated sample for the stale retained currentUsage.")
    }
}
