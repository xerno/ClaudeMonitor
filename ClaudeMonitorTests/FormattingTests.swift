import XCTest
@testable import ClaudeMonitor

final class FormattingTests: XCTestCase {

    // MARK: - timeUntil

    func testTimeUntilMinutesOnly() {
        let now = Date()
        let date = now.addingTimeInterval(25 * 60)
        XCTAssertEqual(Formatting.timeUntil(date, now: now), "in 25m")
    }

    func testTimeUntilHoursAndMinutes() {
        let now = Date()
        let date = now.addingTimeInterval(3 * 3600 + 15 * 60)
        XCTAssertEqual(Formatting.timeUntil(date, now: now), "in 3h 15m")
    }

    func testTimeUntilDaysAndHours() {
        let now = Date()
        let date = now.addingTimeInterval(2 * 86400 + 5 * 3600)
        XCTAssertEqual(Formatting.timeUntil(date, now: now), "in 2d 5h")
    }

    func testTimeUntilPastDateReturnsZero() {
        let now = Date()
        let date = now.addingTimeInterval(-100)
        XCTAssertEqual(Formatting.timeUntil(date, now: now), "in 0m")
    }

    func testTimeUntilExactlyOneHour() {
        let now = Date()
        let date = now.addingTimeInterval(3600)
        XCTAssertEqual(Formatting.timeUntil(date, now: now), "in 1h 0m")
    }

    // MARK: - progressBar

    func testProgressBarZero() {
        let bar = Formatting.progressBar(percent: 0)
        XCTAssertEqual(bar, "░░░░░░░░░░")
    }

    func testProgressBarFull() {
        let bar = Formatting.progressBar(percent: 100)
        XCTAssertEqual(bar, "██████████")
    }

    func testProgressBarHalf() {
        let bar = Formatting.progressBar(percent: 50)
        XCTAssertEqual(bar, "█████░░░░░")
    }

    func testProgressBarClampsAbove100() {
        let bar = Formatting.progressBar(percent: 150)
        XCTAssertEqual(bar, "██████████")
    }

    func testProgressBarClampsBelow0() {
        let bar = Formatting.progressBar(percent: -10)
        XCTAssertEqual(bar, "░░░░░░░░░░")
    }

    func testProgressBarCustomWidth() {
        let bar = Formatting.progressBar(percent: 50, width: 4)
        XCTAssertEqual(bar, "██░░")
    }

    // MARK: - usageStyle (fixed thresholds)

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

    // MARK: - shouldShowInMenuBar

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

    // MARK: - buildTooltip

    func testTooltipWithNoCredentials() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("configure credentials"))
    }

    func testTooltipWithUsageError() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: "Session expired", statusError: nil,
            lastRefreshed: nil, hasCredentials: true
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("⚠ Usage: Session expired"))
    }

    func testTooltipWithUsageData() {
        let now = Date()
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 42, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: UsageWindow(utilization: 18, resetsAt: now.addingTimeInterval(86400)),
            sevenDaySonnet: nil
        )
        let state = MonitorState(
            currentUsage: usage, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: now, hasCredentials: true
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("5h window: 42%"))
        XCTAssertTrue(tooltip.contains("7d window: 18%"))
        XCTAssertTrue(tooltip.contains("Updated:"))
    }

    func testTooltipWithAllSystemsOperational() {
        let status = StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: .operational)],
            incidents: [],
            status: PageStatus(indicator: "none", description: "All Systems Operational")
        )
        let state = MonitorState(
            currentUsage: nil, currentStatus: status,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("✓ All systems operational"))
    }

    func testTooltipWithIncident() {
        let status = StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: .majorOutage)],
            incidents: [Incident(id: "i1", name: "API down", status: "investigating", impact: "major", shortlink: "https://x")],
            status: PageStatus(indicator: "major", description: "Major Outage")
        )
        let state = MonitorState(
            currentUsage: nil, currentStatus: status,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("🔴 API: Major Outage"))
        XCTAssertTrue(tooltip.contains("⚠ API down"))
    }

    func testTooltipLoadingState() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("Usage: loading…"))
        XCTAssertTrue(tooltip.contains("Status: loading…"))
    }
}
