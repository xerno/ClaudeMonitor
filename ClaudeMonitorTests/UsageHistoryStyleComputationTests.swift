import Foundation
import Testing
@testable import ClaudeMonitor

@Suite @MainActor struct StyleComputationTests {

    private func computeStyle(projected: Double, utilization: Int, timeRemaining: TimeInterval, resetsAt: Date?) -> Formatting.UsageStyle {
        Formatting.usageStyle(
            projectedAtReset: projected,
            utilization: utilization,
            resetsAt: resetsAt,
            timeRemaining: timeRemaining
        )
    }

    @Test func normalWhenProjectedUnder80() {
        let now = Date()
        let style = computeStyle(projected: 60, utilization: 30, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .normal)
        #expect(!style.isBold)
    }

    @Test func boldWhenProjected80to99() {
        let now = Date()
        let style = computeStyle(projected: 85, utilization: 40, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .normal)
        #expect(style.isBold)
    }

    @Test func warningWhenProjected100to119() {
        let now = Date()
        let style = computeStyle(projected: 110, utilization: 50, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .warning)
        #expect(style.isBold)
    }

    @Test func criticalWhenProjected120plus() {
        let now = Date()
        let style = computeStyle(projected: 130, utilization: 60, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .critical)
        #expect(style.isBold)
    }

    @Test func criticalWhenBlocked() {
        let now = Date()
        let style = computeStyle(projected: 50, utilization: 100, timeRemaining: 3600, resetsAt: now.addingTimeInterval(3600))
        #expect(style.level == .critical)
        #expect(style.isBold)
    }

    @Test func normalWhenTimeRemainingZero() {
        let now = Date()
        let style = computeStyle(projected: 150, utilization: 70, timeRemaining: 0, resetsAt: now.addingTimeInterval(0))
        #expect(style.level == .normal)
        #expect(!style.isBold)
    }

    @Test func fallbackThresholdsWhenNoResetsAt() {
        let style = computeStyle(projected: 92, utilization: 92, timeRemaining: 3600, resetsAt: nil)
        #expect(style.level == .warning)
        #expect(style.isBold)
    }
}
