import AppKit

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let windowWidth: CGFloat = 700
        let columnWidth = windowWidth / 2
        let leftHeight = Self.columnHeight(Self.leftColumnContent(), columnWidth: columnWidth)
        let rightHeight = Self.columnHeight(Self.rightColumnContent(), columnWidth: columnWidth)
        let signatureHeight: CGFloat = 32
        let windowHeight = max(leftHeight, rightHeight) + signatureHeight

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Monitor – About"
        window.minSize = NSSize(width: 400, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeColumn(Self.leftColumnContent()))
        stack.addArrangedSubview(makeColumn(Self.rightColumnContent()))

        let signature = NSTextField(labelWithString: "Zdeněk Kopš · 2026")
        signature.font = NSFont.systemFont(ofSize: 11)
        signature.textColor = NSColor.tertiaryLabelColor
        signature.alignment = .center
        signature.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        contentView.addSubview(signature)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: signature.topAnchor, constant: -8),

            signature.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            signature.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            signature.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
        ])
    }

    private func makeColumn(_ content: NSAttributedString) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textStorage?.setAttributedString(content)
        scrollView.documentView = textView

        return scrollView
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        WindowManager.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.revertActivationPolicyIfNeeded(excluding: window)
    }

    // MARK: - Height calculation

    private static func columnHeight(_ content: NSAttributedString, columnWidth: CGFloat) -> CGFloat {
        let inset: CGFloat = 16
        let textWidth = columnWidth - inset * 2
        let storage = NSTextStorage(attributedString: content)
        let container = NSTextContainer(size: NSSize(width: textWidth, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.glyphRange(for: container)
        return layout.usedRect(for: container).height + inset * 2
    }

    // MARK: - Content helpers

    private static func heading(_ text: String, into s: NSMutableAttributedString) {
        if s.length > 0 { s.append(NSAttributedString(string: "\n")) }
        s.append(NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 14),
            .foregroundColor: NSColor.labelColor,
        ]))
    }

    private static func line(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.labelColor,
        ])
    }

    private static func secondary(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11.5),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
    }

    // MARK: - Column content

    private static func leftColumnContent() -> NSAttributedString {
        let s = NSMutableAttributedString()

        heading("Menu Bar", into: s)
        s.append(line("The menu bar shows your Claude usage as percentages."))
        s.append(line(""))
        s.append(line("  1st number — 5-hour window (always visible)"))
        s.append(line("  2nd number — 7-day window"))
        s.append(line("  3rd number — 7-day Sonnet window"))
        s.append(line(""))
        s.append(secondary(
            "The 7-day windows appear only when usage is significant " +
            "and outpacing the remaining time in the window. " +
            "For example, if you've used 60% with only 40% of the " +
            "time remaining, the number will appear as a warning."))
        s.append(secondary(
            "If only the Sonnet window triggers, the 7-day window " +
            "is also shown so the position stays consistent."))

        heading("Color Coding", into: s)
        s.append(line("Each percentage is styled independently:"))
        s.append(line(""))
        s.append(line("  Normal  — usage is within comfortable limits"))
        let boldLabel = NSMutableAttributedString(string: "  ", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
        ])
        boldLabel.append(NSAttributedString(string: "Bold", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
        ]))
        boldLabel.append(NSAttributedString(string: "      — ≥ 50%, or outpacing remaining time\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
        ]))
        s.append(boldLabel)
        s.append(NSAttributedString(string: "  Orange  — ≥ 70%, or significantly outpacing time\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.systemOrange,
        ]))
        s.append(NSAttributedString(string: "  Red       — ≥ 80%, or critically outpacing time\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.systemRed,
        ]))
        s.append(line(""))
        s.append(secondary(
            "\"Outpacing time\" means your consumption rate projects to exceed the limit before the window resets."))

        return s
    }

    private static func rightColumnContent() -> NSAttributedString {
        let s = NSMutableAttributedString()

        heading("Refresh Behavior", into: s)
        s.append(secondary(
            "Claude Monitor adjusts how often it checks for updates. " +
            "When your usage is actively changing, it checks more frequently. " +
            "When usage is stable, it gradually checks less often " +
            "to reduce network traffic. Use Refresh Now (\u{2318}R) for an " +
            "immediate update."))

        heading("Status Icon", into: s)
        s.append(line("  ✓  Green   — all systems operational"))
        s.append(line("  !   Yellow  — degraded performance"))
        s.append(line("  !   Orange — partial outage"))
        s.append(line("  ✕  Red       — major outage"))
        s.append(line("  🔧 Blue      — under maintenance"))

        heading("When You Hit 100%", into: s)
        s.append(secondary(
            "If any usage window reaches 100%, Claude Monitor replaces percentages by a countdown showing time until the limit clears."))

        return s
    }
}
