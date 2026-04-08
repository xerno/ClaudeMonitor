import Testing
import Foundation
import AppKit
@testable import ClaudeMonitor

@MainActor struct ModelsTests {

    // MARK: - ComponentStatus Comparable

    @Test func severityOrder() {
        #expect(ComponentStatus.unknown < .operational)
        #expect(ComponentStatus.operational < .underMaintenance)
        #expect(ComponentStatus.underMaintenance < .degradedPerformance)
        #expect(ComponentStatus.degradedPerformance < .partialOutage)
        #expect(ComponentStatus.partialOutage < .majorOutage)
    }

    @Test func comparableConsistentWithEquatable() {
        let all: [ComponentStatus] = [.unknown, .operational, .underMaintenance, .degradedPerformance, .partialOutage, .majorOutage]
        for (i, a) in all.enumerated() {
            for (j, b) in all.enumerated() {
                if i == j {
                    #expect(a == b)
                    #expect(!(a < b))
                    #expect(!(b < a))
                } else if i < j {
                    #expect(a < b)
                    #expect(a != b)
                }
            }
        }
    }

    @Test func maxReturnsHighestSeverity() {
        let statuses: [ComponentStatus] = [.operational, .partialOutage, .degradedPerformance]
        #expect(statuses.max() == .partialOutage)
    }

    // MARK: - ComponentStatus Labels & Dots

    @Test func labels() {
        #expect(ComponentStatus.operational.label == "Operational")
        #expect(ComponentStatus.degradedPerformance.label == "Degraded")
        #expect(ComponentStatus.partialOutage.label == "Partial Outage")
        #expect(ComponentStatus.majorOutage.label == "Major Outage")
        #expect(ComponentStatus.underMaintenance.label == "Maintenance")
        #expect(ComponentStatus.unknown.label == "Unknown")
    }

    @Test func dots() {
        #expect(ComponentStatus.operational.dot == "🟢")
        #expect(ComponentStatus.majorOutage.dot == "🔴")
        #expect(ComponentStatus.unknown.dot == "⚪")
    }

    // MARK: - Decoding

    @Test func decodingKnownStatus() throws {
        let json = #"{"id":"1","name":"API","status":"degraded_performance"}"#.data(using: .utf8)!
        let component = try JSONDecoder().decode(StatusComponent.self, from: json)
        #expect(component.status == .degradedPerformance)
        #expect(component.name == "API")
    }

    @Test func decodingUnknownStatusFallsBack() throws {
        let json = #"{"id":"1","name":"API","status":"something_new"}"#.data(using: .utf8)!
        let component = try JSONDecoder().decode(StatusComponent.self, from: json)
        #expect(component.status == .unknown)
    }

    // MARK: - UsageResponse

    @Test func usageResponseDecoding() throws {
        let json = """
        {
            "five_hour": {"utilization": 42, "resets_at": "2026-04-01T15:00:00.000Z"},
            "seven_day": {"utilization": 18, "resets_at": "2026-04-07T00:00:00.000Z"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: json)
        #expect(response.entries.count == 2)
        #expect(response.entries[0].key == "five_hour")
        #expect(response.entries[0].window.utilization == 42)
        #expect(response.entries[0].duration == 5 * 3600)
        #expect(response.entries[0].durationLabel == "5h")
        #expect(response.entries[0].modelScope == nil)
        #expect(response.entries[1].key == "seven_day")
        #expect(response.entries[1].window.utilization == 18)
    }

    @Test func usageResponseDecodingWithoutFractionalSeconds() throws {
        let json = """
        {
            "five_hour": {"utilization": 50, "resets_at": "2026-04-01T15:00:00Z"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: json)
        #expect(response.entries.count == 1)
        #expect(response.entries[0].window.utilization == 50)
    }

    @Test func usageResponseEmptyJSON() throws {
        let json = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.entries.isEmpty)
        #expect(response.allWindows.isEmpty)
    }

