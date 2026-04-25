import Testing
import Foundation
@testable import ClaudeMonitor

struct DemoDataTests {

    @Test func scenario1ReturnsValidData() {
        let frame = DemoData.scenario(1)
        #expect(!frame.usage.entries.isEmpty)
        #expect(!frame.status.components.isEmpty)
        #expect(!frame.status.incidents.isEmpty) // scenario 1 has incidents
    }

    @Test func scenario2ReturnsValidData() {
        let frame = DemoData.scenario(2)
        #expect(!frame.usage.entries.isEmpty)
        #expect(!frame.status.components.isEmpty)
        #expect(!frame.status.incidents.isEmpty) // scenario 2 has an incident
    }

    @Test func scenario3ReturnsValidData() {
        let frame = DemoData.scenario(3)
        #expect(!frame.usage.entries.isEmpty)
        #expect(!frame.status.components.isEmpty)
        #expect(frame.status.incidents.isEmpty) // scenario 3 has no incidents
    }

    @Test func scenario4ReturnsValidData() {
        let frame = DemoData.scenario(4)
        #expect(!frame.usage.entries.isEmpty)
        #expect(!frame.status.components.isEmpty)
        #expect(frame.status.incidents.isEmpty) // scenario 4 has no incidents
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
            for entry in frame.usage.entries {
                if let resetsAt = entry.window.resetsAt {
                    #expect(resetsAt > now,
                            "Scenario \(i): key '\(entry.key)' has past reset date")
                }
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
        // Scenarios 1, 2, 4, 5, 6, 7 provide samples for every entry key.
        // Scenario 3 intentionally omits samples for seven_day_sonnet (utilization 0,
        // no resetsAt — nothing meaningful to graph).
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

    @Test @MainActor func demoSamplesProduceNonTrivialAnalyses() {
        let now = Date()
        for i in 1...7 {
            let frame = DemoData.scenario(i)
            for entry in frame.usage.entries {
                guard let entrySamples = frame.samples[entry.key], !entrySamples.isEmpty else { continue }
                let analysis = UsageHistory.analyze(entry: entry, samples: entrySamples, now: now)
                #expect(!analysis.segments.isEmpty,
                        "Scenario \(i), key \(entry.key): analysis has no segments")
                #expect(analysis.timeSinceLastChange != nil,
                        "Scenario \(i), key \(entry.key): timeSinceLastChange is nil")
            }
        }
    }

    // MARK: - Connectivity State

    @Test func scenario5HasRecentFailureFlag() {
        let frame = DemoData.scenario(5)
        #expect(frame.isOnline == true)
        #expect(frame.hasRecentFailure == true)
        #expect(frame.isStale == false)
        #expect(frame.lastFailedAt != nil)
    }

    @Test func scenario6IsOfflineAndStale() {
        let frame = DemoData.scenario(6)
        #expect(frame.isOnline == false)
        #expect(frame.isStale == true)
        #expect(frame.hasRecentFailure == false)
        #expect(frame.lastFailedAt != nil)
    }

    @Test func scenario7IsStaleWithConnectionError() {
        let frame = DemoData.scenario(7)
        #expect(frame.isOnline == true)
        #expect(frame.isStale == true)
        #expect(frame.hasRecentFailure == false)
        #expect(frame.lastFailedAt != nil)
    }
}
