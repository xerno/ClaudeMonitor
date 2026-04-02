import XCTest
@testable import ClaudeMonitor

final class NextTickTargetTests: XCTestCase {

    func testNextTickTargetSecondsZone() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(-47.3)
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-46.5))
    }

    func testNextTickTargetSecondsZoneExactBoundary() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(-47.0)
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-46.5))
    }

    func testNextTickTargetSecondsZoneExactCenter() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(-46.5)  // exactly at center of "46s" interval
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-45.5))
    }

    func testNextTickTargetMinutesZone() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(-14 * 60 - 45)  // 14m 45s remaining
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-13 * 60 - 30))
    }

    func testNextTickTargetMinutesZoneExactCenter() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(-14 * 60 - 30)  // 14m 30s remaining, center of "14m"
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-13 * 60 - 30))
    }

    func testNextTickTargetMixedZone() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(-92)  // 1m 32s remaining
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-91.5))
    }

    func testNextTickTargetHoursZone() {
        let T = Date(timeIntervalSinceReferenceDate: 100000)
        let now = T.addingTimeInterval(-3 * 3600 - 21 * 60 - 15)  // 3h 21m 15s
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-3 * 3600 - 20 * 60 - 30))
    }

    func testNextTickTargetDaysZone() {
        let T = Date(timeIntervalSinceReferenceDate: 200000)
        let now = T.addingTimeInterval(-26 * 3600 - 30 * 60)  // 26h 30m — safely inside days zone
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-25 * 3600 - 30 * 60))
    }

    func testNextTickTargetDaysToHoursBoundary() {
        let T = Date(timeIntervalSinceReferenceDate: 200000)
        let now = T.addingTimeInterval(-25 * 3600 - 5 * 60)  // 25h 5m — first interval in days zone
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-90000 + 30))  // center of "24h 59m" interval
    }

    func testNextTickTargetMinutesToMixedBoundary() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(-121)  // 2m 1s — first interval in minutes zone
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-119.5))  // center of "1m 59s" interval
    }

    func testNextTickTargetMinutesZoneNoBoundary() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(-181)  // 3m 1s — next interval still in minutes zone
        let target = Formatting.nextTickTargetSingle(resetTime: T, now: now)
        XCTAssertEqual(target, T.addingTimeInterval(-2 * 60 - 30))  // center of "2m" interval
    }

    func testNextTickTargetPastResetReturnsNil() {
        let T = Date(timeIntervalSinceReferenceDate: 10000)
        let now = T.addingTimeInterval(5)  // past the reset
        XCTAssertNil(Formatting.nextTickTargetSingle(resetTime: T, now: now))
    }

    func testNextTickTargetMultipleReturnsEarliest() {
        let T1 = Date(timeIntervalSinceReferenceDate: 10000)
        let T2 = Date(timeIntervalSinceReferenceDate: 20000)
        let now = T1.addingTimeInterval(-47.3)  // 47.3s to T1, much more to T2
        let target = Formatting.nextTickTarget(resetTimes: [T1, T2], now: now)
        // T1 target = T1 - 46.5 (earlier), T2 target computed from its remaining which is much larger
        XCTAssertEqual(target, T1.addingTimeInterval(-46.5))
    }
}
