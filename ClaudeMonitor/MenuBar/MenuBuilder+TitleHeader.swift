import AppKit

/// The pill on the right of the dropdown's title block: a coloured dot and a short status phrase.
/// Absent when there is nothing to report — its mere presence is the signal, which saves inventing
/// and translating a neutral resting phrase.
struct HeaderBadge {
    let text: String
    let dotColor: NSColor
}

extension MenuBuilder {
    private static let titleHeaderHeight: CGFloat = 34
    private static let titleGlyphSize: CGFloat = 20
    private static let titleGlyphGap: CGFloat = 8
    /// Gap kept between the switcher and whatever sits to its left.
    private static let titleToggleClearance: CGFloat = 16

    private static let badgeHeight: CGFloat = 20
    private static let badgeInset: CGFloat = 9
    private static let badgeDotSize: CGFloat = 7
    private static let badgeDotGap: CGFloat = 6
    private static let badgeLabelIdentifier = NSUserInterfaceItemIdentifier("titleHeaderBadge")

    static let titleFont = NSFont.systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)

    /// The dropdown's top row: the mark, the app name, the account switcher, and the status badge.
    /// Replaces the old grey "Usage … Claude Monitor" line — the section word is gone, the usage
    /// rows sit directly under the title.
    static func makeTitleHeaderView(
        title: String,
        badge: HeaderBadge? = nil,
        switcher: HeaderAccountSwitcher? = nil
    ) -> NSView {
        let glyph = makeGlyphView()
        let label = makeTitleLabel(title)
        let badgeView = badge.map(makeBadgeView)
        let toggle = switcher.map(makeTitleToggle)
        let width = titleHeaderMinWidth(label: label, badge: badgeView, toggle: toggle)
        return assembleTitleHeader(width: width, glyph: glyph, label: label, badge: badgeView, toggle: toggle)
    }

    private static func makeGlyphView() -> NSImageView {
        let view = NSImageView(image: ClaudeGlyph.image(size: titleGlyphSize))
        view.frame.size = NSSize(width: titleGlyphSize, height: titleGlyphSize)
        return view
    }

    private static func makeTitleLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = titleFont
        label.textColor = .labelColor
        label.sizeToFit()
        return label
    }

    private static func makeTitleToggle(_ switcher: HeaderAccountSwitcher) -> AccountToggleView {
        let control = AccountToggleView(frame: .zero)
        control.configure(with: switcher)
        control.autoresizingMask = [.minXMargin, .maxXMargin]
        return control
    }

    private static func titleHeaderMinWidth(
        label: NSTextField, badge: NSView?, toggle: AccountToggleView?
    ) -> CGFloat {
        let toggleWidth = toggle.map { $0.fittingSize.width + titleToggleClearance } ?? 0
        let badgeWidth = badge.map { $0.frame.width + titleToggleClearance } ?? 0
        return rowTrailingInset + titleGlyphSize + titleGlyphGap + label.frame.width
            + titleToggleClearance + badgeWidth + toggleWidth + rowTrailingInset
    }

    private static func assembleTitleHeader(
        width: CGFloat, glyph: NSImageView, label: NSTextField, badge: NSView?, toggle: AccountToggleView?
    ) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: titleHeaderHeight))
        view.autoresizingMask = .width

        glyph.frame.origin = NSPoint(x: rowTrailingInset, y: titleCentredY(titleGlyphSize))
        label.frame.origin = NSPoint(
            x: rowTrailingInset + titleGlyphSize + titleGlyphGap,
            y: titleCentredY(label.frame.height)
        )
        view.addSubview(glyph)
        view.addSubview(label)
        addTrailingCluster(to: view, width: width, badge: badge, toggle: toggle)
        return view
    }

    /// Lays out the right-hand side, right to left: the switcher owns the trailing edge and the
    /// badge tucks in beside it. Both stay pinned to that edge as the menu widens.
    private static func addTrailingCluster(
        to view: NSView, width: CGFloat, badge: NSView?, toggle: AccountToggleView?
    ) {
        var trailing = width - rowTrailingInset
        if let toggle {
            let size = toggle.fittingSize
            toggle.frame = NSRect(
                x: trailing - size.width, y: titleCentredY(size.height),
                width: size.width, height: size.height
            )
            toggle.autoresizingMask = .minXMargin
            view.addSubview(toggle)
            trailing -= size.width + titleToggleClearance
        }
        guard let badge else { return }
        badge.frame.origin = NSPoint(x: trailing - badge.frame.width, y: titleCentredY(badgeHeight))
        badge.autoresizingMask = .minXMargin
        view.addSubview(badge)
    }

    static func titleHeaderBadgeText(in view: NSView?) -> String? {
        guard let view else { return nil }
        if view.identifier == badgeLabelIdentifier, let label = view as? NSTextField {
            return label.stringValue
        }
        return view.subviews.lazy.compactMap { titleHeaderBadgeText(in: $0) }.first
    }

    private static func titleCentredY(_ height: CGFloat) -> CGFloat {
        ((titleHeaderHeight - height) / 2).rounded()
    }

    // MARK: - Badge

    private static func makeBadgeView(_ badge: HeaderBadge) -> NSView {
        let label = NSTextField(labelWithString: badge.text)
        label.identifier = badgeLabelIdentifier
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.sizeToFit()

        let width = badgeInset * 2 + badgeDotSize + badgeDotGap + label.frame.width
        let view = badgeContainer(width: width)
        view.addSubview(badgeDot(badge.dotColor))
        label.frame.origin = NSPoint(
            x: badgeInset + badgeDotSize + badgeDotGap,
            y: ((badgeHeight - label.frame.height) / 2).rounded()
        )
        view.addSubview(label)
        return view
    }

    private static func badgeContainer(width: CGFloat) -> NSView {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: badgeHeight))
        view.wantsLayer = true
        view.layer?.cornerRadius = badgeHeight / 2
        view.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor
        return view
    }

    private static func badgeDot(_ color: NSColor) -> NSView {
        let dot = NSView(frame: NSRect(
            x: badgeInset, y: ((badgeHeight - badgeDotSize) / 2).rounded(),
            width: badgeDotSize, height: badgeDotSize
        ))
        dot.wantsLayer = true
        dot.layer?.cornerRadius = badgeDotSize / 2
        dot.layer?.backgroundColor = color.cgColor
        return dot
    }
}

