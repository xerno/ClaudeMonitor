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
        // 30% used, ~70% time remaining → not outpacing
        let entries = [entry(key: "seven_day", utilization: 30, resetsIn: 604_800 * 0.7)]
        let keys = StatusBarRenderer.secondaryWindowKeys(from: entries)
        #expect(keys.isEmpty)
    }

    @Test func outpacingWindowIsIncluded() {
        // 65% used, 40% time remaining (60% elapsed) → outpacing (65 > 60)
        let sevenDay = entry(key: "seven_day", utilization: 65, resetsIn: 604_800 * 0.4)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [sevenDay])
        #expect(keys.contains("seven_day"))
    }

    // MARK: - Model-specific pull-in logic

    @Test func modelSpecificPullsInAllModelsWindow() {
        // seven_day_sonnet outpacing → should also include seven_day (all-models)
        let allModels = entry(key: "seven_day", utilization: 30, resetsIn: 604_800 * 0.7) // not outpacing on its own
        let sonnet = entry(key: "seven_day_sonnet", utilization: 65, resetsIn: 604_800 * 0.4) // outpacing
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet])
        #expect(keys.contains("seven_day_sonnet"))
        #expect(keys.contains("seven_day")) // pulled in because sonnet qualifies
    }

    @Test func modelSpecificDoesNotPullInDifferentDuration() {
        // five_hour_sonnet outpacing should NOT pull in seven_day (different duration)
        let sevenDay = entry(key: "seven_day", utilization: 30, resetsIn: 604_800 * 0.7)
        let fiveHourSonnet = entry(key: "five_hour_sonnet", utilization: 65, resetsIn: 18000 * 0.4)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [sevenDay, fiveHourSonnet])
        #expect(keys.contains("five_hour_sonnet"))
        #expect(!keys.contains("seven_day")) // different duration, not pulled in
    }

    @Test func allModelsOutpacingAloneDoesNotPullInModelSpecific() {
        // seven_day outpacing does NOT pull in seven_day_sonnet
        let allModels = entry(key: "seven_day", utilization: 65, resetsIn: 604_800 * 0.4)
        let sonnet = entry(key: "seven_day_sonnet", utilization: 30, resetsIn: 604_800 * 0.7)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet])
        #expect(keys.contains("seven_day"))
        #expect(!keys.contains("seven_day_sonnet"))
    }

    @Test func multipleModelSpecificPullInSameAllModels() {
        let allModels = entry(key: "seven_day", utilization: 30, resetsIn: 604_800 * 0.7)
        let sonnet = entry(key: "seven_day_sonnet", utilization: 65, resetsIn: 604_800 * 0.4)
        let opus = entry(key: "seven_day_opus", utilization: 70, resetsIn: 604_800 * 0.4)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet, opus])
        #expect(keys.contains("seven_day"))
        #expect(keys.contains("seven_day_sonnet"))
        #expect(keys.contains("seven_day_opus"))
    }

    @Test func noAllModelsWindowAvailableForPullIn() {
        // Model-specific outpacing but no matching all-models window in the collection
        let sonnet = entry(key: "seven_day_sonnet", utilization: 65, resetsIn: 604_800 * 0.4)
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
