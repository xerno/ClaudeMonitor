import Foundation
import Testing
@testable import ClaudeMonitor

@Suite @MainActor struct RateComputationTests {

    @Test func averageRateFromElapsedTime() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 60,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .implied)
        let expectedRate = 60.0 / 14400.0
        #expect(abs(rate - expectedRate) < 0.001)
    }

    @Test func averageRateFromElapsedTime2h() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(18000 - 7200)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 40,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .implied)
        let expectedRate = 40.0 / 7200.0
        #expect(abs(rate - expectedRate) < 0.001)
    }

    @Test func insufficientWhenNoResetsAt() {
        let now = Date()
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 50,
            resetsAt: nil,
            now: now
        )
        #expect(source == .insufficient)
        #expect(rate == 0)
    }

    @Test func zeroUtilizationGivesZeroRate() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 0,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .implied)
        #expect(rate == 0)
    }

    @Test func insufficientWhenWindowJustStarted() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(18000)
        let (rate, source) = UsageHistory.computeRate(
            windowDuration: 18000,
            currentUtilization: 0,
            resetsAt: resetsAt,
            now: now
        )
        #expect(source == .insufficient)
        #expect(rate == 0)
    }
}
