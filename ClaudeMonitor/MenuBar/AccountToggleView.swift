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

/// Geometry and drawing for the account switcher, kept out of the view so the hit test and the
/// tests can both measure it without a live control on screen.
///
/// Drawn rather than built from `NSSegmentedControl`: the control paints the selected segment with
/// the system accent and exposes no way to colour the label. `selectedSegmentBezelColor` was tried
/// on the running app and does nothing on the `.automatic` style — Apple documents it as honoured
/// only "in appearances that support it" — and even where it does paint, the label stays white,
/// which is 3.2:1 on this fill and below the readable threshold.
@MainActor
enum AccountTogglePill {
    static let height: CGFloat = 18
    /// Space either side of a label inside its own segment.
    static let horizontalPadding: CGFloat = 9
    static var font: NSFont { NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small)) }

    /// Track behind both segments — same treatment as the header badge, so the two read as one
    /// family of small pills.
    static var trackColor: NSColor { NSColor.quaternaryLabelColor.withAlphaComponent(0.18) }
    /// The active segment carries the mark's coral, so the switcher and the logo are one colour.
    static var selectedFill: NSColor { ClaudeGlyph.color }
    /// Dark label on the coral: white would be 3.2:1, this is 5.5:1. Same rule as the menu bar
    /// badges, where a bright disc gets the dark glyph and a dark disc the white one.
    static var selectedText: NSColor { StatusBarRenderer.darkGlyph }
    static var unselectedText: NSColor { .secondaryLabelColor }

    static func segmentWidths(_ labels: [String]) -> [CGFloat] {
        labels.map { ($0 as NSString).size(withAttributes: [.font: font]).width + horizontalPadding * 2 }
    }

    static func size(labels: [String]) -> NSSize {
        NSSize(width: segmentWidths(labels).reduce(0, +).rounded(.up), height: height)
    }

    /// Each segment's frame inside `rect`, left to right.
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

    /// The pill as a standalone image, so tests can count its pixels the way they count the mark's.
    static func image(labels: [String], selectedIndex: Int) -> NSImage {
        NSImage(size: size(labels: labels), flipped: false) { rect in
            draw(labels: labels, selectedIndex: selectedIndex, in: rect)
            return true
        }
    }
}

// MARK: - View

/// Compact account switcher pinned to the trailing edge of the dropdown's title header, one segment
/// per account, the active one filled with the mark's coral. Selecting a segment reports the chosen
/// profile id via `onSelect`; the menu builder drives the switch from it.
@MainActor
final class AccountToggleView: NSView {
    private var onSelect: ((String) -> Void)?
    private(set) var currentSegments: [AccountSegment] = []
    private(set) var selectedIndex = 0
    private var toolTipViews: [NSView] = []

    private var currentLabels: [String] { currentSegments.map(\.label) }

    /// The header sizes the switcher from `fittingSize`, and a view that draws itself has no
    /// constraints to derive one from — without this it collapses to zero width and disappears.
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

    /// Repaints itself rather than waiting for the next rebuild: while the menu is open the
    /// reconciler only touches the rows it tracks, and the header is not one of them, so without
    /// this the coral would not move until the menu was closed and reopened.
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
