import Testing
import Foundation
@testable import ClaudeMonitor

struct UsageStyleTests {

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

    // windowDuration=1000, timeRemaining=500 (50% remaining), timeElapsed=500
    // impliedRate = utilization / 500, projected = utilization + rate * 500 = utilization * 2

    @Test func styleNormal() {
        // 10% used, 50% remaining → projected = 10 + (10/500)*500 = 20 → normal, not bold
        let s = style(utilization: 10, timeRemainingPercent: 50)
        #expect(s.level == .normal)
        #expect(!s.isBold)
    }

    @Test func styleBoldByProjection() {
        // 40% used, 50% remaining → projected = 40 + (40/500)*500 = 80 → bold (≥80)
        let s = style(utilization: 40, timeRemainingPercent: 50)
        #expect(s.level == .normal)
        #expect(s.isBold)
    }

    @Test func styleWarningByProjection() {
        // 50% used, 50% remaining → projected = 50 + (50/500)*500 = 100 → warning (≥100)
        let s = style(utilization: 50, timeRemainingPercent: 50)
        #expect(s.level == .warning)
        #expect(s.isBold)
    }

    @Test func styleCriticalByProjection() {
        // 60% used, 50% remaining → projected = 60 + (60/500)*500 = 120 → critical (≥120)
        let s = style(utilization: 60, timeRemainingPercent: 50)
        #expect(s.level == .critical)
        #expect(s.isBold)
    }

    @Test func styleRedByFixedThreshold() {
        // utilization ≥ 100 → always critical regardless of projection
        let s = style(utilization: 100, timeRemainingPercent: 80)
        #expect(s.level == .critical)
        #expect(s.isBold)
    }

    @Test func styleRedByHighUtilization() {
        // 78% used, 60% remaining → projected = 78 + (78/400)*600 = 78+117 = 195 → critical
        let s = style(utilization: 78, timeRemainingPercent: 60)
        #expect(s.level == .critical)
        #expect(s.isBold)
    }

    @Test func styleNotBoldWhenLowProjection() {
        // 15% used, 80% remaining → elapsed=200, rate=0.075%/s, projected=15+0.075*800=75 → not bold
        let s = style(utilization: 15, timeRemainingPercent: 80)
        #expect(s.level == .normal)
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

    @Test func shouldShowLowProjection() {
        // 10% used, 50% remaining → projected = 20 → no show (< 80)
        #expect(!shouldShow(utilization: 10, timeRemainingPercent: 50))
    }

    @Test func shouldShowProjectionAtBoldThreshold() {
        // 40% used, 50% remaining → projected = 80 → show (≥ 80)
        #expect(shouldShow(utilization: 40, timeRemainingPercent: 50))
    }

    @Test func shouldShowHighProjection() {
        // 65% used, 40% remaining → elapsed=600, rate=65/600, projected=65+(65/600)*400 ≈ 108 → show
        #expect(shouldShow(utilization: 65, timeRemainingPercent: 40))
    }

    @Test func shouldShowLowUtilizationLittleTime() {
        // 20% used, 10% remaining (90% elapsed) → elapsed=900, rate=20/900, projected=20+(20/900)*100≈22 → no show
        #expect(!shouldShow(utilization: 20, timeRemainingPercent: 10))
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

    // MARK: - UsageLevel Comparable

    @Test func usageLevelNormalLessThanWarning() {
        #expect(Formatting.UsageLevel.normal < .warning)
    }

    @Test func usageLevelWarningLessThanCritical() {
        #expect(Formatting.UsageLevel.warning < .critical)
    }

    @Test func usageLevelNormalLessThanCritical() {
        #expect(Formatting.UsageLevel.normal < .critical)
    }

    @Test func usageLevelEquality() {
        #expect(!(Formatting.UsageLevel.normal < .normal))
        #expect(!(Formatting.UsageLevel.warning < .warning))
        #expect(!(Formatting.UsageLevel.critical < .critical))
    }

    // MARK: - UsageStyle Comparable

    @Test func usageStyleNotBoldLessThanBoldAtSameLevel() {
        let notBold = Formatting.UsageStyle(level: .normal, isBold: false)
        let bold = Formatting.UsageStyle(level: .normal, isBold: true)
        #expect(notBold < bold)
    }

    @Test func usageStyleNormalBoldLessThanWarningNotBold() {
        let normalBold = Formatting.UsageStyle(level: .normal, isBold: true)
        let warningNotBold = Formatting.UsageStyle(level: .warning, isBold: false)
        #expect(normalBold < warningNotBold)
    }

    @Test func usageStyleLevelDominatesOverBold() {
        // warning (not bold) > normal (bold)
        let normalBold = Formatting.UsageStyle(level: .normal, isBold: true)
        let warningNotBold = Formatting.UsageStyle(level: .warning, isBold: false)
        #expect(!(warningNotBold < normalBold))
    }

    @Test func usageStyleNormalNotBoldIsMinimum() {
        let min = Formatting.UsageStyle(level: .normal, isBold: false)
        let max = Formatting.UsageStyle(level: .critical, isBold: true)
        #expect(min < max)
    }
}
