import AppKit

// MARK: - UsageRowView

/// A custom NSView used as an NSMenuItem's view for usage rows.
/// Because `.view` is set on the menu item, NSMenu does NOT auto-close on click.
final class UsageRowView: NSView {
    private let textField: NSTextField
    var onClick: (() -> Void)?
    private var isHighlighted = false
    var isSelected = false {
        didSet { needsDisplay = true }
    }
    private var menuItemObservation: NSKeyValueObservation?

    private static let selectionBarWidth: CGFloat = 3
    private static let leftPadding: CGFloat = 17  // standard menu item left margin
    private static let rightPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 3

    init(attributedTitle: NSAttributedString) {
        textField = NSTextField(labelWithAttributedString: attributedTitle)
        textField.isSelectable = false
        let textSize = attributedTitle.size()
        let height = textSize.height + UsageRowView.verticalPadding * 2
        let width = textSize.width + UsageRowView.leftPadding + UsageRowView.rightPadding + UsageRowView.selectionBarWidth
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textField.frame = NSRect(
            x: UsageRowView.leftPadding + UsageRowView.selectionBarWidth,
            y: UsageRowView.verticalPadding,
            width: textSize.width + UsageRowView.rightPadding,
            height: textSize.height
        )
        addSubview(textField)
        updateTrackingAreas()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        menuItemObservation = enclosingMenuItem?.observe(\.isHighlighted, options: []) { [weak self] _, _ in
            // AppKit fires KVO on the main thread; assumeIsolated avoids an unnecessary hop.
            MainActor.assumeIsolated { self?.needsDisplay = true }
        }
    }

    override func mouseEntered(with event: NSEvent) { isHighlighted = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { isHighlighted = false; needsDisplay = true }

    override var acceptsFirstResponder: Bool { true }

    override func mouseUp(with event: NSEvent) {
        onClick?()
    }

    override func keyDown(with event: NSEvent) {
        // Do NOT call cancelTracking() — mouse clicks don't close the menu either.
        if let chars = event.charactersIgnoringModifiers, chars == "\r" || chars == " " {
            onClick?()
        } else {
            super.keyDown(with: event)
        }
    }

    func ensureFrameWidth(for attributedTitle: NSAttributedString) {
        let needed = attributedTitle.size().width + UsageRowView.leftPadding + UsageRowView.rightPadding + UsageRowView.selectionBarWidth
        guard needed > frame.size.width else { return }
        let extra = needed - frame.size.width
        textField.frame.size.width += extra
        frame.size.width = needed
    }

    func updateTitle(_ attributedTitle: NSAttributedString) {
        textField.attributedStringValue = attributedTitle
        let textSize = attributedTitle.size()
        textField.frame.size.width = textSize.width + UsageRowView.rightPadding
        frame.size.width = textSize.width + UsageRowView.leftPadding + UsageRowView.rightPadding + UsageRowView.selectionBarWidth
    }

    /// Returns the current attributed title of the row.
    var currentAttributedTitle: NSAttributedString { textField.attributedStringValue }

    /// Returns the plain string content of the row (for testing).
    var textContent: String { textField.attributedStringValue.string }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted || enclosingMenuItem?.isHighlighted == true {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).setFill()
            dirtyRect.fill()
        }
        if isSelected {
            NSColor.controlAccentColor.setFill()
            NSRect(x: UsageRowView.leftPadding, y: 0,
                   width: UsageRowView.selectionBarWidth, height: bounds.height).fill()
        }
    }
}