extension MenuBuilder {
    /// The app's own name, shown as the dropdown's title. Deliberately not localized — it is the
    /// product name, same as in the About and Preferences window titles.
    static let appTitle = Constants.Menu.appTitle

    /// "All systems operational" — its own green is the whole signal, no dot beside it.
    static var servicesOperationalSubtitle: String {
        String(localized: "services.all_operational", bundle: .module)
    }

    /// The dropdown's top row. Replaces the old "Usage" section header: the reference design drops
    /// the section word and puts the usage rows straight under the title.
    static func usageHeaderItem(state: MonitorState, target: any MenuActions) -> NSMenuItem {
        let item = NSMenuItem(title: appTitle, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = usageSectionTag
        item.view = makeTitleHeaderView(
            title: appTitle,
            badge: usageBadge(state: state),
            switcher: accountSwitcher(state: state, target: target)
        )
        return item
    }

    /// The status badge, or `nil` while nothing is blocked. No time in it on purpose — the row
    /// right below already carries "resets in …", and the badge is only redrawn on a poll, so a
    /// countdown here would sit up to five minutes stale.
    static func usageBadge(state: MonitorState) -> HeaderBadge? {
        guard Formatting.blockingLimit(state.usage.currentUsage) != nil else { return nil }
        return HeaderBadge(
            text: String(localized: "menu.badge.rate_limited", bundle: .module),
            dotColor: .systemRed
        )
    }
}
