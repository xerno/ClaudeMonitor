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

    // At 50% remaining, projected = 2 × utilization.

    @Test func styleNormal() {
        let s = style(utilization: 10, timeRemainingPercent: 50)
        #expect(s.level == .normal)
        #expect(!s.isBold)
    }

    @Test func styleBoldByProjection() {
        let s = style(utilization: 40, timeRemainingPercent: 50)
        #expect(s.level == .normal)
        #expect(s.isBold)
    }

    @Test func styleWarningByProjection() {
        let s = style(utilization: 50, timeRemainingPercent: 50)
        #expect(s.level == .warning)
        #expect(s.isBold)
    }

    @Test func styleCriticalByProjection() {
        let s = style(utilization: 60, timeRemainingPercent: 50)
        #expect(s.level == .critical)
        #expect(s.isBold)
    }

    @Test func styleRedByFixedThreshold() {
        let s = style(utilization: 100, timeRemainingPercent: 80)
        #expect(s.level == .critical)
        #expect(s.isBold)
    }

    @Test func styleRedByHighUtilization() {
        let s = style(utilization: 78, timeRemainingPercent: 60)
        #expect(s.level == .critical)
        #expect(s.isBold)
    }

    @Test func styleAtExactBoldThreshold() {
        // 79 / 0.9875 elapsed = 80.0
        let s = style(utilization: 79, timeRemainingPercent: 1.25)
        #expect(s.level == .normal)
        #expect(s.isBold)
    }

    @Test func styleJustBelowBoldThreshold() {
        let s = style(utilization: 78, timeRemainingPercent: 1.25)
        #expect(s.level == .normal)
        #expect(!s.isBold)
    }

    @Test func styleAtExactWarningThreshold() {
        // 99 / 0.99 elapsed = 100.0
        let s = style(utilization: 99, timeRemainingPercent: 1)
        #expect(s.level == .warning)
        #expect(s.isBold)
    }

    @Test func styleJustBelowWarningThreshold() {
        let s = style(utilization: 98, timeRemainingPercent: 1)
        #expect(s.level == .normal)
        #expect(s.isBold)
    }

    // The critical pair stays below 100: utilization >= 100 is critical whatever the projection,
    // so such a fixture would pass without exercising the 120 threshold.

    @Test func styleAtExactCriticalThreshold() {
        let s = style(utilization: 60, timeRemainingPercent: 50)
        #expect(s.level == .critical)
        #expect(s.isBold)
    }

    @Test func styleJustBelowCriticalThreshold() {
        let s = style(utilization: 59, timeRemainingPercent: 50)
        #expect(s.level == .warning)
        #expect(s.isBold)
    }

    @Test func styleNotBoldWhenLowProjection() {
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

    // MARK: - Fallback path (resetsAt: nil)

    private func fallbackStyle(utilization: Int) -> Formatting.UsageStyle {
        Formatting.usageStyle(utilization: utilization, resetsAt: nil, windowDuration: 1000)
    }

    @Test func fallbackBelowBoldThreshold() {
        let s = fallbackStyle(utilization: 79)
        #expect(s.level == .normal)
        #expect(!s.isBold)
    }

    @Test func fallbackAtBoldThreshold() {
        let s = fallbackStyle(utilization: 80)
        #expect(s.level == .normal)
        #expect(s.isBold)
    }

    @Test func fallbackBelowWarningThreshold() {
        let s = fallbackStyle(utilization: 89)
        #expect(s.level == .normal)
        #expect(s.isBold)
    }

    @Test func fallbackAtWarningThreshold() {
        let s = fallbackStyle(utilization: 90)
        #expect(s.level == .warning)
        #expect(s.isBold)
    }

    @Test func fallbackBelowCriticalThreshold() {
        let s = fallbackStyle(utilization: 94)
        #expect(s.level == .warning)
        #expect(s.isBold)
    }

    @Test func fallbackAtCriticalThreshold() {
        let s = fallbackStyle(utilization: 95)
        #expect(s.level == .critical)
        #expect(s.isBold)
    }

    @Test func fallbackBlocked() {
        let s = fallbackStyle(utilization: 100)
        #expect(s.level == .critical)
        #expect(s.isBold)
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
        #expect(!shouldShow(utilization: 10, timeRemainingPercent: 50))
    }

    @Test func shouldShowProjectionAtBoldThreshold() {
        #expect(shouldShow(utilization: 40, timeRemainingPercent: 50))
    }

    @Test func shouldShowHighProjection() {
        #expect(shouldShow(utilization: 65, timeRemainingPercent: 40))
    }

    @Test func shouldShowLowUtilizationLittleTime() {
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
