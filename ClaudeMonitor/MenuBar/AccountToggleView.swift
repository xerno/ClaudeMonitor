import AppKit

struct AccountSegment: Equatable, Sendable {
    let id: String
    let label: String
    let toolTip: String
}

@MainActor
struct HeaderAccountSwitcher {
    let segments: [AccountSegment]
    let activeIndex: Int
    let onSelect: (String) -> Void
}

/// Drawn, not an `NSSegmentedControl`: that paints the selected segment in the system accent with a
/// white label, and `selectedSegmentBezelColor` is ignored on `.automatic`.
@MainActor
enum AccountTogglePill {
    static let height: CGFloat = 18
    static let horizontalPadding: CGFloat = 9
    static var font: NSFont { NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)) }

    /// Same fill as the header badge.
    static var trackColor: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.18) }
    static var selectedFill: NSColor { ClaudeGlyph.color }
    /// Dark on coral is 5.5:1; white is 3.2:1.
    static var selectedText: NSColor { StatusBarRenderer.darkGlyph }
    static var unselectedText: NSColor { .secondaryLabelColor }

    static func segmentWidths(_ labels: [String]) -> [CGFloat] {
        labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width + horizontalPadding * 2 }
    }

    static func size(labels: [String]) -> NSSize {
        NSSize(width: segmentWidths(labels).reduce(0, +).rounded(.up), height: height)
    }

    static func segmentRects(labels: [String], in rect: NSRect) -> [NSRect] {
        var x = rect.minX
        return segmentWidths(labels).map { width in
            defer { x += width }
            return NSRect(x: x, y: rect.minY, width: width, height: rect.height)
        }
    }

    static func draw(labels: [String], selectedIndex: Int, in rect: NSRect) {
        guard !labels.isEmpty else { return }
        trackColor.setFill()
        NSBezierPath(roundedRect: rect, xRadius: rect.height / 2, yRadius: rect.height / 2).fill()
        for (index, frame) in segmentRects(labels: labels, in: rect).enumerated() {
            let isSelected = index == selectedIndex
            if isSelected {
                selectedFill.setFill()
                NSBezierPath(roundedRect: frame, xRadius: frame.height / 2, yRadius: frame.height / 2).fill()
            }
            drawLabel(labels[index], in: frame, color: isSelected ? selectedText : unselectedText)
        }
    }

    private static func drawLabel(_ text: String, in frame: NSRect, color: NSColor) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attributes)
        let origin = NSPoint(
            x: (frame.midX - size.width / 2).rounded(),
            y: (frame.midY - size.height / 2).rounded()
        )
        (text as NSString).draw(at: origin, withAttributes: attributes)
    }

    /// For pixel counting in tests.
    static func image(labels: [String], selectedIndex: Int) -> NSImage {
        NSImage(size: size(labels: labels), flipped: false) { rect in
            draw(labels: labels, selectedIndex: selectedIndex, in: rect)
            return true
        }
    }
}

// MARK: - View

@MainActor
final class AccountToggleView: NSView {
    private var onSelect: ((String) -> Void)?
    private(set) var currentSegments: [AccountSegment] = []
    private(set) var selectedIndex = 0
    private var toolTipViews: [NSView] = []

    private var currentLabels: [String] { currentSegments.map(\.label) }

    /// A self-drawn view has no constraints, so without this `fittingSize` is zero and the header collapses it.
    override var intrinsicContentSize: NSSize { AccountTogglePill.size(labels: currentLabels) }

    override func draw(_ dirtyRect: NSRect) {
        AccountTogglePill.draw(labels: currentLabels, selectedIndex: selectedIndex, in: bounds)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        positionToolTipViews()
    }

    func configure(with switcher: HeaderAccountSwitcher) {
        if currentSegments != switcher.segments {
            currentSegments = switcher.segments
            rebuildToolTipViews()
            invalidateIntrinsicContentSize()
        }
        if currentSegments.indices.contains(switcher.activeIndex) {
            selectedIndex = switcher.activeIndex
        }
        onSelect = switcher.onSelect
        needsDisplay = true
    }

    /// The reconciler skips the header while the menu is open, so `select(segmentAt:)` repaints itself.
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let rects = AccountTogglePill.segmentRects(labels: currentLabels, in: bounds)
        guard let index = rects.firstIndex(where: { $0.contains(point) }) else { return }
        select(segmentAt: index)
    }

    func select(segmentAt index: Int) {
        guard currentSegments.indices.contains(index) else { return }
        selectedIndex = index
        needsDisplay = true
        onSelect?(currentSegments[index].id)
    }

    private func rebuildToolTipViews() {
        toolTipViews.forEach { $0.removeFromSuperview() }
        toolTipViews = currentSegments.map { segment in
            let view = NSView()
            view.toolTip = segment.toolTip
            addSubview(view)
            return view
        }
        positionToolTipViews()
    }

    private func positionToolTipViews() {
        let rects = AccountTogglePill.segmentRects(labels: currentLabels, in: bounds)
        for (view, rect) in zip(toolTipViews, rects) {
            view.frame = rect
        }
    }
}
