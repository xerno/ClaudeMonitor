import Testing
import Foundation
@testable import ClaudeMonitor

struct FormatRateTests {

    // MARK: - Per-hour branch (perHour >= 0.5)

    @Test func rateAboveHourThreshold() {
        let rate = 1.0 / Constants.Time.secondsPerHour
        #expect(Formatting.formatRate(rate) == "1%/h")
    }

    @Test func rateLargePerHour() {
        let rate = 60.0 / Constants.Time.secondsPerHour
        #expect(Formatting.formatRate(rate) == "60%/h")
    }

    @Test func rateExactlyHalfPerHour() {
        // Half rounds away from zero: 0.5 -> "1%/h".
        let rate = 0.5 / Constants.Time.secondsPerHour
        #expect(Formatting.formatRate(rate) == "1%/h")
    }

    @Test func rateJustBelowHourThreshold() {
        let rate = 0.499 / Constants.Time.secondsPerHour
        let perDay = rate * 86400
        let expected = "\(Int(perDay.rounded()))%/d"
        #expect(Formatting.formatRate(rate) == expected)
    }

    // MARK: - Per-day branch (perHour < 0.5, perDay >= 0.5)

    @Test func rateBelowHourAboveDay() {
        // 0.1 * 24 = 2.4 per day
        let rate = 0.1 / Constants.Time.secondsPerHour
        #expect(Formatting.formatRate(rate) == "2%/d")
    }

    @Test func rateExactlyHalfPerDay() {
        let rate = 0.5 / 86400.0
        #expect(Formatting.formatRate(rate) == "1%/d")
    }

    @Test func rateJustBelowDayThreshold() {
        let rate = 0.499 / 86400.0
        #expect(Formatting.formatRate(rate) == "< 1%/d")
    }

    // MARK: - Minimal branch (perDay < 0.5)

    @Test func rateVerySmall() {
        let rate = 0.001 / 86400.0
        #expect(Formatting.formatRate(rate) == "< 1%/d")
    }

    @Test func rateZero() {
        #expect(Formatting.formatRate(0) == "< 1%/d")
    }
}