    @Test func usageResponseDecodingWithModelScope() throws {
        let json = """
        {
            "seven_day": {"utilization": 18, "resets_at": "2026-04-07T00:00:00.000Z"},
            "seven_day_sonnet": {"utilization": 22, "resets_at": "2026-04-07T00:00:00.000Z"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: json)
        #expect(response.entries.count == 2)
        #expect(response.entries[0].modelScope == nil)
        #expect(response.entries[1].modelScope == "Sonnet")
        #expect(response.entries[1].durationLabel == "7d")
    }

    @Test func usageResponseSkipsUnparseableKeys() throws {
        let json = """
        {
            "five_hour": {"utilization": 42, "resets_at": "2026-04-01T15:00:00.000Z"},
            "unknown_format": {"utilization": 10, "resets_at": "2026-04-01T15:00:00.000Z"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: json)
        #expect(response.entries.count == 1)
        #expect(response.entries[0].key == "five_hour")
    }

    @Test func usageResponseSkipsNonWindowValues() throws {
        let json = """
        {
            "five_hour": {"utilization": 42, "resets_at": "2026-04-01T15:00:00.000Z"},
            "one_day": "not_a_window_object",
            "two_hour": {"unexpected": "structure"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: json)
        #expect(response.entries.count == 1)
        #expect(response.entries[0].key == "five_hour")
    }

    // MARK: - WindowKeyParser

    @Test func parserBasicHour() {
        let parsed = WindowKeyParser.parse("five_hour")
        #expect(parsed?.duration == 5.0 * 3600)
        #expect(parsed?.durationLabel == "5h")
        #expect(parsed?.modelScope == nil)
    }

    @Test func parserBasicDay() {
        let parsed = WindowKeyParser.parse("seven_day")
        #expect(parsed?.duration == 7.0 * 86400)
        #expect(parsed?.durationLabel == "7d")
        #expect(parsed?.modelScope == nil)
    }

    @Test func parserWithModel() {
        let parsed = WindowKeyParser.parse("seven_day_sonnet")
        #expect(parsed?.duration == 7.0 * 86400)
        #expect(parsed?.durationLabel == "7d")
        #expect(parsed?.modelScope == "Sonnet")
    }

    @Test func parserCompoundNumber() {
        let parsed = WindowKeyParser.parse("twenty_four_hour")
        #expect(parsed?.duration == 24.0 * 3600)
        #expect(parsed?.durationLabel == "24h")
        #expect(parsed?.modelScope == nil)
    }

    @Test func parserTwoWordModel() {
        let parsed = WindowKeyParser.parse("seven_day_claude_code")
        #expect(parsed?.duration == 7.0 * 86400)
        #expect(parsed?.modelScope == "Claude Code")
    }

    @Test func parserUnknownFormat() {
        #expect(WindowKeyParser.parse("foo") == nil)
        #expect(WindowKeyParser.parse("") == nil)
        #expect(WindowKeyParser.parse("five") == nil)
        #expect(WindowKeyParser.parse("blah_hour") == nil)
    }

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

    // MARK: - StatusSummary

    @Test func statusSummaryDecoding() throws {
        let json = """
        {
            "components": [
                {"id": "1", "name": "API", "status": "operational"},
                {"id": "2", "name": "Console", "status": "major_outage"}
            ],
            "incidents": [
                {"id": "i1", "name": "API issues", "status": "investigating", "impact": "major", "shortlink": "https://stspg.io/x"}
            ],
            "status": {"indicator": "major", "description": "Major System Outage"}
        }
        """.data(using: .utf8)!

        let summary = try JSONDecoder().decode(StatusSummary.self, from: json)
        #expect(summary.components.count == 2)
        #expect(summary.incidents.count == 1)
        #expect(summary.incidents.first?.name == "API issues")
        #expect(summary.status.indicator == "major")
        #expect(summary.components.map(\.status).max() == .majorOutage)
    }

    // MARK: - Equatable

    @Test func usageWindowEquality() {
        let date = Date()
        let a = UsageWindow(utilization: 42, resetsAt: date)
        let b = UsageWindow(utilization: 42, resetsAt: date)
        let c = UsageWindow(utilization: 50, resetsAt: date)
        #expect(a == b)
        #expect(a != c)
    }
}
