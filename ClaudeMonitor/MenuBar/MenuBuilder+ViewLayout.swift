import AppKit

extension MenuBuilder {
    static let maxDisplayLength = 40
    static let truncatedPrefixLength = 30

    static func makeHeaderView(title: String, subtitle: String) -> NSView {
        let font = NSFont.menuFont(ofSize: 0)
        let height: CGFloat = 22
        let edgePadding: CGFloat = 14

        let leftLabel = NSTextField(labelWithString: title)
        leftLabel.font = font
        leftLabel.textColor = .disabledControlTextColor
        leftLabel.sizeToFit()
        leftLabel.frame.origin = NSPoint(x: edgePadding, y: (height - leftLabel.frame.height) / 2)

        let rightLabel = NSTextField(labelWithString: subtitle)
        rightLabel.font = font
        rightLabel.textColor = .tertiaryLabelColor
        rightLabel.sizeToFit()
        rightLabel.autoresizingMask = .minXMargin
        let minWidth = edgePadding + leftLabel.frame.width + 20 + rightLabel.frame.width + edgePadding
        rightLabel.frame.origin = NSPoint(
            x: minWidth - edgePadding - rightLabel.frame.width,
            y: (height - rightLabel.frame.height) / 2
        )

        let view = NSView(frame: NSRect(x: 0, y: 0, width: minWidth, height: height))
        view.autoresizingMask = .width
        view.addSubview(leftLabel)
        view.addSubview(rightLabel)
        return view
    }

    static func sectionHeader(_ title: String, subtitle: String? = nil, tag: Int) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.tag = tag
        if let subtitle {
            item.view = makeHeaderView(title: title, subtitle: subtitle)
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
        name.count > maxDisplayLength ? String(name.prefix(truncatedPrefixLength)).trimmingCharacters(in: .whitespaces) + "…" : name
    }
}
