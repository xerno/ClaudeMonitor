import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct SecondaryWindowKeysTests {

    private func entry(key: String, utilization: Int, resetsIn: TimeInterval) -> WindowEntry {
        .make(key: key, utilization: utilization, resetsAt: Date().addingTimeInterval(resetsIn))
    }

    // MARK: - Basic filtering

    @Test func noEntriesReturnsEmpty() {
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [WindowEntry]())
        #expect(keys.isEmpty)
    }

    @Test func nonOutpacingWindowIsExcluded() {
        // 20% used, ~50% time remaining → projected = 20 + (20/duration*0.5)*duration*0.5 = 40 → < 80, no show
        let entries = [entry(key: "seven_day", utilization: 20, resetsIn: 604_800 * 0.5)]
        let keys = StatusBarRenderer.secondaryWindowKeys(from: entries)
        #expect(keys.isEmpty)
    }

    @Test func outpacingWindowIsIncluded() {
        // 50% used, 50% time remaining → projected = 50+(50/duration*0.5)*duration*0.5 = 100 → ≥ 80, show
        let sevenDay = entry(key: "seven_day", utilization: 50, resetsIn: 604_800 * 0.5)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [sevenDay])
        #expect(keys.contains("seven_day"))
    }

    // MARK: - Model-specific pull-in logic

    @Test func modelSpecificPullsInAllModelsWindow() {
        // seven_day_sonnet qualifies → should also include seven_day (all-models, same duration)
        let allModels = entry(key: "seven_day", utilization: 20, resetsIn: 604_800 * 0.5) // projected=40, no show alone
        let sonnet = entry(key: "seven_day_sonnet", utilization: 50, resetsIn: 604_800 * 0.5) // projected=100, shows
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet])
        #expect(keys.contains("seven_day_sonnet"))
        #expect(keys.contains("seven_day")) // pulled in because sonnet qualifies
    }

    @Test func modelSpecificDoesNotPullInDifferentDuration() {
        // five_hour_sonnet qualifies but should NOT pull in seven_day (different duration)
        let sevenDay = entry(key: "seven_day", utilization: 20, resetsIn: 604_800 * 0.5) // projected=40, no show
        let fiveHourSonnet = entry(key: "five_hour_sonnet", utilization: 50, resetsIn: 18000 * 0.5) // projected=100, shows
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [sevenDay, fiveHourSonnet])
        #expect(keys.contains("five_hour_sonnet"))
        #expect(!keys.contains("seven_day")) // different duration, not pulled in
    }

    @Test func allModelsOutpacingAloneDoesNotPullInModelSpecific() {
        // seven_day qualifies, seven_day_sonnet does not → sonnet should not be added
        let allModels = entry(key: "seven_day", utilization: 50, resetsIn: 604_800 * 0.5) // projected=100, shows
        let sonnet = entry(key: "seven_day_sonnet", utilization: 20, resetsIn: 604_800 * 0.5) // projected=40, no show
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet])
        #expect(keys.contains("seven_day"))
        #expect(!keys.contains("seven_day_sonnet"))
    }

    @Test func multipleModelSpecificPullInSameAllModels() {
        let allModels = entry(key: "seven_day", utilization: 20, resetsIn: 604_800 * 0.5) // projected=40, no show alone
        let sonnet = entry(key: "seven_day_sonnet", utilization: 50, resetsIn: 604_800 * 0.5) // projected=100, shows
        let opus = entry(key: "seven_day_opus", utilization: 50, resetsIn: 604_800 * 0.5) // projected=100, shows
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet, opus])
        #expect(keys.contains("seven_day"))
        #expect(keys.contains("seven_day_sonnet"))
        #expect(keys.contains("seven_day_opus"))
    }

    @Test func noAllModelsWindowAvailableForPullIn() {
        // Model-specific qualifies but no matching all-models window in the collection
        let sonnet = entry(key: "seven_day_sonnet", utilization: 50, resetsIn: 604_800 * 0.5) // projected=100, shows
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [sonnet])
        #expect(keys.contains("seven_day_sonnet"))
        #expect(keys.count == 1) // no all-models to pull in
    }

    // MARK: - Past reset date

    @Test func pastResetDateExcludesWindow() {
        let past = WindowEntry.make(key: "seven_day", utilization: 90, resetsAt: Date().addingTimeInterval(-100))
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [past])
        #expect(keys.isEmpty) // shouldShowInMenuBar returns false for past reset
    }
}
