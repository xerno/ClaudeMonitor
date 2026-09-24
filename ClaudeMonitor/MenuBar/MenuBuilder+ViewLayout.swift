import AppKit

extension MenuBuilder {
    static let maxDisplayLength = 40
    static let truncatedPrefixLength = 30
    private static let headerSubtitleIdentifier = NSUserInterfaceItemIdentifier("headerSubtitle")

    static func makeHeaderView(title: String, subtitle: String?, switcher: HeaderAccountSwitcher? = nil) -> NSView {
        let font = NSFont.menuFont(ofSize: 0)
        let height: CGFloat = 22
        let edgePadding = Constants.Menu.edgePadding
        let spacing = Constants.Menu.headerElementSpacing

        let leftLabel = NSTextField(labelWithString: title)
        leftLabel.font = font
        leftLabel.textColor = .disabledControlTextColor
        leftLabel.sizeToFit()
        leftLabel.frame.origin = NSPoint(x: edgePadding, y: (height - leftLabel.frame.height) / 2)

        let rightLabel = subtitle.map { makeHeaderSubtitleLabel($0, font: font) }
        let rightLabelWidth = rightLabel?.frame.width ?? 0

        var toggle: AccountToggleView?
        var toggleSize = NSSize.zero
        if let switcher {
            let control = AccountToggleView(frame: .zero)
            control.configure(with: switcher)
            toggleSize = control.fittingSize
            control.autoresizingMask = [.minXMargin, .maxXMargin]
            toggle = control
        }

        let toggleReserve = toggleSize.width > 0 ? toggleSize.width + spacing : 0
        let minWidth = edgePadding + leftLabel.frame.width + spacing + toggleReserve + rightLabelWidth + edgePadding

        let view = NSView(frame: NSRect(x: 0, y: 0, width: minWidth, height: height))
        view.autoresizingMask = .width
        view.addSubview(leftLabel)
        if let rightLabel {
            rightLabel.frame.origin = NSPoint(
                x: minWidth - edgePadding - rightLabelWidth,
                y: (height - rightLabel.frame.height) / 2
            )
            view.addSubview(rightLabel)
        }
        if let toggle {
            toggle.frame = NSRect(
                x: (minWidth - toggleSize.width) / 2,
                y: (height - toggleSize.height) / 2,
                width: toggleSize.width,
                height: toggleSize.height
            )
            view.addSubview(toggle)
        }
        return view
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

    private static func makeHeaderSubtitleLabel(_ subtitle: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: subtitle)
        label.identifier = headerSubtitleIdentifier
        label.font = font
        label.textColor = .tertiaryLabelColor
        label.sizeToFit()
        label.autoresizingMask = .minXMargin
        return label
    }
}
