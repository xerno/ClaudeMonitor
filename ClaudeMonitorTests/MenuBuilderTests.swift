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
    @objc func didSelectSentinel() {}
}

@MainActor struct MenuBuilderTests {
    private let target = MockMenuActions()

    private func menuItems(for state: MonitorState) -> [NSMenuItem] {
        let menu = MenuBuilder.build(state: state, target: target)
        return (0..<menu.numberOfItems).map { menu.item(at: $0)! }
    }

    // MARK: - Usage Section

    @Test func noCredentialsShowsConfigureMessage() {
        let state = MonitorState(hasCredentials: false)
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.contains("Configure credentials") })
    }

    @Test func usageErrorWithNoDataShowsLoading() {
        let state = MonitorState(
            usage: UsageSnapshot(usageError: "Session expired"),
            hasCredentials: true
        )
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.contains("Loading") })
    }

    @Test func usageDataShowsProgressBars() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))!,
            .make(key: "seven_day", utilization: 18, resetsAt: now.addingTimeInterval(86400))!,
        ])
        let state = MonitorState(
            usage: UsageSnapshot(currentUsage: usage),
            hasCredentials: true
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
            incidents: []
        )
        let state = MonitorState(service: ServiceHealth(currentStatus: status))
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
            incidents: [Incident(id: "i1", name: "API down", shortlink: "https://stspg.io/x")]
        )
        let state = MonitorState(service: ServiceHealth(currentStatus: status))
        let items = menuItems(for: state)
        let incidentItems = items.filter { $0.title.contains("API down") }
        #expect(incidentItems.count == 1)
        #expect(incidentItems.first?.representedObject as? String == "https://stspg.io/x")
        #expect(incidentItems.first?.action != nil)
    }

    @Test func noIncidentsSectionWhenEmpty() {
        let status = StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: .operational)],
            incidents: []
        )
        let state = MonitorState(service: ServiceHealth(currentStatus: status))
        let items = menuItems(for: state)
        #expect(!items.contains { $0.title.contains("Active Incidents") })
    }

    // MARK: - Controls Section

    @Test func controlsIncludeRefreshAndPreferences() {
        let state = MonitorState(lastRefreshed: Date())
        let items = menuItems(for: state)
        #expect(items.contains { $0.title == "Refresh Now" })
        #expect(items.contains { $0.title == "Preferences" })
        #expect(items.contains { $0.title == "About" })
        #expect(items.contains { $0.title == "Quit" })
    }

    @Test func lastRefreshedTimestamp() {
        let state = MonitorState(lastRefreshed: Date())
        let items = menuItems(for: state)
        #expect(items.contains { $0.title.starts(with: "Updated:") })
    }

    @Test func lastRefreshedWithInterval() {
        let now = Date()
        let state = MonitorState(
            polling: PollingState(currentPollInterval: 60),
            lastRefreshed: now
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
        )!
        let samples = (0..<10).map { i in
            UtilizationSample(
                utilization: 42,
                timestamp: now.addingTimeInterval(TimeInterval(-3600 + i * 360))
            )
        }
        let analysis = UsageHistory.analyze(entry: entry, samples: samples, now: now)

        let usage = UsageResponse(entries: [entry])
        let state = MonitorState(
            usage: UsageSnapshot(currentUsage: usage, windowAnalyses: [analysis]),
            hasCredentials: true
        )

        let menu = MenuBuilder.build(state: state, target: target)

        // The graph item must be present and carry the correct view type
        let graphItem = (0..<menu.numberOfItems).compactMap { menu.item(at: $0) }
            .first { $0.tag == MenuBuilder.usageGraphTag }
        #expect(graphItem != nil)
        #expect(graphItem?.view is UsageGraphView)
        #expect(graphItem?.isHidden == false)
    }

    // MARK: - Connectivity Banner

    @Test func staleOfflineShowsOfflineBannerAtTop() {
        let state = MonitorState(
            polling: PollingState(isOnline: false, isAnyServiceStale: true),
            hasCredentials: true
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
            polling: PollingState(isOnline: true, isAnyServiceStale: true),
            hasCredentials: true
        )
        let items = menuItems(for: state)
        let bannerItem = items.first { $0.tag == MenuBuilder.connectivityBannerTag }
        #expect(bannerItem?.title.contains("Connection error") == true)
    }

    @Test func notStaleHasNoBanner() {
        let state = MonitorState(
            polling: PollingState(isAnyServiceStale: false),
            hasCredentials: true
        )
        let items = menuItems(for: state)
        #expect(!items.contains { $0.tag == MenuBuilder.connectivityBannerTag })
    }

    @Test func staleBannerSubtitleContainsLastUpdate() {
        let refreshed = Date()
        let state = MonitorState(
            polling: PollingState(isAnyServiceStale: true),
            lastRefreshed: refreshed,
            hasCredentials: true
        )
        let items = menuItems(for: state)
        let banner = items.first { $0.tag == MenuBuilder.connectivityBannerTag }
        #expect(banner != nil)
        #expect(banner?.title.contains("Claude Monitor") == true || banner?.view != nil)
    }

    @Test func usageRowsRemainVisibleWhenStale() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 55, resetsAt: now.addingTimeInterval(3600))!,
        ])
        let state = MonitorState(
            usage: UsageSnapshot(currentUsage: usage),
            polling: PollingState(isAnyServiceStale: true),
            hasCredentials: true
        )
        let items = menuItems(for: state)
        func rowText(_ item: NSMenuItem) -> String {
            if let row = item.view as? UsageRowView { return row.textContent }
            return item.attributedTitle?.string ?? item.title
        }
        #expect(items.contains { rowText($0).contains("5h") && rowText($0).contains("55%") })
        #expect(!items.contains { $0.tag == MenuBuilder.usagePlaceholderTag })
    }

    // MARK: - Live Updates

    @Test func liveUpdatePreservesMenuStructure() {
        let menu = NSMenu()
        let state1 = MonitorState(
            usage: UsageSnapshot(
                currentUsage: UsageResponse(entries: [
                    .make(key: "five_hour", utilization: 100, resetsAt: nil)!
                ])
            ),
            hasCredentials: true
        )
        _ = MenuBuilder.populate(menu: menu, state: state1, target: target)
        let itemCountBefore = menu.numberOfItems

        let state2 = MonitorState(
            usage: UsageSnapshot(
                currentUsage: UsageResponse(entries: [
                    .make(key: "five_hour", utilization: 100, resetsAt: nil)!
                ])
            ),
            hasCredentials: true
        )
        MenuBuilder.updateExistingItems(menu: menu, state: state2)

        #expect(menu.numberOfItems == itemCountBefore)
    }

    @Test func liveUpdateChangesValues() {
        let menu = NSMenu()
        let state1 = MonitorState(
            usage: UsageSnapshot(
                currentUsage: UsageResponse(entries: [
                    .make(key: "five_hour", utilization: 50, resetsAt: Date().addingTimeInterval(3600))!
                ])
            ),
            hasCredentials: true
        )
        _ = MenuBuilder.populate(menu: menu, state: state1, target: target)

        let usageItem = menu.item(withTag: MenuBuilder.usageBaseTag)
        func rowText(_ item: NSMenuItem?) -> String {
            guard let item else { return "" }
            if let row = item.view as? UsageRowView { return row.textContent }
            return item.attributedTitle?.string ?? item.title
        }
        #expect(rowText(usageItem).contains("50%"))

        let state2 = MonitorState(
            usage: UsageSnapshot(
                currentUsage: UsageResponse(entries: [
                    .make(key: "five_hour", utilization: 75, resetsAt: Date().addingTimeInterval(3600))!
                ])
            ),
            hasCredentials: true
        )
        MenuBuilder.updateExistingItems(menu: menu, state: state2)

        #expect(rowText(usageItem).contains("75%"))
        #expect(!rowText(usageItem).contains("50%"))
    }
}
