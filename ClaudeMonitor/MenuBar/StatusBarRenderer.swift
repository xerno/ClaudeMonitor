import AppKit

@MainActor
enum StatusBarRenderer {
    private static let iconPointSize: CGFloat = 14

    static let regularFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
    static let boldFont = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .bold)

    private static let blockedOctagon: NSImage? = {
        guard let symbol = NSImage(systemSymbolName: "octagon.fill", accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: NSFont.systemFontSize, weight: .medium)
            .applying(.init(paletteColors: [.systemRed]))
        guard let configured = symbol.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false
        return configured
    }()

    static func resolveIcon(
        status: StatusSummary?,
        hasRefreshWarning: Bool
    ) -> (symbolName: String, color: NSColor) {
        if hasRefreshWarning {
            return ("exclamationmark.triangle.fill", .systemYellow)
        }

        guard let worst = status?.components.map(\.status).max() else {
            return ("checkmark.circle.fill", .systemGreen)
        }

        switch worst {
        case .majorOutage:
            return ("xmark.circle.fill", .systemRed)
        case .partialOutage:
            return ("exclamationmark.circle.fill", .systemOrange)
        case .degradedPerformance:
            return ("exclamationmark.circle.fill", .systemYellow)
        case .underMaintenance:
            return ("wrench.and.screwdriver.fill", .systemBlue)
        case .operational, .unknown:
            return ("checkmark.circle.fill", .systemGreen)
        }
    }

    static func updateIcon(
        button: NSStatusBarButton,
        status: StatusSummary?,
        hasRefreshWarning: Bool
    ) {
        let icon = resolveIcon(status: status, hasRefreshWarning: hasRefreshWarning)
        button.image = makeImage(symbolName: icon.symbolName, color: icon.color)
    }

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

    static func noCredentialsTitle() -> NSAttributedString {
        NSAttributedString(string: "-%", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: regularFont,
        ])
    }

    static func loadingTitle() -> NSAttributedString {
        NSAttributedString(string: "…", attributes: [
            .foregroundColor: NSColor.secondaryLabelColor, .font: regularFont,
        ])
    }

    static func blockedTitle(blockedUntil: Date, now: Date = Date()) -> NSAttributedString {
        let countdown = Formatting.timeUntil(blockedUntil, now: now)
        let result = NSMutableAttributedString()
        if let octagon = blockedOctagon {
            let attachment = NSTextAttachment()
            attachment.image = octagon
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " ", attributes: [.font: regularFont]))
        }
        result.append(NSAttributedString(string: countdown, attributes: [
            .foregroundColor: NSColor.systemRed,
            .font: regularFont,
        ]))
        result.append(NSAttributedString(string: " ", attributes: [.font: regularFont]))
        return result
    }

    static func usageTitle(usage: UsageResponse, windowAnalyses: [WindowAnalysis] = [], isStale: Bool = false) -> NSAttributedString {
        let parts = NSMutableAttributedString()
        let analysisByKey = Dictionary(uniqueKeysWithValues: windowAnalyses.map { ($0.entry.storageIdentity, $0) })

        // Pre-compute desaturated variants once when stale to avoid repeated HSL conversion per window.
        let labelColor = isStale ? NSColor.labelColor.desaturatedForStale() : NSColor.labelColor
        let orangeColor = isStale ? NSColor.systemOrange.desaturatedForStale() : NSColor.systemOrange
        let redColor = isStale ? NSColor.systemRed.desaturatedForStale() : NSColor.systemRed
        let separatorColor = isStale ? NSColor.secondaryLabelColor.desaturatedForStale() : NSColor.secondaryLabelColor

        if isStale {
            parts.append(NSAttributedString(string: "! ", attributes: [
                .foregroundColor: labelColor,
                .font: boldFont,
            ]))
        }

        guard let first = usage.entries.first else { return NSAttributedString() }

        appendWindow(first.window, duration: first.duration, key: first.storageIdentity,
                     analysisByKey: analysisByKey,
                     labelColor: labelColor, orangeColor: orangeColor, redColor: redColor,
                     into: parts)

        let rest = usage.entries.dropFirst()
        let visible = secondaryWindowKeys(from: rest, analysisByKey: analysisByKey)
        for entry in rest where visible.contains(entry.storageIdentity) {
            parts.append(NSAttributedString(string: " | ", attributes: [
                .foregroundColor: separatorColor, .font: regularFont,
            ]))
            appendWindow(entry.window, duration: entry.duration, key: entry.storageIdentity,
                         analysisByKey: analysisByKey,
                         labelColor: labelColor, orangeColor: orangeColor, redColor: redColor,
                         into: parts)
        }

        return parts
    }

    static func secondaryWindowKeys(
        from entries: some Collection<WindowEntry>,
        analysisByKey: [String: WindowAnalysis] = [:]
    ) -> Set<String> {
        var keys = Set<String>()
        for entry in entries {
            let shouldShow: Bool
            if let analysis = analysisByKey[entry.storageIdentity] {
                shouldShow = Formatting.shouldShowInMenuBar(projectedAtReset: analysis.projectedAtReset)
            } else {
                // Fallback for usageTitle's default windowAnalyses: [] (tests, previews). Production callers always provide populated analyses.
                shouldShow = Formatting.shouldShowInMenuBar(
                    utilization: entry.window.utilization,
                    resetsAt: entry.window.resetsAt,
                    windowDuration: entry.duration
                )
            }
            guard shouldShow else { continue }
            keys.insert(entry.storageIdentity)
            if entry.modelScope != nil,
               let allModels = entries.first(where: { $0.durationLabel == entry.durationLabel && $0.modelScope == nil }) {
                keys.insert(allModels.storageIdentity)
            }
        }
        return keys
    }

    private static func appendWindow(
        _ window: UsageWindow,
        duration: TimeInterval,
        key: String,
        analysisByKey: [String: WindowAnalysis],
        labelColor: NSColor,
        orangeColor: NSColor,
        redColor: NSColor,
        into parts: NSMutableAttributedString
    ) {
        let style: Formatting.UsageStyle
        if let analysis = analysisByKey[key] {
            style = analysis.style
        } else {
            // Fallback for usageTitle's default windowAnalyses: [] (tests, previews). Production callers always provide populated analyses.
            style = Formatting.usageStyle(
                utilization: window.utilization,
                resetsAt: window.resetsAt,
                windowDuration: duration
            )
        }
        let color: NSColor
        switch style.level {
        case .normal: color = labelColor
        case .warning: color = orangeColor
        case .critical: color = redColor
        }
        parts.append(NSAttributedString(string: "\(window.utilization)%", attributes: [
            .foregroundColor: color,
            .font: style.isBold ? boldFont : regularFont,
        ]))
    }

    static func nsColor(for level: Formatting.UsageLevel) -> NSColor {
        switch level {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }

    static func makeImage(symbolName: String, color: NSColor) -> NSImage? {
        guard let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: iconPointSize, weight: .medium)
            .applying(.init(paletteColors: [color]))
        guard let configured = symbol.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false

        let verticalOffset: CGFloat = 2.0
        let horizontalTrim: CGFloat = 0.5
        let newSize = NSSize(width: configured.size.width - horizontalTrim * 2,
                             height: configured.size.height + verticalOffset)
        let shifted = NSImage(size: newSize, flipped: false) { rect in
            configured.draw(in: NSRect(x: -horizontalTrim, y: verticalOffset,
                                       width: configured.size.width,
                                       height: configured.size.height))
            return true
        }
        shifted.isTemplate = false
        return shifted
    }
}
