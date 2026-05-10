import AppKit

final class ControlRowView: NSView {
    private let label: NSTextField

    init(title: String) {
        let font = NSFont.menuFont(ofSize: 0)
        label = NSTextField(labelWithString: title)
        label.font = font
        label.textColor = .secondaryLabelColor
        let edgePadding: CGFloat = 14
        let textWidth = NSAttributedString(string: title, attributes: [.font: font]).size().width
        let minWidth = edgePadding + textWidth + edgePadding
        let height: CGFloat = 22
        super.init(frame: NSRect(x: 0, y: 0, width: minWidth, height: height))
        autoresizingMask = .width
        label.frame = NSRect(x: edgePadding, y: (height - label.intrinsicContentSize.height) / 2,
                             width: frame.width - edgePadding * 2, height: label.intrinsicContentSize.height)
        label.autoresizingMask = .width
        addSubview(label)
    }

    required init?(coder: NSCoder) { fatalError() }

    func updateTitle(_ title: String) {
        label.stringValue = title
        needsDisplay = true
    }
}
