import Testing
import AppKit
@testable import ClaudeMonitor

@MainActor
struct UICompositionTests {

    // MARK: - Shared helpers

    private func makeState(
        usage: UsageResponse?,
        analyses: [WindowAnalysis] = [],
        hasCredentials: Bool = true
    ) -> MonitorState {
        MonitorState(
            usage: UsageSnapshot(currentUsage: usage, windowAnalyses: analyses),
            hasCredentials: hasCredentials
        )
    }

    private final class MockActions: NSObject, MenuActions {
        @objc func didSelectRefresh() {}
        @objc func openIncident(_ sender: NSMenuItem) {}
        @objc func didSelectPreferences() {}
        @objc func didSelectAbout() {}
        @objc func didSelectUsageWindow(_ sender: NSMenuItem) {}
        @objc func didSelectSentinel() {}
        @objc func didSelectProfile(id: String) {}
    }

    // MARK: - usageTitle reads style from WindowAnalysis (analysisByKey lookup path)

    @Test func usageTitleUsesStyleFromWindowAnalysisWhenProvided() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(18000 * 0.9)
        let entry = WindowEntry.make(key: "five_hour", utilization: 10, resetsAt: resetsAt)!
        let usage = UsageResponse(entries: [entry])

        let criticalEntry = WindowEntry.make(
            key: "five_hour",
            utilization: 65,
            resetsAt: now.addingTimeInterval(9000)
        )!
        let samples: [UtilizationSample] = []
        let analysis = UsageHistory.analyze(entry: criticalEntry, samples: samples, now: now)

        #expect(analysis.style.level == .critical)

        let usageForCritical = UsageResponse(entries: [criticalEntry])
        let title = StatusBarRenderer.usageTitle(usage: usageForCritical, windowAnalyses: [analysis])

        #expect(!title.string.isEmpty)
        #expect(title.string.contains("65%"))

        // Inline styling is also critical for this entry, so this alone cannot show the analysis was used.
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .systemRed)

        // A critical analysis for another window (seven_day) must not restyle this five_hour entry.
        let mismatchedAnalysis = UsageHistory.analyze(
            entry: WindowEntry.make(key: "seven_day", utilization: 65,
                                    resetsAt: now.addingTimeInterval(302_400))!,
            samples: [],
            now: now
        )
        let titleWithMismatch = StatusBarRenderer.usageTitle(usage: usage, windowAnalyses: [mismatchedAnalysis])
        let fallbackColor = titleWithMismatch.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(fallbackColor == .labelColor)
    }

    // MARK: - populate → refreshTimes round-trip updates menu item titles

    @Test func populateThenRefreshTimesUpdatesMenuItemTitles() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let usage = UsageResponse(entries: [
            WindowEntry.make(key: "five_hour", utilization: 42, resetsAt: resetsAt)!,
        ])
        let state = makeState(usage: usage)
        let target = MockActions()
        let menu = NSMenu()

        let cache = MenuBuilder.populate(menu: menu, state: state, target: target)

        #expect(!cache.labels.isEmpty)
        let windowedLabels = cache.labels.filter { $0.window?.resetsAt != nil }
        #expect(!windowedLabels.isEmpty)

        #expect(!cache.prefixes.isEmpty)

        MenuBuilder.refreshTimes(in: menu, cache: cache)

        for (tag, _, window) in cache.labels where window?.resetsAt != nil {
            guard let item = menu.item(withTag: tag) else {
                Issue.record("Expected menu item with tag \(tag) not found")
                continue
            }
            let titleString: String
            if let rowView = item.view as? UsageRowView {
                titleString = rowView.textContent
            } else {
                titleString = item.attributedTitle?.string ?? ""
            }
            #expect(!titleString.isEmpty, "Item with tag \(tag) has empty title after refreshTimes")
            let hasDigit = titleString.contains(where: { $0.isNumber })
            #expect(hasDigit, "Item with tag \(tag) title '\(titleString)' contains no digit after refreshTimes")
        }
    }

    // MARK: - populate called twice reconciles in place (no item count explosion)

    @Test func populateCalledTwiceReconcilesMutatesExistingItems() {
        let now = Date()
        let target = MockActions()
        let menu = NSMenu()

        let usage1 = UsageResponse(entries: [
            WindowEntry.make(key: "five_hour", utilization: 42, resetsAt: now.addingTimeInterval(3600))!,
        ])
        let state1 = makeState(usage: usage1)
        MenuBuilder.populate(menu: menu, state: state1, target: target)
        let itemCountAfterFirst = menu.numberOfItems
        #expect(itemCountAfterFirst > 0)

        let usage2 = UsageResponse(entries: [
            WindowEntry.make(key: "five_hour", utilization: 77, resetsAt: now.addingTimeInterval(2400))!,
        ])
        let state2 = makeState(usage: usage2)
        MenuBuilder.populate(menu: menu, state: state2, target: target)
        let itemCountAfterSecond = menu.numberOfItems

        #expect(itemCountAfterSecond == itemCountAfterFirst,
                "Item count changed from \(itemCountAfterFirst) to \(itemCountAfterSecond) on second populate")

        var foundUsageRow = false
        for i in 0..<menu.numberOfItems {
            guard let item = menu.item(at: i) else { continue }
            let tag = item.tag
            guard tag >= MenuBuilder.usageBaseTag && tag < MenuBuilder.usagePlaceholderTag else { continue }

            let rowText: String
            if let rowView = item.view as? UsageRowView {
                rowText = rowView.textContent
            } else {
                rowText = item.attributedTitle?.string ?? item.title
            }
            foundUsageRow = true
            #expect(rowText.contains("77%"),
                    "Usage row should contain '77%' after second populate, got: '\(rowText)'")
            #expect(!rowText.contains("42%"),
                    "Usage row should NOT contain stale '42%' after second populate")
        }
        #expect(foundUsageRow, "No usage row item found in the menu after second populate")
    }
}
