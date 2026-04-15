import Testing
import Foundation
@testable import ClaudeMonitor

struct FormatRateTests {

    // MARK: - Per-hour branch (perHour >= 0.5)

    @Test func rateAboveHourThreshold() {
        // 1%/h → perHour = 1.0, formatted as "1%/h"
        let rate = 1.0 / Constants.Time.secondsPerHour
        #expect(Formatting.formatRate(rate) == "1%/h")
    }

    @Test func rateLargePerHour() {
        // 60%/h → perHour = 60
        let rate = 60.0 / Constants.Time.secondsPerHour
        #expect(Formatting.formatRate(rate) == "60%/h")
    }

    @Test func rateExactlyHalfPerHour() {
        // perHour = exactly 0.5 → rounds to 0%/h? No — 0.5 rounds to 0 via Int(0.5.rounded()).
        // Int(round(0.5)) = 1 in Swift (rounds half to even? No, .rounded() uses .toNearestOrAwayFromZero = 1)
        // Actually: 0.5.rounded() == 1.0, Int(1.0) == 1
        // But the condition is >= 0.5 AND the display is Int(perHour.rounded())
        // So perHour = 0.5 → condition met, Int(0.5.rounded()) = Int(1.0) = 1 → "1%/h"
        let rate = 0.5 / Constants.Time.secondsPerHour
        #expect(Formatting.formatRate(rate) == "1%/h")
    }

    @Test func rateJustBelowHourThreshold() {
        // perHour = 0.499 → falls through to per-day check
        // perDay = 0.499 * 24 ≈ 11.97 → >= 0.5 → "12%/d"
        let rate = 0.499 / Constants.Time.secondsPerHour
        let perDay = rate * 86400  // ≈ 11.97
        let expected = "\(Int(perDay.rounded()))%/d"
        #expect(Formatting.formatRate(rate) == expected)
    }

    // MARK: - Per-day branch (perHour < 0.5, perDay >= 0.5)

    @Test func rateBelowHourAboveDay() {
        // Set perHour = 0.1 (< 0.5) → falls to per-day
        // perDay = 0.1 * 24 = 2.4 → "2%/d"
        let rate = 0.1 / Constants.Time.secondsPerHour
        #expect(Formatting.formatRate(rate) == "2%/d")
    }

    @Test func rateExactlyHalfPerDay() {
        // perHour < 0.5, perDay = exactly 0.5 → Int(0.5.rounded()) = 1 → "1%/d"
        let rate = 0.5 / 86400.0
        #expect(Formatting.formatRate(rate) == "1%/d")
    }

    @Test func rateJustBelowDayThreshold() {
        // perDay = 0.499 → below 0.5 → minimal string
        // String(localized:) returns the .strings value verbatim: "< 1%%/d"
        let rate = 0.499 / 86400.0
        #expect(Formatting.formatRate(rate) == "< 1%%/d")
    }

    // MARK: - Minimal branch (perDay < 0.5)

    @Test func rateVerySmall() {
        // 0.001%/d → way below both thresholds → minimal string
        let rate = 0.001 / 86400.0
        #expect(Formatting.formatRate(rate) == "< 1%%/d")
    }

    @Test func rateZero() {
        #expect(Formatting.formatRate(0) == "< 1%%/d")
    }
}
