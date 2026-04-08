import Testing
import Foundation
@testable import ClaudeMonitor

@MainActor struct WindowKeyParserTests {

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
}
