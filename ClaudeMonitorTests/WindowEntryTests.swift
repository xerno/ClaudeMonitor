import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct WindowEntryTests {

    // MARK: - WindowEntry Sorting

    @Test func windowEntrySorting() {
        let entries = [
            WindowEntry.make(key: "seven_day_sonnet", utilization: 10, resetsAt: nil),
            WindowEntry.make(key: "five_hour", utilization: 10, resetsAt: nil),
            WindowEntry.make(key: "seven_day", utilization: 10, resetsAt: nil),
        ]
        let sorted = entries.sorted()
        #expect(sorted[0].key == "five_hour")
        #expect(sorted[1].key == "seven_day")
        #expect(sorted[2].key == "seven_day_sonnet")
    }

    // MARK: - Display Label

    @Test func displayLabelAllModelsOnly() {
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: nil),
            .make(key: "seven_day", utilization: 18, resetsAt: nil),
        ])
        #expect(Formatting.displayLabel(for: usage.entries[0], in: usage) == "5h")
        #expect(Formatting.displayLabel(for: usage.entries[1], in: usage) == "7d")
    }

    @Test func displayLabelSingleWindow() {
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: nil),
        ])
        #expect(Formatting.displayLabel(for: usage.entries[0], in: usage) == "5h")
    }

    @Test func displayLabelWithModelSpecificShowsAllOnEveryAllModelsWindow() {
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: nil),
            .make(key: "seven_day", utilization: 18, resetsAt: nil),
            .make(key: "seven_day_sonnet", utilization: 22, resetsAt: nil),
        ])
        #expect(Formatting.displayLabel(for: usage.entries[0], in: usage) == "5h all")
        #expect(Formatting.displayLabel(for: usage.entries[1], in: usage) == "7d all")
        #expect(Formatting.displayLabel(for: usage.entries[2], in: usage) == "7d Sonnet")
    }

    @Test func displayLabelOnlyModelSpecific() {
        let usage = UsageResponse(entries: [
            .make(key: "seven_day_sonnet", utilization: 22, resetsAt: nil),
        ])
        #expect(Formatting.displayLabel(for: usage.entries[0], in: usage) == "7d Sonnet")
    }

    @Test func displayLabelMultipleModelSpecificSameDuration() {
        let usage = UsageResponse(entries: [
            .make(key: "seven_day", utilization: 18, resetsAt: nil),
            .make(key: "seven_day_opus", utilization: 10, resetsAt: nil),
            .make(key: "seven_day_sonnet", utilization: 22, resetsAt: nil),
        ])
        #expect(Formatting.displayLabel(for: usage.entries[0], in: usage) == "7d all")
        #expect(Formatting.displayLabel(for: usage.entries[1], in: usage) == "7d Opus")
        #expect(Formatting.displayLabel(for: usage.entries[2], in: usage) == "7d Sonnet")
    }

    @Test func displayLabelModelSpecificAtDifferentDuration() {
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: nil),
            .make(key: "five_hour_sonnet", utilization: 30, resetsAt: nil),
            .make(key: "seven_day", utilization: 18, resetsAt: nil),
        ])
        #expect(Formatting.displayLabel(for: usage.entries[0], in: usage) == "5h all")
        #expect(Formatting.displayLabel(for: usage.entries[1], in: usage) == "5h Sonnet")
        #expect(Formatting.displayLabel(for: usage.entries[2], in: usage) == "7d all")
    }
}
