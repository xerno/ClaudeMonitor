import Testing
import Foundation
import AppKit
@testable import ClaudeMonitor

@MainActor struct UsageStyleTests {

    private func style(utilization: Int, timeRemainingPercent: Double) -> Formatting.UsageStyle {
        let now = Date()
        let windowDuration: TimeInterval = 1000
        let resetsAt = now.addingTimeInterval(windowDuration * timeRemainingPercent / 100)
        return Formatting.usageStyle(
            utilization: utilization,
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            now: now
        )
    }

    @Test func styleNormal() {
        let s = style(utilization: 30, timeRemainingPercent: 70)
        #expect(s.color == .labelColor)
        #expect(!s.isBold)
    }

    @Test func styleBoldByFixedThreshold() {
        // 55% used, 50% time remaining (50% elapsed) — bold by fixed (≥50), not orange (55 < 70)
        let s = style(utilization: 55, timeRemainingPercent: 50)
        #expect(s.color == .labelColor)
        #expect(s.isBold)
    }

    @Test func styleBoldByTimeRule() {
        // 45% used, 60% time remaining (40% elapsed) — projected 112%, outpacing
        let s = style(utilization: 45, timeRemainingPercent: 60)
        #expect(s.color == .labelColor)
        #expect(s.isBold)
    }

    @Test func styleOrangeByFixedThreshold() {
        // 72% used, 50% time remaining (50% elapsed) — orange by fixed (≥70), not red (72 < 85)
        let s = style(utilization: 72, timeRemainingPercent: 50)
        #expect(s.color == .systemOrange)
        #expect(s.isBold)
    }

    @Test func styleOrangeByTimeRule() {
        // 65% used, 60% time remaining (40% elapsed) — 65 > 40+20, projected 162%
        let s = style(utilization: 65, timeRemainingPercent: 60)
        #expect(s.color == .systemOrange)
        #expect(s.isBold)
    }

    @Test func styleRedByFixedThreshold() {
        let s = style(utilization: 85, timeRemainingPercent: 80)
        #expect(s.color == .systemRed)
        #expect(s.isBold)
    }

    @Test func styleRedByTimeRule() {
        // 78% used, 60% time remaining (40% elapsed) — 78 > 40+35, projected 195%
        let s = style(utilization: 78, timeRemainingPercent: 60)
        #expect(s.color == .systemRed)
        #expect(s.isBold)
    }

    @Test func styleNotBoldWhenPlentyOfTime() {
        // 15% used, 80% time remaining (20% elapsed) — projected 75%, comfortable
        let s = style(utilization: 15, timeRemainingPercent: 80)
        #expect(s.color == .labelColor)
        #expect(!s.isBold)
    }

    @Test func stylePastResetDate() {
        let now = Date()
        let resetsAt = now.addingTimeInterval(-100)
        let s = Formatting.usageStyle(utilization: 10, resetsAt: resetsAt, windowDuration: 1000, now: now)
        #expect(!s.isBold)
    }

    private func shouldShow(utilization: Int, timeRemainingPercent: Double) -> Bool {
        let now = Date()
        let windowDuration: TimeInterval = 1000
        let resetsAt = now.addingTimeInterval(windowDuration * timeRemainingPercent / 100)
        return Formatting.shouldShowInMenuBar(
            utilization: utilization,
            resetsAt: resetsAt,
            windowDuration: windowDuration,
            now: now
        )
    }

    @Test func shouldShowLowUtilizationPlentyOfTime() {
        #expect(!shouldShow(utilization: 30, timeRemainingPercent: 70))
    }

    @Test func shouldShowHighUtilizationNotOutpacing() {
        // 55% used, 40% time remaining (60% elapsed) — bold (fixed) but NOT outpacing (55 < 60)
        #expect(!shouldShow(utilization: 55, timeRemainingPercent: 40))
    }

    @Test func shouldShowLowUtilizationLittleTime() {
        // 20% used, 10% time remaining (90% elapsed) — not outpacing (20 < 90), no show
        #expect(!shouldShow(utilization: 20, timeRemainingPercent: 10))
    }

    @Test func shouldShowHighUtilizationOutpacingTime() {
        // 65% used, 40% time remaining (60% elapsed) — bold AND outpacing (65 > 60)
        #expect(shouldShow(utilization: 65, timeRemainingPercent: 40))
    }

    @Test func shouldShowExactlyAtBoundary() {
        // 50% used, 50% time remaining (50% elapsed) — bold (fixed) but NOT outpacing (equal)
        #expect(!shouldShow(utilization: 50, timeRemainingPercent: 50))
    }

    @Test func shouldShowPastResetDate() {
        let now = Date()
        let result = Formatting.shouldShowInMenuBar(
            utilization: 10,
            resetsAt: now.addingTimeInterval(-100),
            windowDuration: 1000,
            now: now
        )
        #expect(!result)
    }
}
