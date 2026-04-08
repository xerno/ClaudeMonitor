import Testing
import AppKit
@testable import ClaudeMonitor

@MainActor
private final class MockMenuActions: NSObject, MenuActions {
    @objc func didSelectRefresh() {}
    @objc func openIncident(_ sender: NSMenuItem) {}
    @objc func didSelectPreferences() {}
    @objc func didSelectAbout() {}
}

@MainActor struct MenuBuilderTests {
    private let target = MockMenuActions()

    private func menuItems(for state: MonitorState) -> [NSMenuItem] {
        let menu = MenuBuilder.build(state: state, target: target)
        return (0..<menu.numberOfItems).map { menu.item(at: $0)! }
    }

    // MARK: - Usage Section

    @Test func noCredentialsShowsConfigureMessage() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.contains("Configure credentials") })
    }

    @Test func usageErrorShowsWarning() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: "Session expired", statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.contains("Session expired") })
    }

    @Test func usageDataShowsProgressBars() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600)),
            .make(key: "seven_day", utilization: 18, resetsAt: now.addingTimeInterval(86400)),
        ])
        let state = MonitorState(
            currentUsage: usage, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.contains("5h") && $0.title.contains("42%") })
        #expect(items.contains { $0.title.contains("7d") && $0.title.contains("18%") })
    }

    // MARK: - Services Section

    @Test func componentsAreSortedByName() {
        let status = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "Console", status: .operational),
                StatusComponent(id: "2", name: "API", status: .operational),
            ],
            incidents: [],
            status: PageStatus(indicator: "none", description: "OK")
        )
        let state = MonitorState(
            currentUsage: nil, currentStatus: status,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        let serviceItems = items.filter { $0.title.contains("Operational") }
        #expect(serviceItems.count == 2)
        #expect(serviceItems[0].title.contains("API"))
        #expect(serviceItems[1].title.contains("Console"))
    }

    // MARK: - Incidents Section

    @Test func incidentsShowWithLinks() {
        let status = StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: .majorOutage)],
            incidents: [Incident(id: "i1", name: "API down", status: "investigating", impact: "major", shortlink: "https://stspg.io/x")],
            status: PageStatus(indicator: "major", description: "Outage")
        )
        let state = MonitorState(
            currentUsage: nil, currentStatus: status,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        let incidentItems = items.filter { $0.title.contains("API down") }
        #expect(incidentItems.count == 1)
        #expect(incidentItems.first?.representedObject as? String == "https://stspg.io/x")
        #expect(incidentItems.first?.action != nil)
    }

    @Test func noIncidentsSectionWhenEmpty() {
        let status = StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: .operational)],
            incidents: [],
            status: PageStatus(indicator: "none", description: "OK")
        )
        let state = MonitorState(
            currentUsage: nil, currentStatus: status,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        #expect(!items.contains { $0.title.contains("Active Incidents") })
    }

    // MARK: - Controls Section

    @Test func controlsIncludeRefreshAndPreferences() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: Date(), hasCredentials: false,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        #expect(items.contains { $0.title == "Refresh Now" })
        #expect(items.contains { $0.title == "Preferences" })
        #expect(items.contains { $0.title == "About" })
        #expect(items.contains { $0.title == "Quit" })
    }

    @Test func lastRefreshedTimestamp() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: Date(), hasCredentials: false,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.starts(with: "Updated:") })
    }

    @Test func lastRefreshedWithInterval() {
        let now = Date()
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: now, hasCredentials: false,
            currentPollInterval: 60
        )
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.starts(with: "Updated:") && $0.title.contains("Interval:") && $0.title.contains("Next:") })
    }
}
