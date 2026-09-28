import Testing
import Foundation
@testable import ClaudeMonitor

struct DemoDataTests {

    @Test func scenario1DemonstratesOutageWithIncidents() {
        let frame = DemoData.scenario(1)
        // Two incidents, so the incident list renders multiple entries.
        let worst = frame.status.components.map(\.status).max()
        #expect(worst != nil && worst! > .operational)
        #expect(frame.status.incidents.count == 2)
        #expect(frame.usage.entries.map(\.key).contains("five_hour"))
        #expect(frame.usage.entries.map(\.key).contains("seven_day"))
    }

    @Test func scenario2DemonstratesDegradedPerformanceWithOneIncident() {
        let frame = DemoData.scenario(2)
        #expect(frame.status.components.contains { $0.status == .degradedPerformance })
        #expect(frame.status.incidents.count == 1)
        #expect(frame.usage.entries.map(\.key).contains("five_hour"))
        #expect(frame.usage.entries.map(\.key).contains("seven_day"))
    }

    @Test func scenario3DemonstratesHighUtilizationWithNoIncidents() {
        let frame = DemoData.scenario(3)
        #expect(frame.status.components.allSatisfy { $0.status == .operational })
        #expect(frame.status.incidents.isEmpty)
        #expect(frame.usage.entries.contains { $0.window.utilization >= 80 })
        #expect(frame.usage.entries.contains { $0.modelScope != nil })
    }

    @Test func scenario4DemonstratesBlockedWindowWithNoIncidents() {
        let frame = DemoData.scenario(4)
        #expect(frame.status.components.allSatisfy { $0.status == .operational })
        #expect(frame.status.incidents.isEmpty)
        #expect(frame.usage.entries.contains { $0.window.utilization >= 100 })
        #expect(frame.usage.entries.contains { $0.modelScope != nil })
    }

    @Test func scenario4HasBlockedWindow() {
        let frame = DemoData.scenario(4)
        let blocked = frame.usage.entries.first { $0.window.utilization >= 100 }
        #expect(blocked != nil)
    }

    @Test func defaultFallsBackToScenario1() {
        let frame1 = DemoData.scenario(1)
        let frameDef = DemoData.scenario(99)
        #expect(frame1.usage.entries.count == frameDef.usage.entries.count)
        #expect(frame1.status.components.count == frameDef.status.components.count)
        // resetsAt is excluded: generated from Date() at call time.
        #expect(frame1.usage.entries.first?.window.utilization == frameDef.usage.entries.first?.window.utilization)
        #expect(frame1.usage.entries.map(\.key) == frameDef.usage.entries.map(\.key))
    }

    @Test func rotationOrderCoversAllScenarios() {
        let order = Constants.Demo.rotationOrder
        #expect(Set(order) == Set(1...7))
    }

    @Test func allScenariosHaveValidWindowKeys() {
        for i in 1...7 {
            let frame = DemoData.scenario(i)
            for entry in frame.usage.entries {
                #expect(WindowKeyParser.parse(entry.key) != nil,
                        "Scenario \(i): key '\(entry.key)' is not parseable")
            }
        }
    }

    @Test func allScenariosHaveFutureResetDates() {
        let now = Date()
        for i in 1...7 {
            let frame = DemoData.scenario(i)
            let entriesWithResetDate = frame.usage.entries.filter { $0.window.resetsAt != nil }
            #expect(!entriesWithResetDate.isEmpty,
                    "Scenario \(i): no entries have a resetsAt date — cannot verify future reset dates")
            for entry in entriesWithResetDate {
                #expect(entry.window.resetsAt! > now,
                        "Scenario \(i): key '\(entry.key)' has past reset date")
            }
        }
    }

    @Test func allScenariosHaveConsistentComponentCount() {
        for i in 1...7 {
            let frame = DemoData.scenario(i)
            #expect(frame.status.components.count == 4, "Scenario \(i) should have 4 components")
        }
    }

    @Test func entriesAreSorted() {
        for i in 1...7 {
            let frame = DemoData.scenario(i)
            let entries = frame.usage.entries
            for j in 1..<entries.count {
                #expect(entries[j - 1] < entries[j] || entries[j - 1] == entries[j],
                        "Scenario \(i): entries not sorted at index \(j)")
            }
        }
    }

    // MARK: - DemoSamples Consistency

    @Test func demoSamplesKeysMatchUsageEntriesForScenariosWithFullCoverage() {
        let scenariosWithFullCoverage = [1, 2, 4, 5, 6, 7]
        for i in scenariosWithFullCoverage {
            let frame = DemoData.scenario(i)
            for entry in frame.usage.entries {
                let entrySamples = frame.samples[entry.key]
                #expect(entrySamples != nil,
                        "Scenario \(i): no samples for entry key '\(entry.key)'")
                #expect(entrySamples?.isEmpty == false,
                        "Scenario \(i): empty samples for entry key '\(entry.key)'")
            }
        }
    }

    @Test @MainActor func demoSamplesProduceOrderedTrackedAnalyses() {
        for i in 1...7 {
            let frame = DemoData.scenario(i)
            // Capture `now` after the frame: demo samples are timed from the wall clock at construction,
            // so an earlier `now` predates the last sample and makes timeSinceLastChange negative.
            let now = Date()
            for entry in frame.usage.entries {
                guard let entrySamples = frame.samples[entry.key], !entrySamples.isEmpty else { continue }
                let analysis = UsageHistory.analyze(entry: entry, samples: entrySamples, now: now)

                #expect(analysis.segments.contains { $0.kind == .tracked },
                        "Scenario \(i), key \(entry.key): analysis has no tracked segment")

                let timestamps = analysis.segments.flatMap { $0.samples.map(\.timestamp) }
                #expect(zip(timestamps, timestamps.dropFirst()).allSatisfy { $0 <= $1 },
                        "Scenario \(i), key \(entry.key): segment samples are not chronologically ordered")

                if let timeSinceLastChange = analysis.timeSinceLastChange {
                    #expect(timeSinceLastChange >= 0,
                            "Scenario \(i), key \(entry.key): timeSinceLastChange is negative")
                } else {
                    Issue.record("Scenario \(i), key \(entry.key): timeSinceLastChange is nil")
                }
            }
        }
    }

    // MARK: - Connectivity State

    @Test func scenario5HasRecentFailureFlag() {
        let frame = DemoData.scenario(5)
        #expect(frame.isOnline == true)
        #expect(frame.hasRecentFailure == true)
        #expect(frame.isAnyServiceStale == false)
        #expect(frame.lastFailedAt != nil)
    }

    @Test func scenario6IsOfflineAndStale() {
        let frame = DemoData.scenario(6)
        #expect(frame.isOnline == false)
        #expect(frame.isAnyServiceStale == true)
        #expect(frame.hasRecentFailure == false)
        #expect(frame.lastFailedAt != nil)
    }

    @Test func scenario7IsStaleWithConnectionError() {
        let frame = DemoData.scenario(7)
        #expect(frame.isOnline == true)
        #expect(frame.isAnyServiceStale == true)
        #expect(frame.hasRecentFailure == false)
        #expect(frame.lastFailedAt != nil)
    }
}
