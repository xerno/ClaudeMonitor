import Foundation

enum DemoData {
    private static let allOperationalComponents = [
        StatusComponent(id: "1", name: "API", status: .operational),
        StatusComponent(id: "2", name: "Claude.ai Web", status: .operational),
        StatusComponent(id: "3", name: "claude.ai on iOS", status: .operational),
        StatusComponent(id: "4", name: "API Cloudflare Worker", status: .operational),
    ]

    static func scenario(_ number: Int) -> (UsageResponse, StatusSummary) {
        switch number {
        case 1: return scenario1()
        case 2: return scenario2()
        case 3: return scenario3()
        case 4: return scenario4()
        default: return scenario1()
        }
    }

    // Scenario 1: Normal 5h-only usage + serious incidents
    private static func scenario1() -> (UsageResponse, StatusSummary) {
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(2.7 * Constants.Time.secondsPerHour)),
            sevenDay: nil,
            sevenDaySonnet: nil
        )
        let status = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "API", status: .majorOutage),
                StatusComponent(id: "2", name: "Claude.ai Web", status: .partialOutage),
                StatusComponent(id: "3", name: "claude.ai on iOS", status: .operational),
                StatusComponent(id: "4", name: "API Cloudflare Worker", status: .operational),
            ],
            incidents: [
                Incident(
                    id: "i1",
                    name: "API Errors and Degraded Performance",
                    status: "investigating",
                    impact: "critical",
                    shortlink: "https://stspg.io/demo1a"
                ),
                Incident(
                    id: "i2",
                    name: "Elevated Error Rates on claude.ai",
                    status: "identified",
                    impact: "major",
                    shortlink: "https://stspg.io/demo1b"
                ),
            ],
            status: PageStatus(indicator: "major", description: "Major Service Outage")
        )
        return (usage, status)
    }

    // Scenario 2: Moderate 5h + 7d usage + minor incident
    private static func scenario2() -> (UsageResponse, StatusSummary) {
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 74, resetsAt: Date().addingTimeInterval(1.4 * Constants.Time.secondsPerHour)),
            sevenDay: UsageWindow(utilization: 61, resetsAt: Date().addingTimeInterval(4.2 * Constants.Time.secondsPerDay)),
            sevenDaySonnet: nil
        )
        let status = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "API", status: .degradedPerformance),
                StatusComponent(id: "2", name: "Claude.ai Web", status: .operational),
                StatusComponent(id: "3", name: "claude.ai on iOS", status: .operational),
                StatusComponent(id: "4", name: "API Cloudflare Worker", status: .operational),
            ],
            incidents: [
                Incident(
                    id: "i3",
                    name: "Increased API Latency",
                    status: "monitoring",
                    impact: "minor",
                    shortlink: "https://stspg.io/demo2"
                ),
            ],
            status: PageStatus(indicator: "minor", description: "Minor Service Disruption")
        )
        return (usage, status)
    }

    // Scenario 3: Very high 5h + 7d + Sonnet usage + no incidents
    private static func scenario3() -> (UsageResponse, StatusSummary) {
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 91, resetsAt: Date().addingTimeInterval(0.8 * Constants.Time.secondsPerHour)),
            sevenDay: UsageWindow(utilization: 85, resetsAt: Date().addingTimeInterval(1.5 * Constants.Time.secondsPerDay)),
            sevenDaySonnet: UsageWindow(utilization: 88, resetsAt: Date().addingTimeInterval(1.5 * Constants.Time.secondsPerDay))
        )
        let status = StatusSummary(
            components: allOperationalComponents,
            incidents: [],
            status: PageStatus(indicator: "none", description: "All Systems Operational")
        )
        return (usage, status)
    }

    // Scenario 4: 5h window exhausted (100%) → countdown in menu bar, small 7d + Sonnet values
    private static func scenario4() -> (UsageResponse, StatusSummary) {
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 100, resetsAt: Date().addingTimeInterval(2.25 * Constants.Time.secondsPerHour)),
            sevenDay: UsageWindow(utilization: 38, resetsAt: Date().addingTimeInterval(3.5 * Constants.Time.secondsPerDay)),
            sevenDaySonnet: UsageWindow(utilization: 22, resetsAt: Date().addingTimeInterval(3.5 * Constants.Time.secondsPerDay))
        )
        let status = StatusSummary(
            components: allOperationalComponents,
            incidents: [],
            status: PageStatus(indicator: "none", description: "All Systems Operational")
        )
        return (usage, status)
    }
}
