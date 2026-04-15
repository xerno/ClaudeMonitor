import Testing
import Foundation
@testable import ClaudeMonitor

struct WindowKeyParserTests {

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

    @Test func parserFortyEightHour() {
        let parsed = WindowKeyParser.parse("forty_eight_hour")
        #expect(parsed?.duration == 48.0 * 3600)
        #expect(parsed?.durationLabel == "48h")
        #expect(parsed?.modelScope == nil)
    }

    @Test func parserFiftyMinute() {
        let parsed = WindowKeyParser.parse("fifty_minute")
        #expect(parsed?.duration == 50.0 * 60)
        #expect(parsed?.durationLabel == "50m")
        #expect(parsed?.modelScope == nil)
    }

    @Test func parserSixtyDay() {
        let parsed = WindowKeyParser.parse("sixty_day")
        #expect(parsed?.duration == 60.0 * 86400)
        #expect(parsed?.durationLabel == "60d")
        #expect(parsed?.modelScope == nil)
    }

    @Test func parserNinetyNineHour() {
        let parsed = WindowKeyParser.parse("ninety_nine_hour")
        #expect(parsed?.duration == 99.0 * 3600)
        #expect(parsed?.durationLabel == "99h")
        #expect(parsed?.modelScope == nil)
    }

    @Test func parserSeventyTwoHourWithModel() {
        let parsed = WindowKeyParser.parse("seventy_two_hour_opus")
        #expect(parsed?.duration == 72.0 * 3600)
        #expect(parsed?.durationLabel == "72h")
        #expect(parsed?.modelScope == "Opus")
    }

    @Test func parserEightyWeek() {
        let parsed = WindowKeyParser.parse("eighty_week")
        #expect(parsed?.duration == 80.0 * 604_800)
        #expect(parsed?.durationLabel == "80w")
        #expect(parsed?.modelScope == nil)
    }

    @Test func parserUnknownFormat() {
        #expect(WindowKeyParser.parse("foo") == nil)
        #expect(WindowKeyParser.parse("") == nil)
        #expect(WindowKeyParser.parse("five") == nil)
        #expect(WindowKeyParser.parse("blah_hour") == nil)
    }

    // MARK: - isInternalWindow

    @Test func isInternalWindowLowercase() {
        #expect(WindowKeyParser.isInternalWindow("omelette"))
    }

    @Test func isInternalWindowUppercase() {
        #expect(!WindowKeyParser.isInternalWindow("OMELETTE"))
    }

    @Test func isInternalWindowMixedCase() {
        #expect(!WindowKeyParser.isInternalWindow("Omelette"))
    }

    @Test func isInternalWindowSubstring() {
        #expect(WindowKeyParser.isInternalWindow("five_hour_omelette"))
    }

    @Test func isInternalWindowNormalKey() {
        #expect(!WindowKeyParser.isInternalWindow("five_hour"))
    }

    @Test func isInternalWindowSevenDay() {
        #expect(!WindowKeyParser.isInternalWindow("seven_day"))
    }
}
