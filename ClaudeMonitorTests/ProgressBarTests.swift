import XCTest
@testable import ClaudeMonitor

final class ProgressBarTests: XCTestCase {

    func testProgressBarZero() {
        let bar = Formatting.progressBar(percent: 0)
        XCTAssertEqual(bar, "░░░░░░░░░░")
    }

    func testProgressBarFull() {
        let bar = Formatting.progressBar(percent: 100)
        XCTAssertEqual(bar, "██████████")
    }

    func testProgressBarHalf() {
        let bar = Formatting.progressBar(percent: 50)
        XCTAssertEqual(bar, "█████░░░░░")
    }

    func testProgressBarClampsAbove100() {
        let bar = Formatting.progressBar(percent: 150)
        XCTAssertEqual(bar, "██████████")
    }

    func testProgressBarClampsBelow0() {
        let bar = Formatting.progressBar(percent: -10)
        XCTAssertEqual(bar, "░░░░░░░░░░")
    }

    func testProgressBarCustomWidth() {
        let bar = Formatting.progressBar(percent: 50, width: 4)
        XCTAssertEqual(bar, "██░░")
    }
}
