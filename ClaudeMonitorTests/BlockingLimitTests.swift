import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct BlockingLimitTests {

    @Test func blockingLimitNilUsage() {
        #expect(Formatting.blockingLimit(nil) == nil)
    }

    @Test func blockingLimitNoWindowsAt100() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600)),
            .make(key: "seven_day", utilization: 80, resetsAt: now.addingTimeInterval(86400)),
        ])
        #expect(Formatting.blockingLimit(usage) == nil)
    }

    @Test func blockingLimitOnly5hAt100() {
        let now = Date()
        let resetTime = now.addingTimeInterval(7200)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: resetTime),
            .make(key: "seven_day", utilization: 80, resetsAt: now.addingTimeInterval(86400)),
        ])
        #expect(Formatting.blockingLimit(usage) == resetTime)
    }

    @Test func blockingLimitBothAt100ReturnsLatest() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(7200)
        let sevenDayReset = now.addingTimeInterval(259200)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: fiveHourReset),
            .make(key: "seven_day", utilization: 100, resetsAt: sevenDayReset),
        ])
        #expect(Formatting.blockingLimit(usage) == sevenDayReset)
    }

    @Test func blockingLimitAllThreeAt100ReturnsLatest() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(7200)
        let sevenDayReset = now.addingTimeInterval(259200)
        let sonnetReset = now.addingTimeInterval(172800)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: fiveHourReset),
            .make(key: "seven_day", utilization: 100, resetsAt: sevenDayReset),
            .make(key: "seven_day_sonnet", utilization: 100, resetsAt: sonnetReset),
        ])
        #expect(Formatting.blockingLimit(usage) == sevenDayReset)
    }
}
