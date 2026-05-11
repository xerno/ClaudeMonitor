import AppKit

struct ColorTheme {
    let label: NSColor
    let orange: NSColor
    let red: NSColor
}

@MainActor
enum StatusBarRenderer {
    static let iconPointSize: CGFloat = 14

    static let regularFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    static let boldFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)

    static func updateText(
        button: NSStatusBarButton,
        usage: UsageResponse?,
        hasCredentials: Bool,
        isStale: Bool,
        windowAnalyses: [WindowAnalysis] = []
    ) {
        if !hasCredentials {
            button.attributedTitle = noCredentialsTitle()
            return
        }
        guard let usage else {
            button.attributedTitle = loadingTitle()
            return
        }
        if let blockedUntil = Formatting.blockingLimit(usage) {
            button.attributedTitle = blockedTitle(blockedUntil: blockedUntil)
            return
        }
        button.attributedTitle = usageTitle(usage: usage, windowAnalyses: windowAnalyses, isStale: isStale)
    }
}

extension StatusBarRenderer {
    static func nsColor(for level: Formatting.UsageLevel) -> NSColor {
        switch level {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }
}
