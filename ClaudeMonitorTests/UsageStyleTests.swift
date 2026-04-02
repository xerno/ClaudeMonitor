import XCTest
@testable import ClaudeMonitor

final class UsageStyleTests: XCTestCase {

    private func style(utilization: Int, timeRemainingPercent: Double) -> Formatting.UsageStyle {
        let now = Date()
        let windowDuration: TimeInterval = 1000
        let resetsAt = now.addingTimeInterval(windowDuration * timeRemainingPercent / 100)
        return Formatting.usageStyle(
            utilization: utilization,
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            now: now
        )
    }

    func testStyleNormal() {
        let s = style(utilization: 30, timeRemainingPercent: 70)
        XCTAssertEqual(s.color, .labelColor)
        XCTAssertFalse(s.isBold)
    }

    func testStyleBoldByFixedThreshold() {
        // 55% used, 50% time remaining (50% elapsed) — bold by fixed (≥50), not orange (55 < 70)
        let s = style(utilization: 55, timeRemainingPercent: 50)
        XCTAssertEqual(s.color, .labelColor)
        XCTAssertTrue(s.isBold)
    }

    func testStyleBoldByTimeRule() {
        // 45% used, 60% time remaining (40% elapsed) — projected 112%, outpacing
        let s = style(utilization: 45, timeRemainingPercent: 60)
        XCTAssertEqual(s.color, .labelColor)
        XCTAssertTrue(s.isBold)
    }

    func testStyleOrangeByFixedThreshold() {
        // 72% used, 50% time remaining (50% elapsed) — orange by fixed (≥70), not red (72 < 85)
        let s = style(utilization: 72, timeRemainingPercent: 50)
        XCTAssertEqual(s.color, .systemOrange)
        XCTAssertTrue(s.isBold)
    }

    func testStyleOrangeByTimeRule() {
        // 65% used, 60% time remaining (40% elapsed) — 65 > 40+20, projected 162%
        let s = style(utilization: 65, timeRemainingPercent: 60)
        XCTAssertEqual(s.color, .systemOrange)
        XCTAssertTrue(s.isBold)
    }

    func testStyleRedByFixedThreshold() {
        let s = style(utilization: 85, timeRemainingPercent: 80)
        XCTAssertEqual(s.color, .systemRed)
        XCTAssertTrue(s.isBold)
    }

    func testStyleRedByTimeRule() {
        // 78% used, 60% time remaining (40% elapsed) — 78 > 40+35, projected 195%
        let s = style(utilization: 78, timeRemainingPercent: 60)
        XCTAssertEqual(s.color, .systemRed)
        XCTAssertTrue(s.isBold)
    }

    func testStyleNotBoldWhenPlentyOfTime() {
        // 15% used, 80% time remaining (20% elapsed) — projected 75%, comfortable
        let s = style(utilization: 15, timeRemainingPercent: 80)
        XCTAssertEqual(s.color, .labelColor)
        XCTAssertFalse(s.isBold)
    }

    func testStylePastResetDate() {
        // Reset passed, low utilization — not concerning
        let now = Date()
        let resetsAt = now.addingTimeInterval(-100)
        let s = Formatting.usageStyle(utilization: 10, resetsAt: resetsAt, windowDuration: 1000, now: now)
        XCTAssertFalse(s.isBold)
    }

    private func shouldShow(utilization: Int, timeRemainingPercent: Double) -> Bool {
        let now = Date()
        let windowDuration: TimeInterval = 1000
        let resetsAt = now.addingTimeInterval(windowDuration * timeRemainingPercent / 100)
        return Formatting.shouldShowInMenuBar(
            utilization: utilization,
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            now: now
        )
    }

    func testShouldShowLowUtilizationPlentyOfTime() {
        // 30% used, 70% time remaining — comfortable, no show
        XCTAssertFalse(shouldShow(utilization: 30, timeRemainingPercent: 70))
    }

    func testShouldShowHighUtilizationNotOutpacing() {
        // 55% used, 40% time remaining (60% elapsed) — bold (fixed) but NOT outpacing (55 < 60)
        XCTAssertFalse(shouldShow(utilization: 55, timeRemainingPercent: 40))
    }

    func testShouldShowLowUtilizationLittleTime() {
        // 20% used, 10% time remaining (90% elapsed) — not outpacing (20 < 90), no show
        XCTAssertFalse(shouldShow(utilization: 20, timeRemainingPercent: 10))
    }

    func testShouldShowHighUtilizationOutpacingTime() {
        // 65% used, 40% time remaining (60% elapsed) — bold AND outpacing (65 > 60)
        XCTAssertTrue(shouldShow(utilization: 65, timeRemainingPercent: 40))
    }

    func testShouldShowExactlyAtBoundary() {
        // 50% used, 50% time remaining (50% elapsed) — bold (fixed) but NOT outpacing (equal)
        XCTAssertFalse(shouldShow(utilization: 50, timeRemainingPercent: 50))
    }

    func testShouldShowPastResetDate() {
        // Reset passed, low utilization — not concerning, no show
        let now = Date()
        let result = Formatting.shouldShowInMenuBar(
            utilization: 10,
            resetsAt: now.addingTimeInterval(-100),
            windowDuration: 1000,
            now: now
        )
        XCTAssertFalse(result)
    }
}
