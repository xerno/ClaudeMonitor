import XCTest
@testable import ClaudeMonitor

final class TooltipTests: XCTestCase {

    func testTooltipWithNoCredentials() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            currentPollInterval: nil
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("configure credentials"))
    }

    func testTooltipWithUsageError() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: "Session expired", statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil
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
            lastRefreshed: now, hasCredentials: true,
            currentPollInterval: nil
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
            lastRefreshed: nil, hasCredentials: false,
            currentPollInterval: nil
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
            lastRefreshed: nil, hasCredentials: false,
            currentPollInterval: nil
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("🔴 API: Major Outage"))
        XCTAssertTrue(tooltip.contains("⚠ API down"))
    }

    func testTooltipLoadingState() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil
        )
        let tooltip = Formatting.buildTooltip(state: state)
        XCTAssertTrue(tooltip.contains("Usage: loading…"))
        XCTAssertTrue(tooltip.contains("Status: loading…"))
    }
}
