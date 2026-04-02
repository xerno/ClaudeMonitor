import XCTest
@testable import ClaudeMonitor

private final class MockMenuActions: NSObject, MenuActions {
    @objc func didSelectRefresh() {}
    @objc func openIncident(_ sender: NSMenuItem) {}
    @objc func didSelectPreferences() {}
    @objc func didSelectAbout() {}
}

final class MenuBuilderTests: XCTestCase {
    private let target = MockMenuActions()

    private func menuItems(for state: MonitorState) -> [NSMenuItem] {
        let menu = MenuBuilder.build(state: state, target: target)
        return (0..<menu.numberOfItems).map { menu.item(at: $0)! }
    }

    // MARK: - Usage Section

    func testNoCredentialsShowsConfigureMessage() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            nextPollDate: nil
        )
        let items = menuItems(for: state)
        XCTAssertTrue(items.contains { $0.title.contains("Configure credentials") })
    }

    func testUsageErrorShowsWarning() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: "Session expired", statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            nextPollDate: nil
        )
        let items = menuItems(for: state)
        XCTAssertTrue(items.contains { $0.title.contains("Session expired") })
    }

    func testUsageDataShowsProgressBars() {
        let now = Date()
        let usage = UsageResponse(
            fiveHour: UsageWindow(utilization: 42, resetsAt: now.addingTimeInterval(3600)),
            sevenDay: UsageWindow(utilization: 18, resetsAt: now.addingTimeInterval(86400)),
            sevenDaySonnet: nil
        )
        let state = MonitorState(
            currentUsage: usage, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            nextPollDate: nil
        )
        let items = menuItems(for: state)
        XCTAssertTrue(items.contains { $0.title.contains("5h window") && $0.title.contains("42%") })
        XCTAssertTrue(items.contains { $0.title.contains("7d window") && $0.title.contains("18%") })
    }

    // MARK: - Services Section

    func testComponentsAreSortedByName() {
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
            nextPollDate: nil
        )
        let items = menuItems(for: state)
        let serviceItems = items.filter { $0.title.contains("Operational") }
        XCTAssertEqual(serviceItems.count, 2)
        XCTAssertTrue(serviceItems[0].title.contains("API"))
        XCTAssertTrue(serviceItems[1].title.contains("Console"))
    }

    // MARK: - Incidents Section

    func testIncidentsShowWithLinks() {
        let status = StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: .majorOutage)],
            incidents: [Incident(id: "i1", name: "API down", status: "investigating", impact: "major", shortlink: "https://stspg.io/x")],
            status: PageStatus(indicator: "major", description: "Outage")
        )
        let state = MonitorState(
            currentUsage: nil, currentStatus: status,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            nextPollDate: nil
        )
        let items = menuItems(for: state)
        let incidentItems = items.filter { $0.title.contains("API down") }
        XCTAssertEqual(incidentItems.count, 1)
        XCTAssertEqual(incidentItems.first?.representedObject as? String, "https://stspg.io/x")
        XCTAssertNotNil(incidentItems.first?.action)
    }

    func testNoIncidentsSectionWhenEmpty() {
        let status = StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: .operational)],
            incidents: [],
            status: PageStatus(indicator: "none", description: "OK")
        )
        let state = MonitorState(
            currentUsage: nil, currentStatus: status,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: false,
            nextPollDate: nil
        )
        let items = menuItems(for: state)
        XCTAssertFalse(items.contains { $0.title.contains("Active Incidents") })
    }

    // MARK: - Controls Section

    func testControlsIncludeRefreshAndPreferences() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: Date(), hasCredentials: false,
            nextPollDate: nil
        )
        let items = menuItems(for: state)
        XCTAssertTrue(items.contains { $0.title == "Refresh Now" })
        XCTAssertTrue(items.contains { $0.title == "Preferences" })
        XCTAssertTrue(items.contains { $0.title == "About" })
        XCTAssertTrue(items.contains { $0.title == "Quit" })
    }

    func testLastRefreshedTimestamp() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: Date(), hasCredentials: false,
            nextPollDate: nil
        )
        let items = menuItems(for: state)
        XCTAssertTrue(items.contains { $0.title.starts(with: "Updated:") })
    }

    func testLastRefreshedWithNextPollDate() {
        let now = Date()
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: now, hasCredentials: false,
            nextPollDate: now.addingTimeInterval(60)
        )
        let items = menuItems(for: state)
        XCTAssertTrue(items.contains { $0.title.starts(with: "Updated:") && $0.title.contains("Next:") })
    }
}
