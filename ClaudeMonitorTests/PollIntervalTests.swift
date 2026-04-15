import Testing
import Foundation
@testable import ClaudeMonitor

struct PollIntervalTests {

    private func usage(utilization: Int, resetsIn: TimeInterval = 3600) -> UsageResponse {
        UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: utilization, resetsAt: Date().addingTimeInterval(resetsIn)))
        ])
    }

    // MARK: - Near-Reset Snapping

    @Test func nextPollIntervalNearReset() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [])
        // Window resets in 30s — within 60s effective interval
        let nearResetUsage = usage(utilization: 42, resetsIn: 30)
        let interval = scheduler.nextPollInterval(usage: nearResetUsage)
        // Should be ~31s (30 + 1 padding)
        #expect(interval > 28 && interval < 35)
    }

    @Test func nextPollIntervalResetBeyondEffectiveInterval() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [])
        // Reset 300s out — well beyond 60s interval → no snapping
        let farUsage = usage(utilization: 42, resetsIn: 300)
        #expect(scheduler.nextPollInterval(usage: farUsage) == Constants.Polling.baseInterval)
    }

    @Test func nearResetWithMultipleWindowsPicksNearest() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(windowAnalyses: [])
        let multiWindowUsage = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(45))),
            WindowEntry(key: "seven_day", duration: 604_800, durationLabel: "7d", modelScope: nil,
                        window: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(20))),
        ])
        let interval = scheduler.nextPollInterval(usage: multiWindowUsage)
        // Nearest is 20s → 20+1=21
        #expect(interval > 18 && interval < 25)
    }

    // MARK: - Error Backoff

    @Test func nextPollIntervalInErrorStateUsesBackoff() {
        var scheduler = PollingScheduler()
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordStatusFailure(category: .transient)
        }
        // After 2 transient failures: backoff = 10→20→40
        #expect(scheduler.nextPollInterval(usage: nil) == 40)
    }

    @Test func nextPollIntervalAuthErrorFallsBackToEffective() {
        var scheduler = PollingScheduler()
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .authFailure)
        }
        // Auth errors return nil from retryInterval → uses effectivePollingInterval
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func nextPollIntervalBothNonRetryableFailuresFlooredAtBase() {
        var scheduler = PollingScheduler()
        // Drive effectivePollingInterval down to minInterval (24s) via approaching-limit logic.
        // timeToLimit: 5s → effectivePollingInterval = max(24, 5/5) = 24s (below baseInterval).
        let entry = WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                                window: UsageWindow(utilization: 95, resetsAt: Date().addingTimeInterval(3600)))
        let nearLimitAnalysis = WindowAnalysis(
            entry: entry, samples: [], consumptionRate: 0, projectedAtReset: 130,
            timeToLimit: 5, rateSource: .insufficient,
            style: Formatting.UsageStyle(level: .critical, isBold: true),
            segments: [], timeSinceLastChange: nil
        )
        scheduler.adjustPollingRate(windowAnalyses: [nearLimitAnalysis])
        // Confirm effectivePollingInterval is below baseInterval
        assert(scheduler.effectivePollingInterval < Constants.Polling.baseInterval)

        // Now both services hit non-retryable failures (authFailure + permanent)
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .authFailure)
            scheduler.recordStatusFailure(category: .permanent)
        }

        // Must not poll faster than baseInterval, even though effectivePollingInterval is 24s
        #expect(scheduler.nextPollInterval(usage: nil) >= Constants.Polling.baseInterval)
    }

    @Test func nextPollIntervalMixedHealthyAndAuthFailedDoesNotFloor() {
        var scheduler = PollingScheduler()
        // Drive effectivePollingInterval below baseInterval via approaching-limit logic.
        let entry = WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                                window: UsageWindow(utilization: 95, resetsAt: Date().addingTimeInterval(3600)))
        let nearLimitAnalysis = WindowAnalysis(
            entry: entry, samples: [], consumptionRate: 0, projectedAtReset: 130,
            timeToLimit: 5, rateSource: .insufficient,
            style: Formatting.UsageStyle(level: .critical, isBold: true),
            segments: [], timeSinceLastChange: nil
        )
        scheduler.adjustPollingRate(windowAnalyses: [nearLimitAnalysis])
        assert(scheduler.effectivePollingInterval < Constants.Polling.baseInterval)

        // Only usage hits the threshold with a non-retryable auth failure; status is healthy (0 failures).
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .authFailure)
        }

        // Must NOT floor at baseInterval — only usage is non-retryable, status is healthy.
        // retryInterval(for: usageState) == nil (non-retryable), retryInterval(for: statusState) == nil (below threshold).
        // The fix ensures we use effectivePollingInterval (the aggressive 24s) rather than baseInterval.
        #expect(scheduler.nextPollInterval(usage: nil) < Constants.Polling.baseInterval)
    }

    @Test func nextPollIntervalPicksShorterOfTwoBackoffs() {
        var scheduler = PollingScheduler()
        // Status: 2 transient failures → backoff 40
        scheduler.recordStatusFailure(category: .transient)
        scheduler.recordStatusFailure(category: .transient)
        // Usage: 2 transient failures → backoff 40 (same)
        scheduler.recordUsageFailure(category: .transient)
        scheduler.recordUsageFailure(category: .transient)
        #expect(scheduler.nextPollInterval(usage: nil) == 40)

        // One more status failure → backoff 80; usage still 40
        scheduler.recordStatusFailure(category: .transient)
        #expect(scheduler.nextPollInterval(usage: nil) == 40) // picks shorter
    }

    @Test func nextPollIntervalMixedErrorCategories() {
        var scheduler = PollingScheduler()
        // Status: auth failure (no backoff)
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordStatusFailure(category: .authFailure)
        }
        // Usage: transient (has backoff 40)
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .transient)
        }
        // min(effective=60, 40) = 40
        #expect(scheduler.nextPollInterval(usage: nil) == 40)
    }

    // MARK: - Refresh Warning

    @Test func hasRefreshWarningBelowThreshold() {
        var scheduler = PollingScheduler()
        scheduler.recordStatusFailure(category: .transient)
        #expect(!scheduler.hasRefreshWarning)
    }

    @Test func hasRefreshWarningAtThreshold() {
        var scheduler = PollingScheduler()
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordStatusFailure(category: .transient)
        }
        #expect(scheduler.hasRefreshWarning)
    }

    @Test func hasRefreshWarningFromUsageOnly() {
        var scheduler = PollingScheduler()
        for _ in 0..<Constants.Retry.failureThreshold {
            scheduler.recordUsageFailure(category: .rateLimited)
        }
        #expect(scheduler.hasRefreshWarning)
    }

    // MARK: - Staleness

    @Test func isUsageStaleReturnsFalseWithNoSuccess() {
        let scheduler = PollingScheduler()
        #expect(!scheduler.isUsageStale) // guard let fails → false
    }

    @Test func isUsageStaleReturnsFalseAfterFreshSuccess() {
        var scheduler = PollingScheduler()
        scheduler.recordUsageSuccess()
        #expect(!scheduler.isUsageStale)
    }

    // MARK: - Reset

    @Test func resetClearsAllState() {
        var scheduler = PollingScheduler()
        scheduler.recordStatusFailure(category: .transient)
        scheduler.recordUsageFailure(category: .rateLimited)
        scheduler.adjustPollingRate(windowAnalyses: [])
        scheduler.adjustPollingRate(windowAnalyses: [])

        scheduler.reset()

        #expect(scheduler.statusState.consecutiveFailures == 0)
        #expect(scheduler.usageState.consecutiveFailures == 0)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
        #expect(!scheduler.hasRefreshWarning)
    }
}
