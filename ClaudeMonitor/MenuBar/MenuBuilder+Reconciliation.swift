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
                        existingControl.updateTitle(desiredItem.title)
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
