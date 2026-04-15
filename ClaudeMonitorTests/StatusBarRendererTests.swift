import Testing
import AppKit
@testable import ClaudeMonitor

@MainActor struct StatusBarRendererTests {

    private func status(with componentStatus: ComponentStatus) -> StatusSummary {
        StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: componentStatus)],
            incidents: [],
            status: PageStatus(indicator: "none", description: "")
        )
    }

    // MARK: - resolveIcon

    @Test func resolveIconRefreshWarningTakesPriority() {
        let icon = StatusBarRenderer.resolveIcon(
            status: status(with: .majorOutage), hasRefreshWarning: true
        )
        #expect(icon.symbolName == "exclamationmark.triangle.fill")
        #expect(icon.color == .systemYellow)
    }

    @Test func resolveIconNilStatus() {
        let icon = StatusBarRenderer.resolveIcon(status: nil, hasRefreshWarning: false)
        #expect(icon.symbolName == "checkmark.circle.fill")
        #expect(icon.color == .systemGreen)
    }

    @Test func resolveIconMajorOutage() {
        let icon = StatusBarRenderer.resolveIcon(
            status: status(with: .majorOutage), hasRefreshWarning: false
        )
        #expect(icon.symbolName == "xmark.circle.fill")
        #expect(icon.color == .systemRed)
    }

    @Test func resolveIconPartialOutage() {
        let icon = StatusBarRenderer.resolveIcon(
            status: status(with: .partialOutage), hasRefreshWarning: false
        )
        #expect(icon.symbolName == "exclamationmark.circle.fill")
        #expect(icon.color == .systemOrange)
    }

    @Test func resolveIconDegradedPerformance() {
        let icon = StatusBarRenderer.resolveIcon(
            status: status(with: .degradedPerformance), hasRefreshWarning: false
        )
        #expect(icon.symbolName == "exclamationmark.circle.fill")
        #expect(icon.color == .systemYellow)
    }

    @Test func resolveIconUnderMaintenance() {
        let icon = StatusBarRenderer.resolveIcon(
            status: status(with: .underMaintenance), hasRefreshWarning: false
        )
        #expect(icon.symbolName == "wrench.and.screwdriver.fill")
        #expect(icon.color == .systemBlue)
    }

    @Test func resolveIconOperational() {
        let icon = StatusBarRenderer.resolveIcon(
            status: status(with: .operational), hasRefreshWarning: false
        )
        #expect(icon.symbolName == "checkmark.circle.fill")
        #expect(icon.color == .systemGreen)
    }

    @Test func resolveIconUnknown() {
        let icon = StatusBarRenderer.resolveIcon(
            status: status(with: .unknown), hasRefreshWarning: false
        )
        #expect(icon.symbolName == "checkmark.circle.fill")
        #expect(icon.color == .systemGreen)
    }

    @Test func resolveIconWorstSeverityWins() {
        let mixed = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "API", status: .operational),
                StatusComponent(id: "2", name: "Web", status: .partialOutage),
                StatusComponent(id: "3", name: "iOS", status: .degradedPerformance),
            ],
            incidents: [],
            status: PageStatus(indicator: "minor", description: "")
        )
        let icon = StatusBarRenderer.resolveIcon(status: mixed, hasRefreshWarning: false)
        #expect(icon.symbolName == "exclamationmark.circle.fill")
        #expect(icon.color == .systemOrange) // partialOutage is worst
    }

    @Test func resolveIconEmptyComponents() {
        let empty = StatusSummary(
            components: [],
            incidents: [],
            status: PageStatus(indicator: "none", description: "")
        )
        let icon = StatusBarRenderer.resolveIcon(status: empty, hasRefreshWarning: false)
        #expect(icon.symbolName == "checkmark.circle.fill")
        #expect(icon.color == .systemGreen)
    }

    // MARK: - nsColor

    @Test func nsColorNormal() {
        #expect(StatusBarRenderer.nsColor(for: .normal) == .labelColor)
    }

    @Test func nsColorWarning() {
        #expect(StatusBarRenderer.nsColor(for: .warning) == .systemOrange)
    }

    @Test func nsColorCritical() {
        #expect(StatusBarRenderer.nsColor(for: .critical) == .systemRed)
    }

    // MARK: - noCredentialsTitle

    @Test func noCredentialsTitleContent() {
        let title = StatusBarRenderer.noCredentialsTitle()
        #expect(title.string == "-%")
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .secondaryLabelColor)
    }

    // MARK: - loadingTitle

    @Test func loadingTitleContent() {
        let title = StatusBarRenderer.loadingTitle()
        #expect(title.string == "…")
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .secondaryLabelColor)
    }

    // MARK: - blockedTitle

    @Test func blockedTitleContainsCountdown() {
        let now = Date()
        let blockedUntil = now.addingTimeInterval(3600)
        let title = StatusBarRenderer.blockedTitle(blockedUntil: blockedUntil, now: now)
        let countdown = Formatting.timeUntil(blockedUntil, now: now)
        #expect(title.string.contains(countdown))
    }

    @Test func blockedTitleUsesRedColor() {
        let now = Date()
        let blockedUntil = now.addingTimeInterval(3600)
        let title = StatusBarRenderer.blockedTitle(blockedUntil: blockedUntil, now: now)
        let fullString = title.string
        // Find the countdown text (skip any attachment characters)
        let countdownStart = fullString.firstIndex(where: { $0.isNumber || $0.isLetter }) ?? fullString.startIndex
        let idx = fullString.distance(from: fullString.startIndex, to: countdownStart)
        if idx < title.length {
            let color = title.attribute(.foregroundColor, at: idx, effectiveRange: nil) as? NSColor
            #expect(color == .systemRed)
        }
    }

    // MARK: - usageTitle

    @Test func usageTitleSingleWindow() {
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600)),
        ])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        #expect(title.string.contains("42%"))
    }

    @Test func usageTitleEmptyEntries() {
        let usage = UsageResponse(entries: [])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        #expect(title.string.isEmpty)
    }

    @Test func usageTitleMultipleWindowsWithOutpacing() {
        // Second window is outpacing → should appear with separator
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600)),
            .make(key: "seven_day", utilization: 65, resetsAt: Date().addingTimeInterval(604_800 * 0.4)),
        ])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        #expect(title.string.contains("42%"))
        #expect(title.string.contains("65%"))
        #expect(title.string.contains("|"))
    }

    @Test func usageTitleSecondWindowNotOutpacingIsHidden() {
        // Second window: 8% used, 90% time remaining (10% elapsed) → 8 ≤ 10, not outpacing
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600)),
            .make(key: "seven_day", utilization: 8, resetsAt: Date().addingTimeInterval(604_800 * 0.9)),
        ])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        #expect(title.string.contains("42%"))
        #expect(!title.string.contains("8%"))
    }

    @Test func usageTitleBoldWhenOutpacing() {
        // 60% used, 40% time remaining (60% elapsed) → bold (60 > 60% elapsed = outpacing)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 60, resetsAt: Date().addingTimeInterval(18000 * 0.4)),
        ])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        let font = title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let boldFont = StatusBarRenderer.boldFont
        #expect(font == boldFont)
    }

    @Test func usageTitleRegularWhenNotOutpacing() {
        // 10% used, 80% remaining (duration=18000) → elapsed=3600, rate=10/3600, projected=10+(10/3600)*14400=50 → normal, not bold
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 10, resetsAt: Date().addingTimeInterval(18000 * 0.8)),
        ])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        let font = title.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        let regularFont = StatusBarRenderer.regularFont
        #expect(font == regularFont)
    }

    @Test func usageTitleCriticalUsesRedColor() {
        // 65% used, 50% remaining (duration=18000) → projected = 65+(65/9000)*9000 = 130 → critical → red
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 65, resetsAt: Date().addingTimeInterval(9000)),
        ])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .systemRed)
    }

    @Test func usageTitleWarningUsesOrangeColor() {
        // 55% used, 50% remaining (duration=18000) → projected = 55+(55/9000)*9000 = 110 → warning → orange
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 55, resetsAt: Date().addingTimeInterval(9000)),
        ])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .systemOrange)
    }

    @Test func usageTitleNormalUsesLabelColor() {
        // 20% utilization → normal
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 20, resetsAt: Date().addingTimeInterval(18000 * 0.8)),
        ])
        let title = StatusBarRenderer.usageTitle(usage: usage)
        let color = title.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(color == .labelColor)
    }
}
