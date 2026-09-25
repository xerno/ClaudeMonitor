import AppKit

extension MenuBuilder {
    /// Horizontal inset the dropdown's rows line up on — the header labels, the control row and the
    /// stats row all use it, so a row that picks its own number visibly steps out of the column.
    static let rowTrailingInset: CGFloat = Constants.Menu.edgePadding

    static let maxDisplayLength = 40
    static let truncatedPrefixLength = 30

    /// Both header labels share one shade — the section word ("Usage", "Services") and the trailing
    /// text ("Claude Monitor", "All systems operational") read as a single row. They used to sit on
    /// `disabledControlTextColor` and `tertiaryLabelColor`, which rendered them near-invisible and
    /// mismatched against each other.
    static let headerTextColor = NSColor.secondaryLabelColor

    private static let headerHeight: CGFloat = 22

    static func makeHeaderView(
        title: String,
        subtitle: String,
        subtitleColor: NSColor = headerTextColor
    ) -> NSView {
        let left = headerLabel(title)
        let right = headerLabel(subtitle, color: subtitleColor)
        right.autoresizingMask = .minXMargin
        return assembleHeader(width: headerMinWidth(left: left, right: right), left: left, right: right)
    }

    static func sectionHeader(
        _ title: String,
        subtitle: String? = nil,
        subtitleColor: NSColor = headerTextColor,
        tag: Int
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag
        if let subtitle {
            item.view = makeHeaderView(title: title, subtitle: subtitle, subtitleColor: subtitleColor)
        }
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

    private static func headerLabel(_ text: String, color: NSColor = headerTextColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.menuFont(ofSize: 0)
        label.textColor = color
        label.sizeToFit()
        return label
    }

    /// The width at which both labels still clear each other. The real menu is usually wider, and
    /// the trailing label stays pinned to the right edge of whatever width it gets.
    private static func headerMinWidth(left: NSTextField, right: NSTextField) -> CGFloat {
        rowTrailingInset + left.frame.width + Constants.Menu.headerElementSpacing
            + right.frame.width + rowTrailingInset
    }

    private static func assembleHeader(
        width: CGFloat, left: NSTextField, right: NSTextField
    ) -> NSView {
        left.frame.origin = NSPoint(x: rowTrailingInset, y: centeredY(forHeight: left.frame.height))
        right.frame.origin = NSPoint(
            x: width - rowTrailingInset - right.frame.width,
            y: centeredY(forHeight: right.frame.height)
        )

        let view = NSView(frame: NSRect(x: 0, y: 0, width: width, height: headerHeight))
        view.autoresizingMask = .width
        view.addSubview(left)
        view.addSubview(right)
        return view
    }

    private static func centeredY(forHeight height: CGFloat) -> CGFloat {
        (headerHeight - height) / 2
    }
}
