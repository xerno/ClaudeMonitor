import Testing
import Foundation
@testable import ClaudeMonitor

struct TooltipTests {

    @Test func tooltipWithNoCredentials() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            currentPollInterval: nil
        )
        let tooltip = Formatting.buildTooltip(state: state)
        #expect(tooltip.contains("configure credentials"))
    }

    @Test func tooltipWithUsageError() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: "Session expired", statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil
        )
        let tooltip = Formatting.buildTooltip(state: state)
        #expect(tooltip.contains("⚠ Usage: Session expired"))
    }

    @Test func tooltipWithUsageData() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600)),
            .make(key: "seven_day", utilization: 18, resetsAt: now.addingTimeInterval(86400)),
        ])
        let state = MonitorState(
            currentUsage: usage, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: now, hasCredentials: true,
            currentPollInterval: nil
        )
        let tooltip = Formatting.buildTooltip(state: state)
        #expect(tooltip.contains("5h: 42%"))
        #expect(tooltip.contains("7d: 18%"))
        #expect(tooltip.contains("Updated:"))
    }

    @Test func tooltipWithUsageDataAndInterval() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600)),
            .make(key: "seven_day", utilization: 18, resetsAt: now.addingTimeInterval(86400)),
        ])
        let state = MonitorState(
            currentUsage: usage, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: now, hasCredentials: true,
            currentPollInterval: 60
        )
        let tooltip = Formatting.buildTooltip(state: state)
        #expect(tooltip.contains("Updated:"))
        #expect(tooltip.contains("Interval:"))
        #expect(tooltip.contains("Next:"))
    }

    @Test func tooltipWithAllSystemsOperational() {
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
        #expect(tooltip.contains("✓ All systems operational"))
    }

    @Test func tooltipWithIncident() {
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
        #expect(tooltip.contains("🔴 API: Major Outage"))
        #expect(tooltip.contains("⚠ API down"))
    }

    @Test func tooltipLoadingState() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil
        )
        let tooltip = Formatting.buildTooltip(state: state)
        #expect(tooltip.contains("Usage: loading…"))
        #expect(tooltip.contains("Status: loading…"))
    }
}
