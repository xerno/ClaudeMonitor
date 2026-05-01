import Testing
import Foundation
@testable import ClaudeMonitor

struct TimeUntilTests {

    @Test func timeUntilZero() {
        let now = Date()
        #expect(Formatting.timeUntil(now, now: now) == "0s")
    }

    @Test func timeUntilSubSecond() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(0.9), now: now) == "0s")
    }

    @Test func timeUntilOneSecond() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(1), now: now) == "1s")
    }

    @Test func timeUntil47Seconds() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(47), now: now) == "47s")
    }

    @Test func timeUntil59Seconds() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(59), now: now) == "59s")
    }

    @Test func timeUntil1MinuteExactly() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(60), now: now) == "1m")
    }

    @Test func timeUntil1Minute30Seconds() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(90), now: now) == "1m 30s")
    }

    @Test func timeUntil1Minute59Seconds() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(119), now: now) == "1m 59s")
    }

    @Test func timeUntil2MinutesExactly() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(120), now: now) == "2m")
    }

    @Test func timeUntil14Minutes() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(840), now: now) == "14m")
    }

    @Test func timeUntil59Minutes59Seconds() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(3599), now: now) == "59m")
    }

    @Test func timeUntil1HourExactly() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(3600), now: now) == "1h")
    }

    @Test func timeUntil3Hours21Minutes() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(12060), now: now) == "3h 21m")
    }

    @Test func timeUntil23Hours59Minutes() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(86399), now: now) == "23h 59m")
    }

    @Test func timeUntil24HoursExactly() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(86400), now: now) == "24h")
    }

    @Test func timeUntil24Hours59Minutes() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(89999), now: now) == "24h 59m")
    }

    @Test func timeUntil25HoursExactly() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(90000), now: now) == "1d 1h")
    }

    @Test func timeUntil1Day4Hours() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(100800), now: now) == "1d 4h")
    }

    @Test func timeUntil7DaysExactly() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(604800), now: now) == "7d")
    }

    @Test func timeUntilNegative() {
        let now = Date()
        #expect(Formatting.timeUntil(now.addingTimeInterval(-5), now: now) == "0s")
    }
}
