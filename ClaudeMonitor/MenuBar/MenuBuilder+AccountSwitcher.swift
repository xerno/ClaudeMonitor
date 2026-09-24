import AppKit

extension MenuBuilder {
    static let switcherNameMaxLength = 14
    private static let minimumSwitcherProfileCount = 2

    static func accountSwitcher(state: MonitorState, target: any MenuActions) -> HeaderAccountSwitcher? {
        let profiles = state.profiles.profiles
        guard profiles.count >= minimumSwitcherProfileCount else { return nil }
        return HeaderAccountSwitcher(
            segments: profiles.map {
                AccountSegment(id: $0.id, label: truncatedSwitcherName($0.name), toolTip: $0.name)
            },
            activeIndex: profiles.firstIndex { $0.id == state.profiles.activeId } ?? 0,
            onSelect: { [weak target] id in target?.didSelectProfile(id: id) }
        )
    }

    static func findAccountToggle(in view: NSView?) -> AccountToggleView? {
        guard let view else { return nil }
        if let toggle = view as? AccountToggleView { return toggle }
        for subview in view.subviews {
            if let toggle = findAccountToggle(in: subview) { return toggle }
        }
        return nil
    }

    private static func truncatedSwitcherName(_ name: String) -> String {
        name.count > switcherNameMaxLength
            ? String(name.prefix(switcherNameMaxLength - 1)).trimmingCharacters(in: .whitespaces) + Constants.Menu.ellipsis
            : name
    }
}
