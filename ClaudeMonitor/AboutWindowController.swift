import AppKit

final class AboutWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Monitor – About"
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

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.textContainer?.widthTracksTextView = true
        textView.autoresizingMask = [.width]
        textView.textStorage?.setAttributedString(Self.aboutContent())
        scrollView.documentView = textView

        contentView.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: contentView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        WindowManager.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.revertActivationPolicyIfNeeded(excluding: window)
    }

    // MARK: - Content

    private static func aboutContent() -> NSAttributedString {
        let s = NSMutableAttributedString()

        func heading(_ text: String) {
            if s.length > 0 { s.append(line("\n")) }
            s.append(NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.boldSystemFont(ofSize: 14),
                .foregroundColor: NSColor.labelColor,
            ]))
        }

        func line(_ text: String) -> NSAttributedString {
            NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.labelColor,
            ])
        }

        func secondary(_ text: String) -> NSAttributedString {
            NSAttributedString(string: text + "\n", attributes: [
                .font: NSFont.systemFont(ofSize: 11.5),
                .foregroundColor: NSColor.secondaryLabelColor,
            ])
        }

        heading("Menu Bar")
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

        heading("Color Coding")
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
            "\"Outpacing time\" means your consumption rate projects " +
            "to exceed the limit before the window resets. For example, " +
            "70% used with only 40% of the window remaining."))

        heading("Refresh Behavior")
        s.append(secondary(
            "Claude Monitor adjusts how often it checks for updates. " +
            "When your usage is actively changing, it checks more frequently. " +
            "When usage is stable, it gradually checks less often " +
            "to reduce network traffic. Use Refresh Now (\u{2318}R) for an " +
            "immediate update."))

        heading("Status Icon")
        s.append(line("  ✓  Green   — all systems operational"))
        s.append(line("  !   Yellow  — degraded performance"))
        s.append(line("  !   Orange — partial outage"))
        s.append(line("  ✕  Red       — major outage"))
        s.append(line("  🔧 Blue      — under maintenance"))

        return s
    }
}
