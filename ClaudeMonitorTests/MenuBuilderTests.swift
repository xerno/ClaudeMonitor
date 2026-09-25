import Testing
import AppKit
@testable import ClaudeMonitor

@MainActor
private final class MockMenuActions: NSObject, MenuActions {
    private(set) var refreshCount = 0
    private(set) var selectedProfileIds: [String] = []

    @objc func didSelectRefresh() { refreshCount += 1 }
    @objc func openIncident(_ sender: NSMenuItem) {}
    @objc func didSelectPreferences() {}
    @objc func didSelectAbout() {}
    @objc func didSelectUsageWindow(_ sender: NSMenuItem) {}
    @objc func didSelectSentinel() {}
    @objc func didSelectProfile(id: String) { selectedProfileIds.append(id) }
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

    @Test func affectedComponentsAreSortedByName() {
        let status = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "Console", status: .partialOutage),
                StatusComponent(id: "2", name: "API", status: .majorOutage),
            ],
            incidents: []
        )
        let items = menuItems(for: MonitorState(service: ServiceHealth(currentStatus: status)))
        let serviceItems = items.filter { $0.tag >= MenuBuilder.serviceBaseTag && $0.tag < MenuBuilder.servicesPlaceholderTag }
        #expect(serviceItems.count == 2)
        #expect(serviceItems[0].title.contains("API"))
        #expect(serviceItems[1].title.contains("Console"))
    }

    @Test func allOperationalCollapsesToOneLine() {
        let status = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "API", status: .operational),
                StatusComponent(id: "2", name: "Console", status: .operational),
            ],
            incidents: []
        )
        let items = menuItems(for: MonitorState(service: ServiceHealth(currentStatus: status)))
        #expect(!items.contains { $0.tag >= MenuBuilder.serviceBaseTag && $0.tag < MenuBuilder.servicesPlaceholderTag })
    }

    private func mixedServicesState(compact: Bool) -> MonitorState {
        let status = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "Console", status: .majorOutage),
                StatusComponent(id: "2", name: "Billing", status: .operational),
                StatusComponent(id: "3", name: "APIs", status: .partialOutage),
            ],
            incidents: []
        )
        return MonitorState(service: ServiceHealth(currentStatus: status), compactServices: compact)
    }

    private func serviceRowTitles(in menu: NSMenu) -> [String] {
        menu.items
            .filter { $0.tag >= MenuBuilder.serviceBaseTag && $0.tag < MenuBuilder.servicesPlaceholderTag }
            .map(\.title)
    }

    @Test func compactModeShowsOnlyAffectedComponents() {
        let menu = MenuBuilder.build(state: mixedServicesState(compact: true), target: target)
        let titles = serviceRowTitles(in: menu)
        #expect(titles.count == 2)
        #expect(titles.first?.contains("APIs") == true)
        #expect(titles.last?.contains("Console") == true)
        #expect(!titles.contains { $0.contains("Billing") })
    }

    @Test func fullModeListsAllComponents() throws {
        let menu = MenuBuilder.build(state: mixedServicesState(compact: false), target: target)
        let titles = serviceRowTitles(in: menu)
        try #require(titles.count == 3)
        #expect(titles[0].contains("APIs"))
        #expect(titles[1].contains("Billing"))
        #expect(titles[2].contains("Console"))
    }

    @Test func liveUpdateInCompactModeKeepsAffectedRowsAligned() throws {
        let state = mixedServicesState(compact: true)
        let menu = MenuBuilder.build(state: state, target: target)

        MenuBuilder.updateExistingItems(menu: menu, state: state)

        let first = try #require(menu.item(withTag: MenuBuilder.serviceBaseTag))
        let second = try #require(menu.item(withTag: MenuBuilder.serviceBaseTag + 1))
        #expect(first.title.contains("APIs"))
        #expect(second.title.contains("Console"))
        #expect(menu.item(withTag: MenuBuilder.serviceBaseTag + 2) == nil)
        #expect(!serviceRowTitles(in: menu).contains { $0.contains("Billing") })
    }

    @Test func liveUpdateInFullModeKeepsSortedNamesInPlace() throws {
        let state = mixedServicesState(compact: false)
        let menu = MenuBuilder.build(state: state, target: target)

        MenuBuilder.updateExistingItems(menu: menu, state: state)

        let names = ["APIs", "Billing", "Console"]
        for (index, name) in names.enumerated() {
            let item = try #require(menu.item(withTag: MenuBuilder.serviceBaseTag + index))
            #expect(item.title.contains(name))
        }
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

    @Test func footerActionBarPresentWithFourButtons() {
        let menu = MenuBuilder.build(state: MonitorState(lastRefreshed: Date()), target: target)
        let buttons = MenuBuilder.footerButtons(in: menu)
        let expected = ["Refresh Now", "Preferences", "About", "Quit"]
        #expect(buttons.count == 4)
        #expect(buttons.map { $0.toolTip ?? "" } == expected)
        #expect(buttons.map { $0.accessibilityLabel() ?? "" } == expected)
        #expect(buttons.allSatisfy { $0.isAccessibilityElement() && $0.accessibilityRole() == .button })
    }

    @Test func footerRefreshButtonInvokesTarget() throws {
        let menu = MenuBuilder.build(state: MonitorState(lastRefreshed: Date()), target: target)
        let refresh = try #require(MenuBuilder.footerButtons(in: menu).first)
        #expect(refresh.accessibilityPerformPress())
        #expect(target.refreshCount == 1)
    }

    @Test func hiddenShortcutItemsCarryKeyEquivalents() throws {
        let menu = MenuBuilder.build(state: MonitorState(lastRefreshed: Date()), target: target)
        let shortcuts: [(tag: Int, key: String, action: Selector)] = [
            (MenuBuilder.refreshTag, "r", #selector(MenuActions.didSelectRefresh)),
            (MenuBuilder.preferencesTag, ",", #selector(MenuActions.didSelectPreferences)),
            (MenuBuilder.quitTag, "q", #selector(NSApplication.terminate(_:))),
        ]
        for shortcut in shortcuts {
            let item = try #require(menu.item(withTag: shortcut.tag))
            #expect(item.isHidden)
            #expect(item.allowsKeyEquivalentWhenHidden)
            #expect(item.keyEquivalent == shortcut.key)
            #expect(item.keyEquivalentModifierMask == .command)
            #expect(item.action == shortcut.action)
        }
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

    @Test func liveUpdateCacheKeepsCountdownOnNewDataAndDropsVanishedRows() throws {
        let menu = NSMenu()
        let resetsAt = Date().addingTimeInterval(3600)
        let before = MonitorState(
            usage: UsageSnapshot(currentUsage: UsageResponse(entries: [
                .make(key: "five_hour", utilization: 50, resetsAt: resetsAt)!,
                .make(key: "seven_day", utilization: 20, resetsAt: resetsAt.addingTimeInterval(86400))!,
            ])),
            hasCredentials: true
        )
        MenuBuilder.populate(menu: menu, state: before, target: target)
        #expect(menu.item(withTag: MenuBuilder.usageBaseTag + 1) != nil)

        let after = MonitorState(
            usage: UsageSnapshot(currentUsage: UsageResponse(entries: [
                .make(key: "five_hour", utilization: 75, resetsAt: resetsAt)!,
            ])),
            hasCredentials: true
        )
        let cache = MenuBuilder.updateExistingItems(menu: menu, state: after)
        MenuBuilder.refreshTimes(in: menu, cache: cache)

        let row = try #require(menu.item(withTag: MenuBuilder.usageBaseTag)?.view as? UsageRowView)
        #expect(row.textContent.contains("75%"))
        #expect(!row.textContent.contains("50%"))
        #expect(menu.item(withTag: MenuBuilder.usageBaseTag + 1) == nil)
    }

    @Test func liveUpdateSwapsPreviousAccountRowsForLoadingAndBack() throws {
        let menu = NSMenu()
        let resetsAt = Date().addingTimeInterval(3600)
        let previousAccount = MonitorState(
            usage: UsageSnapshot(currentUsage: UsageResponse(entries: [
                .make(key: "five_hour", utilization: 50, resetsAt: resetsAt)!,
                .make(key: "seven_day", utilization: 20, resetsAt: resetsAt.addingTimeInterval(86400))!,
            ])),
            hasCredentials: true
        )
        MenuBuilder.populate(menu: menu, state: previousAccount, target: target)

        let switched = MonitorState(usage: UsageSnapshot(currentUsage: nil), hasCredentials: true)
        let loadingCache = MenuBuilder.updateExistingItems(menu: menu, state: switched, target: target)

        #expect(loadingCache.labels.isEmpty)
        #expect(menu.item(withTag: MenuBuilder.usageBaseTag) == nil)
        #expect(menu.item(withTag: MenuBuilder.usageBaseTag + 1) == nil)
        #expect(menu.item(withTag: MenuBuilder.usagePlaceholderTag) != nil)

        let newAccount = MonitorState(
            usage: UsageSnapshot(currentUsage: UsageResponse(entries: [
                .make(key: "five_hour", utilization: 75, resetsAt: resetsAt)!,
            ])),
            hasCredentials: true
        )
        let freshCache = MenuBuilder.updateExistingItems(menu: menu, state: newAccount, target: target)

        #expect(freshCache.labels.count == 1)
        #expect(menu.item(withTag: MenuBuilder.usagePlaceholderTag) == nil)
        let row = try #require(menu.item(withTag: MenuBuilder.usageBaseTag)?.view as? UsageRowView)
        #expect(row.textContent.contains("75%"))
    }

    // MARK: - Row highlighting

    private func highlightMenu() -> NSMenu {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))!,
            .make(key: "seven_day", utilization: 18, resetsAt: now.addingTimeInterval(86400))!,
        ])
        return MenuBuilder.build(state: MonitorState(usage: UsageSnapshot(currentUsage: usage), hasCredentials: true),
                                 target: target)
    }

    private func usageRows(in menu: NSMenu) -> [UsageRowView] {
        menu.items.compactMap { $0.view as? UsageRowView }
    }

    @Test func syncHighlightLightsExactlyOneRow() {
        let menu = highlightMenu()
        let rows = usageRows(in: menu)
        #expect(rows.count >= 2)

        let secondItem = menu.item(withTag: MenuBuilder.usageBaseTag + 1)
        MenuBuilder.syncHighlight(in: menu, highlighted: secondItem)
        #expect(secondItem?.view as? UsageRowView === rows[1])
        let afterSecond = rows.map(\.isHighlighted)
        #expect(afterSecond == [false, true])

        // Moving the highlight must clear the row that had it — the stuck-highlight bug.
        let firstItem = menu.item(withTag: MenuBuilder.usageBaseTag)
        MenuBuilder.syncHighlight(in: menu, highlighted: firstItem)
        let afterFirst = rows.map(\.isHighlighted)
        #expect(afterFirst == [true, false])
    }

    @Test func syncHighlightWithNilClearsEveryRow() {
        let menu = highlightMenu()
        let rows = usageRows(in: menu)
        MenuBuilder.syncHighlight(in: menu, highlighted: menu.item(withTag: MenuBuilder.usageBaseTag))
        let lit = rows.map(\.isHighlighted)
        #expect(lit == [true, false])

        // What menuDidClose does: a closed menu has no highlighted row, so the highlight
        // cannot survive into the next time the menu opens.
        MenuBuilder.syncHighlight(in: menu, highlighted: nil)
        let cleared = rows.map(\.isHighlighted)
        #expect(cleared == [false, false])
    }

    @Test func syncHighlightIgnoresItemFromAnotherMenu() {
        let menu = highlightMenu()
        let rows = usageRows(in: menu)
        MenuBuilder.syncHighlight(in: menu, highlighted: NSMenuItem())
        let states = rows.map(\.isHighlighted)
        #expect(states == [false, false])
    }

    // MARK: - History health

    @Test func noHistoryHealthItemWhenNothingToReport() {
        let state = MonitorState(history: HistoryHealth())
        #expect(MenuBuilder.historyHealthItem(state: state) == nil)
    }

    private static let personalAndWork = [
        Profile(id: "a", name: "Personal", organizationId: "org-a"),
        Profile(id: "b", name: "Work", organizationId: "org-b"),
    ]

    private func stateWithProfiles(
        _ profiles: [Profile] = personalAndWork,
        activeId: String = "b",
        isStale: Bool = false,
        usageBlocked: Bool = false
    ) -> MonitorState {
        let entries = [WindowEntry.make(key: "five_hour", utilization: usageBlocked ? 100 : 40,
                                        resetsAt: Date().addingTimeInterval(3600))].compactMap { $0 }
        return MonitorState(
            usage: UsageSnapshot(currentUsage: UsageResponse(entries: entries)),
            polling: PollingState(isAnyServiceStale: isStale),
            profiles: ProfileSnapshot(profiles: profiles, activeId: activeId),
            hasCredentials: true
        )
    }

    private func usageHeaderToggle(in menu: NSMenu) -> AccountToggleView? {
        MenuBuilder.findAccountToggle(in: menu.item(withTag: MenuBuilder.usageSectionTag)?.view)
    }

    @Test func accountToggleAbsentWithSingleProfile() {
        let state = stateWithProfiles([Profile(id: "a", name: "Personal", organizationId: "org-a")], activeId: "a")
        let menu = MenuBuilder.build(state: state, target: target)
        #expect(usageHeaderToggle(in: menu) == nil)
    }

    @Test func accountTogglePresentInUsageHeaderWithTwoProfiles() {
        let menu = MenuBuilder.build(state: stateWithProfiles(), target: target)
        #expect(usageHeaderToggle(in: menu) != nil)
    }

    @Test func switcherSelectsActiveProfileIndex() throws {
        let menu = MenuBuilder.build(state: stateWithProfiles(activeId: "b"), target: target)
        let toggle = try #require(usageHeaderToggle(in: menu))
        #expect(toggle.selectedIndex == 1)
    }

    @Test func populateUpdatesToggleSelectionInPlace() throws {
        let menu = NSMenu()
        MenuBuilder.populate(menu: menu, state: stateWithProfiles(activeId: "b"), target: target)
        let original = try #require(usageHeaderToggle(in: menu))

        MenuBuilder.populate(menu: menu, state: stateWithProfiles(activeId: "a"), target: target)

        let updated = try #require(usageHeaderToggle(in: menu))
        #expect(updated === original)
        #expect(updated.selectedIndex == 0)
    }

    @Test func switcherReplacedWhenIdsChangeEvenIfLabelsEqual() throws {
        let menu = NSMenu()
        MenuBuilder.populate(menu: menu, state: stateWithProfiles(activeId: "a"), target: target)
        let original = try #require(usageHeaderToggle(in: menu))

        let renumbered = [
            Profile(id: "c", name: "Personal", organizationId: "org-c"),
            Profile(id: "d", name: "Work", organizationId: "org-d"),
        ]
        MenuBuilder.populate(menu: menu, state: stateWithProfiles(renumbered, activeId: "c"), target: target)

        let replaced = try #require(usageHeaderToggle(in: menu))
        #expect(replaced !== original)
        #expect(replaced.currentSegments.map(\.id) == ["c", "d"])

        replaced.select(segmentAt: 1)
        #expect(target.selectedProfileIds == ["d"])
    }

    @Test func switcherPresentWhenServiceStale() throws {
        let built = MenuBuilder.build(state: stateWithProfiles(isStale: true), target: target)
        #expect(usageHeaderToggle(in: built) != nil)

        let menu = NSMenu()
        MenuBuilder.populate(menu: menu, state: stateWithProfiles(), target: target)
        MenuBuilder.populate(menu: menu, state: stateWithProfiles(isStale: true), target: target)
        #expect(usageHeaderToggle(in: menu) != nil)
    }

    @Test func switcherTruncatesLongNames() throws {
        let longName = "Personal Account With A Long Name"
        let profiles = [
            Profile(id: "a", name: longName, organizationId: "org-a"),
            Profile(id: "b", name: "Work", organizationId: "org-b"),
        ]
        let menu = MenuBuilder.build(state: stateWithProfiles(profiles), target: target)
        let toggle = try #require(usageHeaderToggle(in: menu))

        let label = toggle.currentSegments[0].label
        #expect(label.count == MenuBuilder.switcherNameMaxLength)
        #expect(label.hasSuffix("…"))
        #expect(longName.hasPrefix(String(label.dropLast())))
        #expect(toggle.currentSegments[1].label == "Work")
        #expect(toggle.currentSegments[0].toolTip == longName)
        #expect(toggle.currentSegments[1].toolTip == "Work")

        let tooltips = toggle.subviews.compactMap(\.toolTip)
        #expect(tooltips == [longName, "Work"])
    }

    @Test func populateRebuildsTitleHeaderWhenBadgeChanges() throws {
        let menu = NSMenu()
        MenuBuilder.populate(menu: menu, state: stateWithProfiles(usageBlocked: false), target: target)
        let originalToggle = try #require(usageHeaderToggle(in: menu))
        #expect(MenuBuilder.titleHeaderBadgeText(in: menu.item(withTag: MenuBuilder.usageSectionTag)?.view) == nil)

        MenuBuilder.populate(menu: menu, state: stateWithProfiles(usageBlocked: true), target: target)

        let header = menu.item(withTag: MenuBuilder.usageSectionTag)?.view
        #expect(MenuBuilder.titleHeaderBadgeText(in: header) != nil)
        let updatedToggle = try #require(usageHeaderToggle(in: menu))
        #expect(updatedToggle !== originalToggle)
    }

    @Test func graphShownByDefault() {
        let state = MonitorState(usage: UsageSnapshot(currentUsage: UsageResponse(entries: [])), hasCredentials: true)
        #expect(menuItems(for: state).contains { $0.tag == MenuBuilder.usageGraphTag })
    }

    @Test func graphHiddenWhenDisabled() {
        let state = MonitorState(usage: UsageSnapshot(currentUsage: UsageResponse(entries: [])), hasCredentials: true, showGraph: false)
        #expect(!menuItems(for: state).contains { $0.tag == MenuBuilder.usageGraphTag })
    }
}


