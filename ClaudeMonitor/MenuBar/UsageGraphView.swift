import AppKit

// MARK: - SentinelView

/// Invisible 1×1 view that accepts first responder so NSMenu treats its enclosing menu item
/// as a navigable target — used to absorb NSMenu's auto-highlight on open.
final class SentinelView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

// MARK: - UsageGraphView

@MainActor
final class UsageGraphView: NSView {
    private var analyses: [WindowAnalysis] = []
    private var selectedIndex: Int = 0
    private var userSelectedIndex: Bool = false
    private let statsLabel = NSTextField(labelWithString: "")

    var currentSelectedIndex: Int { selectedIndex }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: GraphDrawer.Layout.defaultWidth, height: GraphDrawer.Layout.totalHeight))
        autoresizingMask = .width
        setupViews()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        statsLabel.font = NSFont.systemFont(ofSize: 12)
        statsLabel.textColor = .secondaryLabelColor
        statsLabel.alignment = .center
        statsLabel.autoresizingMask = .width
        statsLabel.frame = NSRect(
            x: GraphDrawer.Layout.sidePadding,
            y: GraphDrawer.Layout.topPadding + GraphDrawer.Layout.graphHeight + GraphDrawer.Layout.graphStatsGap,
            width: bounds.width - GraphDrawer.Layout.sidePadding * 2,
            height: GraphDrawer.Layout.statsHeight
        )
        addSubview(statsLabel)
    }

    // NSView uses non-flipped coordinates (y=0 at bottom) by default on macOS.
    // We override isFlipped to make it flipped (y=0 at top) so layout math is
    // simpler for subview positioning, but we handle graph drawing manually.
    override var isFlipped: Bool { true }

    func selectWindow(at index: Int) {
        guard !analyses.isEmpty else { return }
        selectedIndex = max(0, min(index, analyses.count - 1))
        userSelectedIndex = true
        updateFrameHeight()
        updateStatsLabel()
        needsDisplay = true
    }

    func update(analyses: [WindowAnalysis]) {
        let countChanged = analyses.count != self.analyses.count
        self.analyses = analyses

        if countChanged {
            userSelectedIndex = false
        }

        // Default selected: highest warning level. On tie, first (shortest duration).
        // Only auto-select if user hasn't manually chosen.
        if !userSelectedIndex {
            selectedIndex = highestWarningIndex(analyses: analyses)
        } else {
            // Clamp in case count decreased
            selectedIndex = max(0, min(selectedIndex, analyses.count - 1))
        }

        updateFrameHeight()
        updateStatsLabel()
        needsDisplay = true
    }

    private func highestWarningIndex(analyses: [WindowAnalysis]) -> Int {
        guard !analyses.isEmpty else { return 0 }
        var best = 0
        var bestScore = levelScore(analyses[0].style)
        for (i, a) in analyses.enumerated().dropFirst() {
            let score = levelScore(a.style)
            if score > bestScore {
                bestScore = score
                best = i
            }
        }
        return best
    }

    private func levelScore(_ style: Formatting.UsageStyle) -> Int {
        switch style.level {
        case .normal: return style.isBold ? 1 : 0
        case .warning: return 2
        case .critical: return 3
        }
    }

    // MARK: - Frame Height

    private var selectedHasData: Bool {
        guard selectedIndex < analyses.count else { return false }
        return analyses[selectedIndex].entry.window.resetsAt != nil
    }

    private func updateFrameHeight() {
        let targetHeight = selectedHasData ? GraphDrawer.Layout.totalHeight : GraphDrawer.Layout.noDataHeight
        guard frame.height != targetHeight else { return }
        frame.size.height = targetHeight
        statsLabel.isHidden = !selectedHasData
        if selectedHasData {
            statsLabel.frame.origin.y = targetHeight - GraphDrawer.Layout.statsHeight - GraphDrawer.Layout.bottomPadding
        }
    }

    // MARK: - Graph Rect Helper

    private func currentGraphRect() -> NSRect {
        let graphWidth = bounds.width - GraphDrawer.Layout.sidePadding * 2
        return NSRect(
            x: GraphDrawer.Layout.sidePadding,
            y: GraphDrawer.Layout.topPadding,
            width: graphWidth,
            height: GraphDrawer.Layout.graphHeight
        )
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard selectedIndex < analyses.count else { return }
        let drawer = GraphDrawer(analyses: analyses, selectedIndex: selectedIndex, graphRect: currentGraphRect(), now: Date())
        drawer.draw()
    }

    // MARK: - Stats Label

    private func updateStatsLabel(now: Date = Date()) {
        guard selectedIndex < analyses.count else {
            statsLabel.stringValue = ""
            return
        }
        let analysis = analyses[selectedIndex]
        guard analysis.entry.window.resetsAt != nil else {
            statsLabel.stringValue = ""
            return
        }
        statsLabel.stringValue = Formatting.statsLabelText(analysis: analysis, now: now)
    }
}
