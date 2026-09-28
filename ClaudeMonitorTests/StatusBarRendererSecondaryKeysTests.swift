import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct SecondaryWindowKeysTests {

    private func entry(key: String, utilization: Int, resetsIn: TimeInterval) -> WindowEntry {
        .make(key: key, utilization: utilization, resetsAt: Date().addingTimeInterval(resetsIn))!
    }

    // MARK: - Basic filtering

    @Test func noEntriesReturnsEmpty() {
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [WindowEntry]())
        #expect(keys.isEmpty)
    }

    @Test func nonOutpacingWindowIsExcluded() {
        let entries = [entry(key: "seven_day", utilization: 20, resetsIn: 604_800 * 0.5)]
        let keys = StatusBarRenderer.secondaryWindowKeys(from: entries)
        #expect(keys.isEmpty)
    }

    @Test func outpacingWindowIsIncluded() {
        let sevenDay = entry(key: "seven_day", utilization: 50, resetsIn: 604_800 * 0.5)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [sevenDay])
        #expect(keys.contains("604800"))
    }

    // MARK: - Model-specific pull-in logic

    @Test func modelSpecificPullsInAllModelsWindow() {
        let allModels = entry(key: "seven_day", utilization: 20, resetsIn: 604_800 * 0.5) // does not qualify alone
        let sonnet = entry(key: "seven_day_sonnet", utilization: 50, resetsIn: 604_800 * 0.5)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet])
        #expect(keys.contains("604800_sonnet"))
        #expect(keys.contains("604800"))
    }

    @Test func modelSpecificDoesNotPullInDifferentDuration() {
        let sevenDay = entry(key: "seven_day", utilization: 20, resetsIn: 604_800 * 0.5) // does not qualify alone
        let fiveHourSonnet = entry(key: "five_hour_sonnet", utilization: 50, resetsIn: 18000 * 0.5)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [sevenDay, fiveHourSonnet])
        #expect(keys.contains("18000_sonnet"))
        #expect(!keys.contains("604800"))
    }

    @Test func allModelsOutpacingAloneDoesNotPullInModelSpecific() {
        let allModels = entry(key: "seven_day", utilization: 50, resetsIn: 604_800 * 0.5)
        let sonnet = entry(key: "seven_day_sonnet", utilization: 20, resetsIn: 604_800 * 0.5) // does not qualify alone
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet])
        #expect(keys.contains("604800"))
        #expect(!keys.contains("604800_sonnet"))
    }

    @Test func multipleModelSpecificPullInSameAllModels() {
        let allModels = entry(key: "seven_day", utilization: 20, resetsIn: 604_800 * 0.5) // does not qualify alone
        let sonnet = entry(key: "seven_day_sonnet", utilization: 50, resetsIn: 604_800 * 0.5)
        let opus = entry(key: "seven_day_opus", utilization: 50, resetsIn: 604_800 * 0.5)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [allModels, sonnet, opus])
        #expect(keys.contains("604800"))
        #expect(keys.contains("604800_sonnet"))
        #expect(keys.contains("604800_opus"))
    }

    @Test func noAllModelsWindowAvailableForPullIn() {
        let sonnet = entry(key: "seven_day_sonnet", utilization: 50, resetsIn: 604_800 * 0.5)
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [sonnet])
        #expect(keys.contains("604800_sonnet"))
        #expect(keys.count == 1)
    }

    // MARK: - Past reset date

    @Test func pastResetDateExcludesWindow() {
        let past = WindowEntry.make(key: "seven_day", utilization: 90, resetsAt: Date().addingTimeInterval(-100))!
        let keys = StatusBarRenderer.secondaryWindowKeys(from: [past])
        #expect(keys.isEmpty)
    }
}
