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
    /// Estimated datacentre electricity, right-aligned on the same row as the stats text.
    ///
    /// A second label rather than more text appended to `statsLabel`: that label is centered across
    /// the full width, and `Formatting.statsLabelTextCore` has several return branches, so anything
    /// folded into its string would vanish in every branch but one.
    private let energyLabel = NSTextField(labelWithString: "")

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
        let rowY = GraphDrawer.Layout.topPadding + GraphDrawer.Layout.graphHeight + GraphDrawer.Layout.graphStatsGap
        let energyWidth = GraphDrawer.Layout.energyLabelWidth
        let usableWidth = bounds.width - MenuBuilder.rowTrailingInset * 2

        statsLabel.font = NSFont.systemFont(ofSize: 12)
        statsLabel.textColor = .secondaryLabelColor
        // Left, not centered: the energy estimate takes the right of this row, and a centered label
        // would drift under it as the text changes length.
        statsLabel.alignment = .left
        statsLabel.lineBreakMode = .byTruncatingTail
        statsLabel.autoresizingMask = .width
        statsLabel.frame = NSRect(
            x: MenuBuilder.rowTrailingInset,
            y: rowY,
            width: usableWidth - energyWidth - GraphDrawer.Layout.statsEnergyGap,
            height: GraphDrawer.Layout.statsHeight
        )
        addSubview(statsLabel)

        energyLabel.font = NSFont.systemFont(ofSize: 12)
        energyLabel.textColor = .secondaryLabelColor
        energyLabel.alignment = .right
        // Pinned to the trailing edge while the menu resizes; the stats label absorbs the slack.
        energyLabel.autoresizingMask = .minXMargin
        energyLabel.frame = NSRect(
            x: bounds.width - MenuBuilder.rowTrailingInset - energyWidth,
            y: rowY,
            width: energyWidth,
            height: GraphDrawer.Layout.statsHeight
        )
        addSubview(energyLabel)
        layoutStatsRow()
    }

    // MARK: - Energy

    /// Sets the energy reading, or clears the row when there is nothing to show yet.
    func update(energy: EnergyEstimate?) {
        energyLabel.stringValue = Self.energyText(for: energy)
        layoutStatsRow()
    }

    /// Gives the energy label exactly the width its text needs and the rest of the row to the stats
    /// text. Splitting the row at a fixed point meant the reserve had to cover the widest reading in
    /// the widest of thirty languages, and whatever it reserved was taken from the stats text even
    /// when the reading was short.
    private func layoutStatsRow() {
        // Inset matches the other text rows in the dropdown, not the graph's own side padding: this
        // row reads as part of the text column below the graph, and two points out of line is
        // visible against "Services" and "Updated:".
        let inset = MenuBuilder.rowTrailingInset
        let usable = bounds.width - inset * 2

        // `fittingSize`, not the measured string width. A text field needs a few points more than
        // its text: sized to the text alone it clipped the last glyph ("⚡ ~17 kWh" measures 69 pt
        // but the field needs 73).
        let energyWidth = energyLabel.stringValue.isEmpty
            ? 0
            : min(energyLabel.fittingSize.width.rounded(.up), GraphDrawer.Layout.energyLabelMaxWidth)
        let gap = energyWidth > 0 ? GraphDrawer.Layout.statsEnergyGap : 0

        energyLabel.frame.origin.x = bounds.width - inset - energyWidth
        energyLabel.frame.size.width = energyWidth
        statsLabel.frame.origin.x = inset
        statsLabel.frame.size.width = max(0, usable - energyWidth - gap)
    }

    /// The rendered energy text (for testing).
    var currentEnergyText: String { energyLabel.stringValue }

    /// Kept separate and testable: the icon-plus-range string is the whole visible contract.
    static func energyText(for estimate: EnergyEstimate?) -> String {
        guard let estimate, estimate.median > 0 else { return "" }
        return "\u{26A1} " + estimate.description
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
        let drawer = GraphDrawer(
            analyses: analyses,
            selectedIndex: selectedIndex,
            graphRect: currentGraphRect(),
            now: Date()
        )
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
