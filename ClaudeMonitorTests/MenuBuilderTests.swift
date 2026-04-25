import Testing
import AppKit
@testable import ClaudeMonitor

@MainActor
private final class MockMenuActions: NSObject, MenuActions {
    @objc func didSelectRefresh() {}
    @objc func openIncident(_ sender: NSMenuItem) {}
    @objc func didSelectPreferences() {}
    @objc func didSelectAbout() {}
    @objc func didSelectUsageWindow(_ sender: NSMenuItem) {}
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

    @Test func usageErrorWithNoDataShowsLoading() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: "Session expired", statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil
        )
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.contains("Loading") })
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
        func rowText(_ item: NSMenuItem) -> String {
            if let row = item.view as? UsageRowView {
                return row.textContent
            }
            return item.attributedTitle?.string ?? item.title
        }
        #expect(items.contains { rowText($0).contains("5h") && rowText($0).contains("42%") })
        #expect(items.contains { rowText($0).contains("7d") && rowText($0).contains("18%") })
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

    // MARK: - WindowAnalyses Integration

    @Test func windowAnalysesArePassedToGraphView() {
        let now = Date()
        let entry = WindowEntry.make(
            key: "five_hour",
            utilization: 42,
            resetsAt: now.addingTimeInterval(3600)
        )
        let samples = (0..<10).map { i in
            UtilizationSample(
                utilization: 42,
                timestamp: now.addingTimeInterval(TimeInterval(-3600 + i * 360))
            )
        }
        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        let usage = UsageResponse(entries: [entry])
        let state = MonitorState(
            currentUsage: usage, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil,
            windowAnalyses: [analysis]
        )

        let menu = MenuBuilder.build(state: state, target: target)

        // The graph placeholder item must be present
        let graphItem = (0..<menu.numberOfItems).compactMap { menu.item(at: $0) }
            .first { $0.tag == MenuBuilder.usageGraphTag }
        #expect(graphItem != nil)
        #expect(graphItem?.view is UsageGraphView)

        // The analysis must have non-empty segments (tracked data was provided)
        #expect(!analysis.segments.isEmpty)
        // consumptionRate should be non-zero because resetsAt is set and time has elapsed
        #expect(analysis.consumptionRate > 0)
    }

    // MARK: - Connectivity Banner

    @Test func staleOfflineShowsOfflineBannerAtTop() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil,
            isOnline: false,
            isStale: true
        )
        let items = menuItems(for: state)
        let bannerIndex = items.firstIndex { $0.tag == MenuBuilder.connectivityBannerTag }
        #expect(bannerIndex != nil)
        #expect(items[bannerIndex!].title.contains("Offline"))
        let separatorIndex = items.firstIndex { $0.tag == MenuBuilder.separatorAfterConnectivityTag }
        #expect(separatorIndex == bannerIndex.map { $0 + 1 })
    }

    @Test func staleOnlineShowsConnectionErrorBanner() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil,
            isOnline: true,
            isStale: true
        )
        let items = menuItems(for: state)
        let bannerItem = items.first { $0.tag == MenuBuilder.connectivityBannerTag }
        #expect(bannerItem?.title.contains("Connection error") == true)
    }

    @Test func notStaleHasNoBanner() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil,
            isStale: false
        )
        let items = menuItems(for: state)
        #expect(!items.contains { $0.tag == MenuBuilder.connectivityBannerTag })
    }

    @Test func warnThresholdShowsLastFailedRow() {
        let failedAt = Date()
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil,
            hasRecentFailure: true,
            lastFailedAt: failedAt,
            isStale: false
        )
        let items = menuItems(for: state)
        let failedItem = items.first { $0.tag == MenuBuilder.lastFailedRowTag }
        #expect(failedItem != nil)
        let expectedTime = failedAt.formatted(.dateTime.hour().minute().second())
        #expect(failedItem?.title.contains(expectedTime) == true)
    }

    @Test func staleHidesLastFailedRow() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil,
            hasRecentFailure: true,
            lastFailedAt: Date(),
            isStale: true
        )
        let items = menuItems(for: state)
        #expect(!items.contains { $0.tag == MenuBuilder.lastFailedRowTag })
    }

    @Test func noFailureNoLastFailedRow() {
        let state = MonitorState(
            currentUsage: nil, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil,
            hasRecentFailure: false
        )
        let items = menuItems(for: state)
        #expect(!items.contains { $0.tag == MenuBuilder.lastFailedRowTag })
    }

    @Test func usageRowsRemainVisibleWhenStale() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 55, resetsAt: now.addingTimeInterval(3600)),
        ])
        let state = MonitorState(
            currentUsage: usage, currentStatus: nil,
            usageError: nil, statusError: nil,
            lastRefreshed: nil, hasCredentials: true,
            currentPollInterval: nil,
            isStale: true
        )
        let items = menuItems(for: state)
        func rowText(_ item: NSMenuItem) -> String {
            if let row = item.view as? UsageRowView { return row.textContent }
            return item.attributedTitle?.string ?? item.title
        }
        #expect(items.contains { rowText($0).contains("5h") && rowText($0).contains("55%") })
        #expect(!items.contains { $0.tag == MenuBuilder.usagePlaceholderTag })
    }
}
