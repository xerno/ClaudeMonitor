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
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        // Window resets in 30s — within 60s effective interval
        let nearResetUsage = usage(utilization: 42, resetsIn: 30)
        let interval = scheduler.nextPollInterval(usage: nearResetUsage)
        // Should be ~31s (30 + 1 padding)
        #expect(interval > 28 && interval < 35)
    }

    @Test func nextPollIntervalResetBeyondEffectiveInterval() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        // Reset 300s out — well beyond 60s interval → no snapping
        let farUsage = usage(utilization: 42, resetsIn: 300)
        #expect(scheduler.nextPollInterval(usage: farUsage) == Constants.Polling.baseInterval)
    }

    @Test func nearResetWithMultipleWindowsPicksNearest() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
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
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        scheduler.adjustPollingRate(usage: usage(utilization: 80), isCritical: false)

        scheduler.reset()

        #expect(scheduler.statusState.consecutiveFailures == 0)
        #expect(scheduler.usageState.consecutiveFailures == 0)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
        #expect(!scheduler.hasRefreshWarning)
    }
}
