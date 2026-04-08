import Testing
import Foundation
@testable import ClaudeMonitor

struct DecodingTests {

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
