import XCTest
@testable import ClaudeMonitor

final class TimeUntilTests: XCTestCase {

    func testTimeUntilZero() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now, now: now), "0s")
    }

    func testTimeUntilSubSecond() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(0.9), now: now), "0s")
    }

    func testTimeUntilOneSecond() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(1), now: now), "1s")
    }

    func testTimeUntil47Seconds() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(47), now: now), "47s")
    }

    func testTimeUntil59Seconds() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(59), now: now), "59s")
    }

    func testTimeUntil1MinuteExactly() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(60), now: now), "1m 0s")
    }

    func testTimeUntil1Minute30Seconds() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(90), now: now), "1m 30s")
    }

    func testTimeUntil1Minute59Seconds() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(119), now: now), "1m 59s")
    }

    func testTimeUntil2MinutesExactly() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(120), now: now), "2m")
    }

    func testTimeUntil14Minutes() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(840), now: now), "14m")
    }

    func testTimeUntil59Minutes59Seconds() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(3599), now: now), "59m")
    }

    func testTimeUntil1HourExactly() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(3600), now: now), "1h 0m")
    }

    func testTimeUntil3Hours21Minutes() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(12060), now: now), "3h 21m")
    }

    func testTimeUntil23Hours59Minutes() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(86399), now: now), "23h 59m")
    }

    func testTimeUntil24HoursExactly() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(86400), now: now), "24h 0m")
    }

    func testTimeUntil24Hours59Minutes() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(89999), now: now), "24h 59m")
    }

    func testTimeUntil25HoursExactly() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(90000), now: now), "1d 1h")
    }

    func testTimeUntil1Day4Hours() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(100800), now: now), "1d 4h")
    }

    func testTimeUntil7DaysExactly() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(604800), now: now), "7d 0h")
    }

    func testTimeUntilNegative() {
        let now = Date()
        XCTAssertEqual(Formatting.timeUntil(now.addingTimeInterval(-5), now: now), "0s")
    }
}
