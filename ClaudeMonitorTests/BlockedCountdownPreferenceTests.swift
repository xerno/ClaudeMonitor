import AppKit
import Testing
@testable import ClaudeMonitor

@MainActor
struct BlockedCountdownPreferenceTests {

    private func blockedUsage() -> UsageResponse {
        UsageResponse(entries: [WindowEntry.make(
            key: "seven_day", utilization: 100, resetsAt: Date().addingTimeInterval(3600)
        )].compactMap { $0 })
    }

    private func title(showCountdown: Bool) -> String {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        defer { NSStatusBar.system.removeStatusItem(item) }
        guard let button = item.button else { return "" }
        StatusBarRenderer.updateText(
            button: button, usage: blockedUsage(), hasCredentials: true, isStale: false,
            showBlockedCountdown: showCountdown
        )
        return button.attributedTitle.string
    }

    @Test func onByDefaultTheCountdownIsStillThere() {
        #expect(!title(showCountdown: true).isEmpty)
    }

    /// The whole title goes, stop sign included.
    @Test func turnedOffTheTitleGoesEmpty() {
        #expect(title(showCountdown: false).isEmpty)
    }

    @Test func absentPreferenceDefaultsToShowing() {
        let defaults = UserDefaults(suiteName: TestPreferencesRoot.makeSuiteName("BlockedCountdownPreferenceTests"))!
        #expect(Constants.Preferences.isBlockedCountdownShown(in: defaults))
    }

    @Test func thePreferenceRoundTrips() {
        let defaults = UserDefaults(suiteName: TestPreferencesRoot.makeSuiteName("BlockedCountdownPreferenceTests"))!
        defaults.set(false, forKey: Constants.Preferences.showBlockedCountdown)
        #expect(!Constants.Preferences.isBlockedCountdownShown(in: defaults))
        defaults.set(true, forKey: Constants.Preferences.showBlockedCountdown)
        #expect(Constants.Preferences.isBlockedCountdownShown(in: defaults))
    }

    @Test func theStateDefaultsToShowing() {
        #expect(MonitorState().showBlockedCountdown)
        #expect(!MonitorState(showBlockedCountdown: false).showBlockedCountdown)
    }
}
