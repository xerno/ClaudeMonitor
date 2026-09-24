import AppKit

@MainActor
final class FooterIconButton: NSView {
    private let imageView = NSImageView()
    private let closesMenu: Bool
    private let onClick: () -> Void
    private var trackingArea: NSTrackingArea?

    init(symbol: String, help: String, closesMenu: Bool, onClick: @escaping () -> Void) {
        self.closesMenu = closesMenu
        self.onClick = onClick
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        imageView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: help)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        toolTip = help
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(help)
        resetHover()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override var intrinsicContentSize: NSSize { Constants.Menu.footerButtonSize }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    func resetHover() {
        imageView.contentTintColor = .secondaryLabelColor
    }

    override func mouseEntered(with event: NSEvent) { imageView.contentTintColor = .labelColor }
    override func mouseExited(with event: NSEvent) { resetHover() }
    override func mouseUp(with event: NSEvent) { performClick() }

    override func accessibilityPerformPress() -> Bool {
        performClick()
        return true
    }

    private func performClick() {
        guard closesMenu else {
            onClick()
            return
        }
        enclosingMenuItem?.menu?.cancelTracking()
        Task { [weak self] in self?.onClick() }
    }
}
