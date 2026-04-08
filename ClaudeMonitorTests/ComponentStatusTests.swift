import Testing
import Foundation
import AppKit
@testable import ClaudeMonitor

@MainActor struct ComponentStatusTests {

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
}
