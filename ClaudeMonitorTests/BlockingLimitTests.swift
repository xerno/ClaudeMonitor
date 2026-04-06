import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct BlockingLimitTests {

    @Test func blockingLimitNilUsage() {
        #expect(Formatting.blockingLimit(nil) == nil)
    }

    @Test func blockingLimitNoWindowsAt100() {
        let now = Date()
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 42, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: UsageWindow(utilization: 80, resetsAt: now.addingTimeInterval(86400)),
            sevenDaySonnet: nil
        )
        #expect(Formatting.blockingLimit(usage) == nil)
    }

    @Test func blockingLimitOnly5hAt100() {
        let now = Date()
        let resetTime = now.addingTimeInterval(7200)
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 100, resetsAt: resetTime),
            sevenDay: UsageWindow(utilization: 80, resetsAt: now.addingTimeInterval(86400)),
            sevenDaySonnet: nil
        )
        #expect(Formatting.blockingLimit(usage) == resetTime)
    }

    @Test func blockingLimitBothAt100ReturnsLatest() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(7200)
        let sevenDayReset = now.addingTimeInterval(259200)
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 100, resetsAt: fiveHourReset),
            sevenDay: UsageWindow(utilization: 100, resetsAt: sevenDayReset),
            sevenDaySonnet: nil
        )
        #expect(Formatting.blockingLimit(usage) == sevenDayReset)
    }

    @Test func blockingLimitAllThreeAt100ReturnsLatest() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(7200)
        let sevenDayReset = now.addingTimeInterval(259200)
        let sonnetReset = now.addingTimeInterval(172800)
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 100, resetsAt: fiveHourReset),
            sevenDay: UsageWindow(utilization: 100, resetsAt: sevenDayReset),
            sevenDaySonnet: UsageWindow(utilization: 100, resetsAt: sonnetReset)
        )
        #expect(Formatting.blockingLimit(usage) == sevenDayReset)
    }
}
