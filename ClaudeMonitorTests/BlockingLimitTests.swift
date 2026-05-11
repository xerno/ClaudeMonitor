import Testing
import Foundation
@testable import ClaudeMonitor

struct BlockingLimitTests {

    @Test func blockingLimitNilUsage() {
        #expect(Formatting.blockingLimit(nil) == nil)
    }

    @Test func blockingLimitNoWindowsAt100() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))!,
            .make(key: "seven_day", utilization: 80, resetsAt: now.addingTimeInterval(86400))!,
        ])
        #expect(Formatting.blockingLimit(usage) == nil)
    }

    @Test func blockingLimitOnly5hAt100() {
        let now = Date()
        let resetTime = now.addingTimeInterval(7200)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: resetTime)!,
            .make(key: "seven_day", utilization: 80, resetsAt: now.addingTimeInterval(86400))!,
        ])
        #expect(Formatting.blockingLimit(usage) == resetTime)
    }

    @Test func blockingLimitBothAt100ReturnsLatest() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(7200)
        let sevenDayReset = now.addingTimeInterval(259200)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: fiveHourReset)!,
            .make(key: "seven_day", utilization: 100, resetsAt: sevenDayReset)!,
        ])
        #expect(Formatting.blockingLimit(usage) == sevenDayReset)
    }

    @Test func blockingLimitBothAt100SameResetTimeReturnsThatTime() {
        let now = Date()
        let tiedReset = now.addingTimeInterval(7200)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: tiedReset)!,
            .make(key: "seven_day", utilization: 100, resetsAt: tiedReset)!,
        ])
        #expect(Formatting.blockingLimit(usage) == tiedReset)
    }

    @Test func blockingLimitReversedOrderReturnsMax() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(259200)
        let sevenDayReset = now.addingTimeInterval(7200)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: fiveHourReset)!,
            .make(key: "seven_day", utilization: 100, resetsAt: sevenDayReset)!,
        ])
        #expect(Formatting.blockingLimit(usage) == fiveHourReset)
    }

    // MARK: - hasBlockingGeneralWindow

    @Test func hasBlockingGeneralWindowFalseWhenEmpty() {
        #expect(!Formatting.hasBlockingGeneralWindow([]))
    }

    @Test func hasBlockingGeneralWindowFalseWhenBelowThreshold() {
        let entries: [WindowEntry] = [
            .make(key: "five_hour", utilization: 99, resetsAt: nil)!,
            .make(key: "seven_day", utilization: 50, resetsAt: nil)!,
        ]
        #expect(!Formatting.hasBlockingGeneralWindow(entries))
    }

    @Test func hasBlockingGeneralWindowTrueWhenGeneralAt100() {
        let entries: [WindowEntry] = [
            .make(key: "five_hour", utilization: 100, resetsAt: nil)!,
            .make(key: "seven_day", utilization: 50, resetsAt: nil)!,
        ]
        #expect(Formatting.hasBlockingGeneralWindow(entries))
    }

    @Test func hasBlockingGeneralWindowFalseWhenOnlyModelSpecificAt100() {
        let entries: [WindowEntry] = [
            .make(key: "five_hour", utilization: 50, resetsAt: nil)!,
            .make(key: "seven_day_sonnet", utilization: 100, resetsAt: nil)!,
        ]
        #expect(!Formatting.hasBlockingGeneralWindow(entries))
    }

    @Test func hasBlockingGeneralWindowTrueWhenBothGeneralAndModelSpecificAt100() {
        let entries: [WindowEntry] = [
            .make(key: "five_hour", utilization: 100, resetsAt: nil)!,
            .make(key: "seven_day_sonnet", utilization: 100, resetsAt: nil)!,
        ]
        #expect(Formatting.hasBlockingGeneralWindow(entries))
    }

    @Test func blockingLimitOnlyModelSpecificAt100ReturnsNil() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 80, resetsAt: now.addingTimeInterval(3600))!,
            .make(key: "seven_day", utilization: 70, resetsAt: now.addingTimeInterval(86400))!,
            .make(key: "seven_day_sonnet", utilization: 100, resetsAt: now.addingTimeInterval(172800))!,
        ])
        #expect(Formatting.blockingLimit(usage) == nil)
    }

    @Test func blockingLimitAllThreeAt100ReturnsLatest() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(7200)
        let sevenDayReset = now.addingTimeInterval(259200)
        let sonnetReset = now.addingTimeInterval(172800)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: fiveHourReset)!,
            .make(key: "seven_day", utilization: 100, resetsAt: sevenDayReset)!,
            .make(key: "seven_day_sonnet", utilization: 100, resetsAt: sonnetReset)!,
        ])
        #expect(Formatting.blockingLimit(usage) == sevenDayReset)
    }
}
