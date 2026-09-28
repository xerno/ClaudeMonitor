import AppKit

/// The "Updated / Interval / Next" line under the Services section.
///
/// Separate labels rather than one space-padded string: padding lines up at only one menu width,
/// and the menu is as wide as its widest item.
final class ControlRowView: NSView {
    private static let edgePadding: CGFloat = MenuBuilder.rowTrailingInset
    private static let rowHeight: CGFloat = 22
    private static let minimumGap: CGFloat = 12

    /// Monospaced digits: clock times change on every refresh, and proportional digits would shift the columns.
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: NSFont.menuFont(ofSize: 0).pointSize, weight: .regular
    )

    private var labels: [NSTextField] = []

    /// Lets reconciliation copy a rebuilt row's readings without going through the joined title.
    var segments: [String] { labels.map(\.stringValue) }

    convenience init(title: String) {
        self.init(segments: [title])
    }

    init(segments: [String]) {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: Self.rowHeight))
        autoresizingMask = .width
        setSegments(segments)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Contents

    func updateTitle(_ title: String) {
        update(segments: [title])
    }

    func update(segments: [String]) {
        guard segments.count == labels.count else {
            setSegments(segments)
            return
        }
        for (label, text) in zip(labels, segments) {
            label.stringValue = text
        }
        resizeToFit()
        needsLayout = true
    }

    private func setSegments(_ segments: [String]) {
        labels.forEach { $0.removeFromSuperview() }
        labels = segments.map(Self.makeLabel)
        // Direct subviews, no stack view: tests look for the labels among `subviews`.
        labels.forEach(addSubview)
        resizeToFit()
        needsLayout = true
    }

    private static func makeLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.textColor = .secondaryLabelColor
        return label
    }

    /// Sets the row's minimum width from its content, so the menu fits the longest translation.
    private func resizeToFit() {
        let content = widths().reduce(0, +) + Self.minimumGap * CGFloat(max(labels.count - 1, 0))
        frame.size.width = max(frame.width, Self.edgePadding * 2 + content)
    }

    private func widths() -> [CGFloat] {
        labels.map { $0.fittingSize.width.rounded(.up) }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        let widths = widths()
        for (label, width) in zip(labels, widths) {
            let height = label.fittingSize.height
            label.frame = NSRect(x: 0, y: (Self.rowHeight - height) / 2, width: width, height: height)
        }
        positionLabels(widths: widths)
    }

    private func positionLabels(widths: [CGFloat]) {
        guard let first = labels.first else { return }
        first.frame.origin.x = Self.edgePadding
        guard labels.count > 1 else { return }

        let trailing = labels[labels.count - 1]
        trailing.frame.origin.x = bounds.width - Self.edgePadding - widths[widths.count - 1]
        guard labels.count == 3 else { return }

        labels[1].frame.origin.x = centredMiddleX(widths: widths)
    }

    private func centredMiddleX(widths: [CGFloat]) -> CGFloat {
        let centred = (bounds.width - widths[1]) / 2
        let leftEdge = Self.edgePadding + widths[0] + Self.minimumGap
        let rightEdge = bounds.width - Self.edgePadding - widths[2] - Self.minimumGap - widths[1]
        guard leftEdge <= rightEdge else {
            let free = bounds.width - Self.edgePadding * 2 - widths.reduce(0, +)
            return Self.edgePadding + widths[0] + free / 2
        }
        return min(max(centred, leftEdge), rightEdge)
    }
}
