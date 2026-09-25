import AppKit

extension MenuBuilder {
    static func reconcile(menu: NSMenu, desired: [NSMenuItem]) {
        let desiredTags = Set(desired.map { $0.tag })

        for item in menu.items.reversed() {
            if !desiredTags.contains(item.tag) {
                menu.removeItem(item)
            }
        }

        for (index, desiredItem) in desired.enumerated() {
            if let existing = menu.item(withTag: desiredItem.tag) {
                if !existing.isSeparatorItem {
                    if existing.view == nil {
                        updateItem(existing, from: desiredItem)
                    } else if let existingRow = existing.view as? UsageRowView,
                              let desiredRow = desiredItem.view as? UsageRowView {
                        existingRow.updateTitle(desiredRow.currentAttributedTitle)
                    } else if let existingControl = existing.view as? ControlRowView {
                        if let desiredControl = desiredItem.view as? ControlRowView {
                            existingControl.update(segments: desiredControl.segments)
                        } else {
                            existingControl.updateTitle(desiredItem.title)
                        }
                    }
                }
                let currentIndex = menu.index(of: existing)
                if currentIndex != index {
                    menu.removeItem(existing)
                    menu.insertItem(existing, at: min(index, menu.numberOfItems))
                }
            } else {
                menu.insertItem(desiredItem, at: min(index, menu.numberOfItems))
            }
        }
    }

    static func updateItem(_ existing: NSMenuItem, from desired: NSMenuItem) {
        if let attr = desired.attributedTitle {
            existing.attributedTitle = attr
        } else if existing.title != desired.title {
            existing.title = desired.title
        }
        if let rep = desired.representedObject as? String {
            existing.representedObject = rep
        }
    }

    /// Pushes AppKit's highlight decision into the view-based usage rows: at most one row is
    /// highlighted, `nil` clears every row. Driven by `NSMenuDelegate.menu(_:willHighlight:)`,
    /// which reports mouse hover and keyboard navigation alike, and by `menuDidClose` — a closed
    /// menu has no highlighted row. See `UsageRowView.isHighlighted` for why the rows cannot
    /// track this themselves.
    static func syncHighlight(in menu: NSMenu, highlighted item: NSMenuItem?) {
        for menuItem in menu.items {
            (menuItem.view as? UsageRowView)?.isHighlighted = menuItem === item
        }
    }

    static func syncUsageCheckmarks(in menu: NSMenu, selectedIndex: Int) {
        for item in menu.items {
            let tag = item.tag
            guard tag >= usageBaseTag && tag < usagePlaceholderTag else { continue }
            let index = tag - usageBaseTag
            if let rowView = item.view as? UsageRowView {
                rowView.isSelected = index == selectedIndex
            } else {
                item.state = index == selectedIndex ? .on : .off
            }
        }
    }
}
