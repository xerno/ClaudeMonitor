import AppKit

extension StatusBarRenderer {
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
        let theme = ColorTheme(
            label: isStale ? NSColor.labelColor.desaturatedForStale() : NSColor.labelColor,
            orange: isStale ? NSColor.systemOrange.desaturatedForStale() : NSColor.systemOrange,
            red: isStale ? NSColor.systemRed.desaturatedForStale() : NSColor.systemRed
        )
        let separatorColor = isStale ? NSColor.secondaryLabelColor.desaturatedForStale() : NSColor.secondaryLabelColor

        if isStale {
            parts.append(NSAttributedString(string: "! ", attributes: [
                .foregroundColor: theme.label,
                .font: boldFont,
            ]))
        }

        guard let first = usage.entries.first else { return NSAttributedString() }

        appendWindow(first.window, duration: first.duration, key: first.storageIdentity,
                     analysisByKey: analysisByKey,
                     theme: theme,
                     into: parts)

        let rest = usage.entries.dropFirst()
        let visible = secondaryWindowKeys(from: rest, analysisByKey: analysisByKey)
        for entry in rest where visible.contains(entry.storageIdentity) {
            parts.append(NSAttributedString(string: " | ", attributes: [
                .foregroundColor: separatorColor, .font: regularFont,
            ]))
            appendWindow(entry.window, duration: entry.duration, key: entry.storageIdentity,
                         analysisByKey: analysisByKey,
                         theme: theme,
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

    static func appendWindow(
        _ window: UsageWindow,
        duration: TimeInterval,
        key: String,
        analysisByKey: [String: WindowAnalysis],
        theme: ColorTheme,
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
        case .normal: color = theme.label
        case .warning: color = theme.orange
        case .critical: color = theme.red
        }
        parts.append(NSAttributedString(string: "\(window.utilization)%", attributes: [
            .foregroundColor: color,
            .font: style.isBold ? boldFont : regularFont,
        ]))
    }
}
