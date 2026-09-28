import AppKit

// MARK: - SentinelView

/// Accepts first responder so NSMenu treats its menu item as navigable, absorbing the auto-highlight on open.
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
        // Left, not centered: a centered label would drift under the energy estimate as its text changes length.
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

    func update(energy: EnergyEstimate?) {
        energyLabel.stringValue = Self.energyText(for: energy)
        layoutStatsRow()
    }

    /// Sizes the energy label to its text and gives the rest of the row to the stats text; a fixed
    /// split would have to reserve for the widest reading in any language, at the stats text's expense.
    private func layoutStatsRow() {
        // The dropdown's text-row inset, not the graph's side padding: a mismatch shows against "Services" and "Updated:".
        let inset = MenuBuilder.rowTrailingInset
        let usable = bounds.width - inset * 2

        // `fittingSize`, not the string width: a text field needs a few points more than its text
        // and clips the last glyph otherwise ("⚡ ~17 kWh" is 69 pt, the field needs 73).
        let energyWidth = energyLabel.stringValue.isEmpty
            ? 0
            : min(energyLabel.fittingSize.width.rounded(.up), GraphDrawer.Layout.energyLabelMaxWidth)
        let gap = energyWidth > 0 ? GraphDrawer.Layout.statsEnergyGap : 0

        energyLabel.frame.origin.x = bounds.width - inset - energyWidth
        energyLabel.frame.size.width = energyWidth
        statsLabel.frame.origin.x = inset
        statsLabel.frame.size.width = max(0, usable - energyWidth - gap)
    }

    /// Test seam.
    var currentEnergyText: String { energyLabel.stringValue }

    static func energyText(for estimate: EnergyEstimate?) -> String {
        guard let estimate, estimate.median > 0 else { return "" }
        return "\u{26A1} " + estimate.description
    }

    // Flipped: y=0 at the top, so subview layout and graph coordinates are top-down.
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

        // Ties go to the first entry, the shortest window.
        if !userSelectedIndex {
            selectedIndex = highestWarningIndex(analyses: analyses)
        } else {
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
