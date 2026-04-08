import Testing
import Foundation
@testable import ClaudeMonitor

struct ProgressBarTests {

    @Test func progressBarZero() {
        #expect(Formatting.progressBar(percent: 0) == "░░░░░░░░░░")
    }

    @Test func progressBarFull() {
        #expect(Formatting.progressBar(percent: 100) == "██████████")
    }

    @Test func progressBarHalf() {
        #expect(Formatting.progressBar(percent: 50) == "█████░░░░░")
    }

    @Test func progressBarClampsAbove100() {
        #expect(Formatting.progressBar(percent: 150) == "██████████")
    }

    @Test func progressBarClampsBelow0() {
        #expect(Formatting.progressBar(percent: -10) == "░░░░░░░░░░")
    }

    @Test func progressBarCustomWidth() {
        #expect(Formatting.progressBar(percent: 50, width: 4) == "██░░")
    }
}
