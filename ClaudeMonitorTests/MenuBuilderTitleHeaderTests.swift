import AppKit
import Testing
@testable import ClaudeMonitor

/// The dropdown's title block: the mark, the app name, the account switcher and the status badge.
@MainActor
struct MenuBuilderTitleHeaderTests {

    private func contains<T: NSView>(_ type: T.Type, in view: NSView?) -> Bool {
        guard let view else { return false }
        if view is T { return true }
        return view.subviews.contains { contains(type, in: $0) }
    }

    private func labels(in view: NSView) -> [NSTextField] {
        view.subviews.flatMap { subview -> [NSTextField] in
            if let field = subview as? NSTextField { return [field] }
            return labels(in: subview)
        }
    }

    private func state(blocked: Bool, profiles: [Profile] = []) -> MonitorState {
        let entries = [WindowEntry.make(key: "seven_day", utilization: blocked ? 100 : 40,
                                        resetsAt: Date().addingTimeInterval(3600))].compactMap { $0 }
        return MonitorState(
            usage: UsageSnapshot(currentUsage: UsageResponse(entries: entries)),
            profiles: ProfileSnapshot(profiles: profiles, activeId: profiles.first?.id),
            hasCredentials: true
        )
    }

    @Test func theTitleIsLoudAndTheMarkIsThere() throws {
        let view = MenuBuilder.makeTitleHeaderView(title: MenuBuilder.appTitle)
        let title = try #require(labels(in: view).first)
        #expect(title.stringValue == MenuBuilder.appTitle)
        #expect(title.textColor == .labelColor)
        #expect(title.font == MenuBuilder.titleFont)
        #expect(contains(NSImageView.self, in: view), "the sunburst mark belongs in the title row")
    }

    @Test func noBadgeWhileNothingIsBlocked() {
        #expect(MenuBuilder.usageBadge(state: state(blocked: false)) == nil)
    }

    @Test func aBlockedWindowRaisesTheBadge() throws {
        let badge = try #require(MenuBuilder.usageBadge(state: state(blocked: true)))
        #expect(badge.dotColor == .systemRed)
        #expect(!badge.text.isEmpty)
    }

    /// No countdown in the badge: it is redrawn on a poll, which can be five minutes apart, and the
    /// row right below already carries "resets in …".
    @Test func theBadgeCarriesNoClock() throws {
        let badge = try #require(MenuBuilder.usageBadge(state: state(blocked: true)))
        #expect(!badge.text.contains(":"))
        #expect(badge.text.rangeOfCharacter(from: .decimalDigits) == nil)
    }

    @Test func theBadgeIsBuiltIntoTheHeaderWhenBlocked() throws {
        let blocked = MenuBuilder.makeTitleHeaderView(
            title: MenuBuilder.appTitle,
            badge: HeaderBadge(text: "Rate limit reached", dotColor: .systemRed)
        )
        #expect(labels(in: blocked).count == 2)
        #expect(labels(in: MenuBuilder.makeTitleHeaderView(title: MenuBuilder.appTitle)).count == 1)
    }

    // MARK: - The switcher survives the redesign

    @Test func twoAccountsPutTheSwitcherInTheTitleRow() throws {
        let profiles = [
            Profile(id: "a", name: "Personal", organizationId: "org-a"),
            Profile(id: "b", name: "Work", organizationId: "org-b"),
        ]
        let (items, _) = MenuBuilder.buildDesiredItems(
            state: state(blocked: false, profiles: profiles), target: TitleHeaderMockActions()
        )
        let header = try #require(items.first { $0.tag == MenuBuilder.usageSectionTag })
        #expect(contains(AccountToggleView.self, in: header.view),
                "the compact switcher must survive the redesign, in the title row")
    }

    @Test func oneAccountLeavesTheSwitcherOut() throws {
        let profiles = [Profile(id: "a", name: "Personal", organizationId: "org-a")]
        let (items, _) = MenuBuilder.buildDesiredItems(
            state: state(blocked: false, profiles: profiles), target: TitleHeaderMockActions()
        )
        let header = try #require(items.first { $0.tag == MenuBuilder.usageSectionTag })
        #expect(!contains(AccountToggleView.self, in: header.view))
    }
}

@MainActor
private final class TitleHeaderMockActions: NSObject, MenuActions {
    @objc func didSelectRefresh() {}
    @objc func openIncident(_ sender: NSMenuItem) {}
    @objc func didSelectPreferences() {}
    @objc func didSelectAbout() {}
    @objc func didSelectUsageWindow(_ sender: NSMenuItem) {}
    @objc func didSelectSentinel() {}
    @objc func didSelectProfile(_ sender: NSMenuItem) {}
}
