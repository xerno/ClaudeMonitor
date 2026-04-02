import XCTest
@testable import ClaudeMonitor

final class BlockingLimitTests: XCTestCase {

    func testBlockingLimitNilUsage() {
        XCTAssertNil(Formatting.blockingLimit(nil))
    }

    func testBlockingLimitNoWindowsAt100() {
        let now = Date()
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 42, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: UsageWindow(utilization: 80, resetsAt: now.addingTimeInterval(86400)),
            sevenDaySonnet: nil
        )
        XCTAssertNil(Formatting.blockingLimit(usage))
    }

    func testBlockingLimitOnly5hAt100() {
        let now = Date()
        let resetTime = now.addingTimeInterval(7200)
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 100, resetsAt: resetTime),
            sevenDay: UsageWindow(utilization: 80, resetsAt: now.addingTimeInterval(86400)),
            sevenDaySonnet: nil
        )
        XCTAssertEqual(Formatting.blockingLimit(usage), resetTime)
    }

    func testBlockingLimitBothAt100ReturnsLatest() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(7200)
        let sevenDayReset = now.addingTimeInterval(259200)
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 100, resetsAt: fiveHourReset),
            sevenDay: UsageWindow(utilization: 100, resetsAt: sevenDayReset),
            sevenDaySonnet: nil
        )
        XCTAssertEqual(Formatting.blockingLimit(usage), sevenDayReset)
    }

    func testBlockingLimitAllThreeAt100ReturnsLatest() {
        let now = Date()
        let fiveHourReset = now.addingTimeInterval(7200)
        let sevenDayReset = now.addingTimeInterval(259200)
        let sonnetReset = now.addingTimeInterval(172800)
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 100, resetsAt: fiveHourReset),
            sevenDay: UsageWindow(utilization: 100, resetsAt: sevenDayReset),
            sevenDaySonnet: UsageWindow(utilization: 100, resetsAt: sonnetReset)
        )
        XCTAssertEqual(Formatting.blockingLimit(usage), sevenDayReset)
    }
}
