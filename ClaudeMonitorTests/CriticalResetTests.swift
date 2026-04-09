import Testing
import Foundation
@testable import ClaudeMonitor

struct CriticalResetTests {

    // MARK: - detectCriticalReset

    @Test func detectsResetWhenPreviousWasCritical() {
        let now = Date()
        let duration: TimeInterval = 18000

        let previous = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 85, resetsAt: now.addingTimeInterval(1000)))
        ])
        let current = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 5, resetsAt: now.addingTimeInterval(duration)))
        ])

        #expect(Formatting.detectCriticalReset(previous: previous, current: current))
    }

    @Test func noResetWhenTimestampsDontJump() {
        let now = Date()
        let duration: TimeInterval = 18000

        let previous = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 90, resetsAt: now.addingTimeInterval(1000)))
        ])
        let current = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 88, resetsAt: now.addingTimeInterval(940)))
        ])

        #expect(!Formatting.detectCriticalReset(previous: previous, current: current))
    }

    @Test func resetNotDetectedWhenPreviousWasNotCritical() {
        let now = Date()
        let duration: TimeInterval = 18000

        let previous = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 30, resetsAt: now.addingTimeInterval(10000)))
        ])
        let current = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 5, resetsAt: now.addingTimeInterval(duration)))
        ])

        #expect(!Formatting.detectCriticalReset(previous: previous, current: current))
    }

    @Test func unmatchedKeysAreIgnored() {
        let now = Date()

        let previous = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 90, resetsAt: now.addingTimeInterval(1000))
        ])
        let current = UsageResponse(entries: [
            .make(key: "seven_day", utilization: 5, resetsAt: now.addingTimeInterval(604_800))
        ])

        #expect(!Formatting.detectCriticalReset(previous: previous, current: current))
    }

    @Test func missingResetDatesAreSkipped() {
        let previous = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 90, resetsAt: nil))
        ])
        let current = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 5, resetsAt: Date().addingTimeInterval(18000)))
        ])

        #expect(!Formatting.detectCriticalReset(previous: previous, current: current))
    }

    @Test func resetDetectedOnAnyMatchingCriticalWindow() {
        let now = Date()
        let fiveHour: TimeInterval = 18000
        let sevenDay: TimeInterval = 604_800

        let previous = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: fiveHour, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 30, resetsAt: now.addingTimeInterval(1000))),
            WindowEntry(key: "seven_day", duration: sevenDay, durationLabel: "7d", modelScope: nil,
                        window: UsageWindow(utilization: 85, resetsAt: now.addingTimeInterval(10000))),
        ])
        let current = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: fiveHour, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 28, resetsAt: now.addingTimeInterval(940))),
            WindowEntry(key: "seven_day", duration: sevenDay, durationLabel: "7d", modelScope: nil,
                        window: UsageWindow(utilization: 5, resetsAt: now.addingTimeInterval(sevenDay))),
        ])

        #expect(Formatting.detectCriticalReset(previous: previous, current: current))
    }

    @Test func criticalByTimeRuleAlsoTriggersReset() {
        let now = Date()
        let duration: TimeInterval = 18000
        // 78% used, 60% remaining (40% elapsed) → 78 > 40+35 → critical by time rule
        let previousResets = now.addingTimeInterval(duration * 0.6)

        let previous = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 78, resetsAt: previousResets))
        ])
        let current = UsageResponse(entries: [
            // After reset: new window gets full duration FROM the reset point
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 5, resetsAt: previousResets.addingTimeInterval(duration)))
        ])

        #expect(Formatting.detectCriticalReset(previous: previous, current: current))
    }

    @Test func emptyResponses() {
        let empty = UsageResponse(entries: [])
        let nonEmpty = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 85, resetsAt: Date().addingTimeInterval(18000))
        ])
        #expect(!Formatting.detectCriticalReset(previous: empty, current: nonEmpty))
        #expect(!Formatting.detectCriticalReset(previous: nonEmpty, current: empty))
        #expect(!Formatting.detectCriticalReset(previous: empty, current: empty))
    }

    // MARK: - hasAnyCriticalWindow

    @Test func hasAnyCriticalWindowAllNormal() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 30, resetsAt: now.addingTimeInterval(10000)),
            .make(key: "seven_day", utilization: 18, resetsAt: now.addingTimeInterval(400_000)),
        ])
        #expect(!Formatting.hasAnyCriticalWindow(usage))
    }

    @Test func hasAnyCriticalWindowOneCritical() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 85, resetsAt: now.addingTimeInterval(10000)),
            .make(key: "seven_day", utilization: 18, resetsAt: now.addingTimeInterval(400_000)),
        ])
        #expect(Formatting.hasAnyCriticalWindow(usage))
    }

    @Test func hasAnyCriticalWindowWarningOnly() {
        let now = Date()
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 72, resetsAt: now.addingTimeInterval(10000)),
            .make(key: "seven_day", utilization: 18, resetsAt: now.addingTimeInterval(400_000)),
        ])
        #expect(!Formatting.hasAnyCriticalWindow(usage))
    }

    @Test func hasAnyCriticalByTimeRule() {
        let now = Date()
        let duration: TimeInterval = 18000
        // 78% used, 60% remaining → critical by time rule
        let usage = UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: duration, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 78, resetsAt: now.addingTimeInterval(duration * 0.6)))
        ])
        #expect(Formatting.hasAnyCriticalWindow(usage))
    }

    @Test func hasAnyCriticalWindowEmptyUsage() {
        let usage = UsageResponse(entries: [])
        #expect(!Formatting.hasAnyCriticalWindow(usage))
    }
}
