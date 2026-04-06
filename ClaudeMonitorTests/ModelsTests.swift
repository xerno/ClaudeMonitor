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
        #expect(response.fiveHour?.utilization == 42)
        #expect(response.sevenDay?.utilization == 18)
        #expect(response.sevenDaySonnet == nil)
    }

    @Test func usageResponseDecodingWithoutFractionalSeconds() throws {
        let json = """
        {
            "five_hour": {"utilization": 50, "resets_at": "2026-04-01T15:00:00Z"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: json)
        #expect(response.fiveHour?.utilization == 50)
    }

    @Test func usageResponseAllNil() throws {
        let json = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        #expect(response.fiveHour == nil)
        #expect(response.sevenDay == nil)
        #expect(response.sevenDaySonnet == nil)
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
