import XCTest
@testable import ClaudeMonitor

final class ModelsTests: XCTestCase {

    // MARK: - ComponentStatus Comparable

    func testSeverityOrder() {
        XCTAssertLessThan(ComponentStatus.unknown, .operational)
        XCTAssertLessThan(ComponentStatus.operational, .underMaintenance)
        XCTAssertLessThan(ComponentStatus.underMaintenance, .degradedPerformance)
        XCTAssertLessThan(ComponentStatus.degradedPerformance, .partialOutage)
        XCTAssertLessThan(ComponentStatus.partialOutage, .majorOutage)
    }

    func testComparableConsistentWithEquatable() {
        let all: [ComponentStatus] = [.unknown, .operational, .underMaintenance, .degradedPerformance, .partialOutage, .majorOutage]
        for (i, a) in all.enumerated() {
            for (j, b) in all.enumerated() {
                if i == j {
                    XCTAssertEqual(a, b)
                    XCTAssertFalse(a < b)
                    XCTAssertFalse(b < a)
                } else if i < j {
                    XCTAssertLessThan(a, b)
                    XCTAssertNotEqual(a, b)
                }
            }
        }
    }

    func testMaxReturnsHighestSeverity() {
        let statuses: [ComponentStatus] = [.operational, .partialOutage, .degradedPerformance]
        XCTAssertEqual(statuses.max(), .partialOutage)
    }

    // MARK: - ComponentStatus Labels & Dots

    func testLabels() {
        XCTAssertEqual(ComponentStatus.operational.label, "Operational")
        XCTAssertEqual(ComponentStatus.degradedPerformance.label, "Degraded")
        XCTAssertEqual(ComponentStatus.partialOutage.label, "Partial Outage")
        XCTAssertEqual(ComponentStatus.majorOutage.label, "Major Outage")
        XCTAssertEqual(ComponentStatus.underMaintenance.label, "Maintenance")
        XCTAssertEqual(ComponentStatus.unknown.label, "Unknown")
    }

    func testDots() {
        XCTAssertEqual(ComponentStatus.operational.dot, "🟢")
        XCTAssertEqual(ComponentStatus.majorOutage.dot, "🔴")
        XCTAssertEqual(ComponentStatus.unknown.dot, "⚪")
    }

    // MARK: - Decoding

    func testDecodingKnownStatus() throws {
        let json = #"{"id":"1","name":"API","status":"degraded_performance"}"#.data(using: .utf8)!
        let component = try JSONDecoder().decode(StatusComponent.self, from: json)
        XCTAssertEqual(component.status, .degradedPerformance)
        XCTAssertEqual(component.name, "API")
    }

    func testDecodingUnknownStatusFallsBack() throws {
        let json = #"{"id":"1","name":"API","status":"something_new"}"#.data(using: .utf8)!
        let component = try JSONDecoder().decode(StatusComponent.self, from: json)
        XCTAssertEqual(component.status, .unknown)
    }

    // MARK: - UsageResponse

    func testUsageResponseDecoding() throws {
        let json = """
        {
            "five_hour": {"utilization": 42, "resets_at": "2026-04-01T15:00:00.000Z"},
            "seven_day": {"utilization": 18, "resets_at": "2026-04-07T00:00:00.000Z"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 42)
        XCTAssertEqual(response.sevenDay?.utilization, 18)
        XCTAssertNil(response.sevenDaySonnet)
    }

    func testUsageResponseDecodingWithoutFractionalSeconds() throws {
        let json = """
        {
            "five_hour": {"utilization": 50, "resets_at": "2026-04-01T15:00:00Z"}
        }
        """.data(using: .utf8)!

        let response = try JSONDecoder.iso8601WithFractionalSeconds.decode(UsageResponse.self, from: json)
        XCTAssertEqual(response.fiveHour?.utilization, 50)
    }

    func testUsageResponseAllNil() throws {
        let json = "{}".data(using: .utf8)!
        let response = try JSONDecoder().decode(UsageResponse.self, from: json)
        XCTAssertNil(response.fiveHour)
        XCTAssertNil(response.sevenDay)
        XCTAssertNil(response.sevenDaySonnet)
    }

    // MARK: - StatusSummary

    func testStatusSummaryDecoding() throws {
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
        XCTAssertEqual(summary.components.count, 2)
        XCTAssertEqual(summary.incidents.count, 1)
        XCTAssertEqual(summary.incidents.first?.name, "API issues")
        XCTAssertEqual(summary.status.indicator, "major")
        XCTAssertEqual(summary.components.map(\.status).max(), .majorOutage)
    }

    // MARK: - Equatable

    func testUsageWindowEquality() {
        let date = Date()
        let a = UsageWindow(utilization: 42, resetsAt: date)
        let b = UsageWindow(utilization: 42, resetsAt: date)
        let c = UsageWindow(utilization: 50, resetsAt: date)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