/// Header shades. A section header's two labels share one quiet shade so the row reads as a single
/// line — except the Services status, which the redesign gives its own green, and the dropdown's
/// title, which is the one loud thing at the top.
@MainActor
struct MenuBuilderHeaderShadeTests {

    /// Recursive on purpose. The non-recursive version returned `[]` for any header built into a
    /// container, and `allSatisfy` on an empty array is `true` — the shade tests would have gone on
    /// passing while checking nothing. Callers assert the count as well, for the same reason.
    private func labels(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { subview -> [NSTextField] in
            if let field = subview as? NSTextField { return [field] }
            return labels(in: subview)
        }
    }

    @Test func bothHeaderLabelsShareOneShade() throws {
        let view = MenuBuilder.makeHeaderView(title: "Usage", subtitle: "Claude Monitor")
        let found = labels(in: view)
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.textColor == MenuBuilder.headerTextColor })
    }

    /// The subtitle colour is opt-in: a header that does not ask for one still matches every other
    /// header, so the green below stays the deliberate exception rather than the start of a drift.
    @Test func headersWithoutAnExplicitColourStillMatchEachOther() throws {
        let usage = labels(in: MenuBuilder.makeHeaderView(title: "Usage", subtitle: "Claude Monitor"))
        let services = labels(in: MenuBuilder.makeHeaderView(title: "Services", subtitle: "Operational"))
        let shades = Set((usage + services).compactMap { $0.textColor })
        #expect(shades.count == 1, "every header label should resolve to the same colour")
    }

    /// The shade is deliberately the same token the "Updated / Interval / Next" line already uses,
    /// which is the line Marek pointed at as the reference.
    @Test func headerShadeMatchesTheControlRow() throws {
        #expect(MenuBuilder.headerTextColor == .secondaryLabelColor)
        let control = ControlRowView(title: "Updated: 10:00:00")
        let label = try #require(control.subviews.compactMap { $0 as? NSTextField }.first)
        #expect(label.textColor == MenuBuilder.headerTextColor)
    }

    @Test func sectionHeaderCarriesTheSharedShade() throws {
        let item = MenuBuilder.sectionHeader("Services", subtitle: "Operational", tag: 1)
        let view = try #require(item.view)
        let found = labels(in: view)
        #expect(found.count == 2)
        #expect(found.allSatisfy { $0.textColor == MenuBuilder.headerTextColor })
    }

    /// Pins the built menu, not just the helper: the services header is the one compact mode relies
    /// on. The section word stays quiet; only the status it summarises turns green.
    @Test func servicesHeaderKeepsAGreyWordAndAGreenStatus() throws {
        let state = MonitorState(
            service: ServiceHealth(currentStatus: StatusSummary(
                components: [StatusComponent(id: "1", name: "API", status: .operational)],
                incidents: []
            )),
            compactServices: true
        )
        let (items, _) = MenuBuilder.buildDesiredItems(state: state, target: HeaderShadeMockActions())
        let header = try #require(items.first { $0.tag == MenuBuilder.servicesSectionTag })
        let view = try #require(header.view, "compact + all-operational should render a subtitle view")
        let found = labels(in: view)
        #expect(found.count == 2)
        #expect(found.first?.textColor == MenuBuilder.headerTextColor)
        #expect(found.last?.textColor == .restingAccent)
    }

    /// The bar and the services status are meant to be one green, not two that happen to match
    /// today. Measured against `barFillColor` rather than against the constant, so renaming or
    /// re-pointing either surface alone fails here.
    @Test func theServicesStatusUsesTheSameGreenAsARestingBar() throws {
        let state = MonitorState(
            service: ServiceHealth(currentStatus: StatusSummary(
                components: [StatusComponent(id: "1", name: "API", status: .operational)],
                incidents: []
            )),
            compactServices: true
        )
        let (items, _) = MenuBuilder.buildDesiredItems(state: state, target: HeaderShadeMockActions())
        let header = try #require(items.first { $0.tag == MenuBuilder.servicesSectionTag })
        let view = try #require(header.view)
        let status = try #require(labels(in: view).last)
        #expect(status.textColor == Formatting.barFillColor(percent: 60))
    }
}

@MainActor
private final class HeaderShadeMockActions: NSObject, MenuActions {
    @objc func didSelectRefresh() {}
    @objc func openIncident(_ sender: NSMenuItem) {}
    @objc func didSelectPreferences() {}
    @objc func didSelectAbout() {}
    @objc func didSelectUsageWindow(_ sender: NSMenuItem) {}
    @objc func didSelectSentinel() {}
    @objc func didSelectProfile(id: String) {}
}
