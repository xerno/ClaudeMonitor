import Testing
import Foundation
@testable import ClaudeMonitor

struct DemoDataTests {

    @Test func scenario1ReturnsValidData() {
        let (usage, status, _) = DemoData.scenario(1)
        #expect(!usage.entries.isEmpty)
        #expect(!status.components.isEmpty)
        #expect(!status.incidents.isEmpty) // scenario 1 has incidents
    }

    @Test func scenario2ReturnsValidData() {
        let (usage, status, _) = DemoData.scenario(2)
        #expect(!usage.entries.isEmpty)
        #expect(!status.components.isEmpty)
        #expect(!status.incidents.isEmpty) // scenario 2 has an incident
    }

    @Test func scenario3ReturnsValidData() {
        let (usage, status, _) = DemoData.scenario(3)
        #expect(!usage.entries.isEmpty)
        #expect(!status.components.isEmpty)
        #expect(status.incidents.isEmpty) // scenario 3 has no incidents
    }

    @Test func scenario4ReturnsValidData() {
        let (usage, status, _) = DemoData.scenario(4)
        #expect(!usage.entries.isEmpty)
        #expect(!status.components.isEmpty)
        #expect(status.incidents.isEmpty) // scenario 4 has no incidents
    }

    @Test func scenario4HasBlockedWindow() {
        let (usage, _, _) = DemoData.scenario(4)
        let blocked = usage.entries.first { $0.window.utilization >= 100 }
        #expect(blocked != nil)
    }

    @Test func defaultFallsBackToScenario1() {
        let (usage1, status1, _) = DemoData.scenario(1)
        let (usageDef, statusDef, _) = DemoData.scenario(99)
        #expect(usage1.entries.count == usageDef.entries.count)
        #expect(status1.components.count == statusDef.components.count)
    }

    @Test func rotationOrderCoversAllScenarios() {
        let order = Constants.Demo.rotationOrder
        #expect(Set(order) == Set(1...4))
    }

    @Test func allScenariosHaveValidWindowKeys() {
        for i in 1...4 {
            let (usage, _, _) = DemoData.scenario(i)
            for entry in usage.entries {
                #expect(WindowKeyParser.parse(entry.key) != nil,
                        "Scenario \(i): key '\(entry.key)' is not parseable")
            }
        }
    }

    @Test func allScenariosHaveFutureResetDates() {
        let now = Date()
        for i in 1...4 {
            let (usage, _, _) = DemoData.scenario(i)
            for entry in usage.entries {
                if let resetsAt = entry.window.resetsAt {
                    #expect(resetsAt > now,
                            "Scenario \(i): key '\(entry.key)' has past reset date")
                }
            }
        }
    }

    @Test func allScenariosHaveConsistentComponentCount() {
        for i in 1...4 {
            let (_, status, _) = DemoData.scenario(i)
            #expect(status.components.count == 4, "Scenario \(i) should have 4 components")
        }
    }

    @Test func entriesAreSorted() {
        for i in 1...4 {
            let (usage, _, _) = DemoData.scenario(i)
            let entries = usage.entries
            for j in 1..<entries.count {
                #expect(entries[j - 1] < entries[j] || entries[j - 1] == entries[j],
                        "Scenario \(i): entries not sorted at index \(j)")
            }
        }
    }

    // MARK: - DemoSamples Consistency

    @Test func demoSamplesKeysMatchUsageEntriesForScenariosWithFullCoverage() {
        // Scenarios 1, 2, and 4 provide samples for every entry key.
        // Scenario 3 intentionally omits samples for seven_day_sonnet (utilization 0,
        // no resetsAt — nothing meaningful to graph).
        let scenariosWithFullCoverage = [1, 2, 4]
        for i in scenariosWithFullCoverage {
            let (usage, _, samples) = DemoData.scenario(i)
            for entry in usage.entries {
                let entrySamples = samples[entry.key]
                #expect(entrySamples != nil,
                        "Scenario \(i): no samples for entry key '\(entry.key)'")
                #expect(entrySamples?.isEmpty == false,
                        "Scenario \(i): empty samples for entry key '\(entry.key)'")
            }
        }
    }

    @Test @MainActor func demoSamplesProduceNonTrivialAnalyses() {
        let now = Date()
        for i in 1...4 {
            let (usage, _, samples) = DemoData.scenario(i)
            for entry in usage.entries {
                guard let entrySamples = samples[entry.key], !entrySamples.isEmpty else { continue }
                let analysis = UsageHistory.analyze(entry: entry, samples: entrySamples, now: now)
                #expect(!analysis.segments.isEmpty,
                        "Scenario \(i), key '\(entry.key)': analysis has no segments")
                // Each entry with samples must have a defined timeSinceLastChange
                #expect(analysis.timeSinceLastChange != nil,
                        "Scenario \(i), key '\(entry.key)': timeSinceLastChange is nil")
            }
        }
    }
}
