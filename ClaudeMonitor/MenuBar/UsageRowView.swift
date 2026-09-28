import AppKit

// MARK: - UsageRowView

/// A menu item with a custom `.view` does not auto-close the menu on click.
final class UsageRowView: NSView {
    private let textField: NSTextField
    var onClick: (() -> Void)?
    /// Written only by `MenuBuilder.syncHighlight` from `menu(_:willHighlight:)`. No tracking area of
    /// its own: AppKit sends no `mouseExited` when the menu closes under the cursor or the row is
    /// clicked, so the flag sticks (rows are reused), and `NSMenuItem.isHighlighted` is not KVO-compliant.
    var isHighlighted = false {
        didSet {
            guard oldValue != isHighlighted else { return }
            needsDisplay = true
        }
    }
    var isSelected = false {
        didSet { needsDisplay = true }
    }

    private static let selectionBarWidth: CGFloat = 3
    private static let leftPadding: CGFloat = 17  // standard menu item left margin
    private static let rightPadding: CGFloat = 14
    private static let verticalPadding: CGFloat = 3

    private static func requiredWidth(for attributedTitle: NSAttributedString) -> CGFloat {
        attributedTitle.size().width + leftPadding + rightPadding + selectionBarWidth
    }

    init(attributedTitle: NSAttributedString) {
        textField = NSTextField(labelWithAttributedString: attributedTitle)
        textField.isSelectable = false
        let textSize = attributedTitle.size()
        let height = textSize.height + UsageRowView.verticalPadding * 2
        let width = UsageRowView.requiredWidth(for: attributedTitle)
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: height))
        textField.frame = NSRect(
            x: UsageRowView.leftPadding + UsageRowView.selectionBarWidth,
            y: UsageRowView.verticalPadding,
            width: textSize.width + UsageRowView.rightPadding,
            height: textSize.height
        )
        autoresizingMask = .width
        addSubview(textField)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

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

    /// Grow-only: the menu stretches the row to full width on layout, and the width reserved for the
    /// widest countdown must survive live updates.
    func ensureFrameWidth(for attributedTitle: NSAttributedString) {
        let needed = UsageRowView.requiredWidth(for: attributedTitle)
        guard needed > frame.size.width else { return }
        textField.frame.size.width += needed - frame.size.width
        frame.size.width = needed
    }

    func updateTitle(_ attributedTitle: NSAttributedString) {
        textField.attributedStringValue = attributedTitle
        textField.frame.size.width = attributedTitle.size().width + UsageRowView.rightPadding
        ensureFrameWidth(for: attributedTitle)
    }

    var currentAttributedTitle: NSAttributedString { textField.attributedStringValue }

    /// For tests.
    var textContent: String { textField.attributedStringValue.string }

    override func draw(_ dirtyRect: NSRect) {
        if isHighlighted {
            NSColor.selectedContentBackgroundColor.withAlphaComponent(0.15).setFill()
            bounds.fill()
        }
        if isSelected {
            NSColor.controlAccentColor.setFill()
            NSRect(x: UsageRowView.leftPadding, y: 0,
                   width: UsageRowView.selectionBarWidth, height: bounds.height).fill()
        }
    }
}
