import AppKit

extension MenuBuilder {
    static let maxDisplayLength = 40
    static let truncatedPrefixLength = 30
    private static let headerSubtitleIdentifier = NSUserInterfaceItemIdentifier("headerSubtitle")

    /// Both header labels share one shade — the section word ("Usage", "Services") and the trailing
    /// text ("Claude Monitor", "All systems operational") read as a single row. They used to sit on
    /// `disabledControlTextColor` and `tertiaryLabelColor`, which rendered them near-invisible and
    /// mismatched against each other.
    static let headerTextColor = NSColor.secondaryLabelColor

    private static let headerHeight: CGFloat = 22

    static func makeHeaderView(title: String, subtitle: String?, switcher: HeaderAccountSwitcher? = nil) -> NSView {
        let left = headerLabel(title)
        let right = subtitle.map { makeHeaderSubtitleLabel($0) }
        let toggle = switcher.map { makeAccountToggle($0) }
        let width = headerMinWidth(left: left, right: right, toggle: toggle)
        return assembleHeader(width: width, left: left, right: right, toggle: toggle)
    }

    static func headerSubtitle(in view: NSView?) -> String? {
        let label = view?.subviews.first { $0.identifier == headerSubtitleIdentifier } as? NSTextField
        return label?.stringValue
    }

    static func headerView(title: String, subtitle: String?, switcher: HeaderAccountSwitcher?) -> NSView? {
        guard subtitle != nil || switcher != nil else { return nil }
        return makeHeaderView(title: title, subtitle: subtitle, switcher: switcher)
    }

    static func sectionHeader(_ title: String, subtitle: String? = nil, tag: Int, switcher: HeaderAccountSwitcher? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag
        item.view = headerView(title: title, subtitle: subtitle, switcher: switcher)
        return item
    }

    static func staticItem(_ title: String, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag
        return item
    }

    static func separator(tag: Int) -> NSMenuItem {
        let item = NSMenuItem.separator()
        item.tag = tag
        return item
    }

    static func truncatedName(_ name: String) -> String {
        name.count > maxDisplayLength ? String(name.prefix(truncatedPrefixLength)).trimmingCharacters(in: .whitespaces) + Constants.Menu.ellipsis : name
    }

    private static func headerLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = headerTextColor
        label.sizeToFit()
        return label
    }

    private static func makeHeaderSubtitleLabel(_ subtitle: String) -> NSTextField {
        let label = headerLabel(subtitle)
        label.identifier = headerSubtitleIdentifier
        label.autoresizingMask = .minXMargin
        return label
    }

    private static func makeAccountToggle(_ switcher: HeaderAccountSwitcher) -> AccountToggleView {
        let control = AccountToggleView(frame: .zero)
        control.configure(with: switcher)
        control.autoresizingMask = [.minXMargin, .maxXMargin]
        return control
    }

    /// The width at which a centered toggle still clears both labels. The real menu is usually
    /// wider than this, and the toggle floats centered inside whatever width it gets.
    private static func headerMinWidth(
        left: NSTextField, right: NSTextField?, toggle: AccountToggleView?
    ) -> CGFloat {
        let spacing = Constants.Menu.headerElementSpacing
        let toggleWidth = toggle?.fittingSize.width ?? 0
        let reserve = toggleWidth > 0 ? toggleWidth + spacing : 0
        return Constants.Menu.edgePadding + left.frame.width + spacing
            + reserve + (right?.frame.width ?? 0) + Constants.Menu.edgePadding
    }

    private static func assembleHeader(
        width: CGFloat, left: NSTextField, right: NSTextField?, toggle: AccountToggleView?
    ) -> NSView {
        let edgePadding = Constants.Menu.edgePadding
        left.frame.origin = NSPoint(x: edgePadding, y: centeredY(forHeight: left.frame.height))

        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        view.autoresizingMask = .width
        view.addSubview(left)
        if let right {
            right.frame.origin = NSPoint(
                x: width - edgePadding - right.frame.width,
                y: centeredY(forHeight: right.frame.height)
            )
            view.addSubview(right)
        }

        if let toggle {
            let size = toggle.fittingSize
            toggle.frame = NSRect(
                x: (width - size.width) / 2, y: centeredY(forHeight: size.height),
                width: size.width, height: size.height
            )
            view.addSubview(toggle)
        }
        return view
    }

    private static func centeredY(forHeight height: CGFloat) -> CGFloat {
        (headerHeight - height) / 2
    }
}
