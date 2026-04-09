import Testing
import Foundation
@testable import ClaudeMonitor

struct PollingRateTests {

    private func usage(utilization: Int, resetsIn: TimeInterval = 3600) -> UsageResponse {
        UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: utilization, resetsAt: Date().addingTimeInterval(resetsIn)))
        ])
    }

    // MARK: - Speedup

    @Test func speedupFromBase() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        scheduler.adjustPollingRate(usage: usage(utilization: 60), isCritical: false)
        // base 60 * 0.8 = 48
        #expect(scheduler.nextPollInterval(usage: nil) == 48)
    }

    @Test func speedupChainsMultipleTimes() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false) // 60*0.8=48
        scheduler.adjustPollingRate(usage: usage(utilization: 60), isCritical: false) // 48*0.8=38.4→38
        #expect(scheduler.nextPollInterval(usage: nil) == 38)
    }

    @Test func speedupFloorsAtMinInterval() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 10), isCritical: false)
        for i in stride(from: 20, through: 100, by: 10) {
            scheduler.adjustPollingRate(usage: usage(utilization: i), isCritical: false)
        }
        #expect(scheduler.nextPollInterval(usage: nil) >= Constants.Polling.minInterval)
    }

    @Test func speedupFromAboveBaseSnapsToBase() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        // Cooldown to above-base
        for _ in 0..<(Constants.Polling.cooldownCycles + 3) {
            scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        }
        let slowedInterval = scheduler.nextPollInterval(usage: nil)
        #expect(slowedInterval > Constants.Polling.baseInterval)
        // Speedup should snap to base (not multiply by 0.8)
        scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    // MARK: - Deceleration

    @Test func decelerationFromAboveBaseSnapsToBase() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        for _ in 0..<(Constants.Polling.cooldownCycles + 3) {
            scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        }
        #expect(scheduler.nextPollInterval(usage: nil) > Constants.Polling.baseInterval)
        scheduler.adjustPollingRate(usage: usage(utilization: 30), isCritical: false)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func decelerationInFastModePreservesInterval() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false)
        let fastInterval = scheduler.nextPollInterval(usage: nil)
        #expect(fastInterval < Constants.Polling.baseInterval)
        // Usage decreased in fast mode — interval should stay (cooldown continues)
        scheduler.adjustPollingRate(usage: usage(utilization: 45), isCritical: false)
        #expect(scheduler.nextPollInterval(usage: nil) == fastInterval)
    }

    // MARK: - Cooldown

    @Test func cooldownSlowsAfterThreeCycles() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false) // 48
        let fastInterval = scheduler.nextPollInterval(usage: nil)
        for _ in 0..<Constants.Polling.cooldownCycles {
            scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false)
        }
        #expect(scheduler.nextPollInterval(usage: nil) > fastInterval)
    }

    @Test func cooldownDoesNotExceedMaxInterval() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        for _ in 0..<50 {
            scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        }
        #expect(scheduler.nextPollInterval(usage: nil) <= Constants.Polling.maxInterval)
    }

    @Test func cooldownResetsCounterWhenCrossingBase() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false) // 48
        // 3 cooldown cycles → ceil(48/0.8)=60 → snaps to base, resets counter
        for _ in 0..<Constants.Polling.cooldownCycles {
            scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false)
        }
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
        // Only 2 more cycles — not enough to slow again
        scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false)
        scheduler.adjustPollingRate(usage: usage(utilization: 50), isCritical: false)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    // MARK: - Critical Floor

    @Test func criticalFlagCapsInterval() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        for _ in 0..<20 {
            scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        }
        #expect(scheduler.nextPollInterval(usage: nil) > Constants.Polling.criticalFloor)
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: true)
        #expect(scheduler.nextPollInterval(usage: nil) <= Constants.Polling.criticalFloor)
    }

    @Test func highUtilizationCapsInterval() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        for _ in 0..<20 {
            scheduler.adjustPollingRate(usage: usage(utilization: 40), isCritical: false)
        }
        // ≥90 util caps at criticalFloor even without isCritical
        scheduler.adjustPollingRate(usage: usage(utilization: 92), isCritical: false)
        #expect(scheduler.nextPollInterval(usage: nil) <= Constants.Polling.criticalFloor)
    }

    // MARK: - Edge Cases

    @Test func firstCallWithNoHistorySetsBase() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: usage(utilization: 80), isCritical: false)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }

    @Test func nilUsageSetsBase() {
        var scheduler = PollingScheduler()
        scheduler.adjustPollingRate(usage: nil, isCritical: false)
        #expect(scheduler.nextPollInterval(usage: nil) == Constants.Polling.baseInterval)
    }
}
