import AppKit

@MainActor
final class AboutWindowController: NSWindowController, NSWindowDelegate {
    init() {
        let windowWidth: CGFloat = 900
        let columnWidth = windowWidth / 2
        let leftContent = Self.leftColumnContent()
        let rightContent = Self.rightColumnContent()
        let leftHeight = Self.columnHeight(leftContent, columnWidth: columnWidth)
        let rightHeight = Self.columnHeight(rightContent, columnWidth: columnWidth)
        let signatureHeight: CGFloat = 48
        let windowHeight = max(leftHeight, rightHeight) + signatureHeight

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: windowWidth, height: windowHeight),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "about.window.title", bundle: .module)
        window.minSize = NSSize(width: 400, height: 400)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI(leftContent: leftContent, rightContent: rightContent)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI(leftContent: NSAttributedString, rightContent: NSAttributedString) {
        guard let contentView = window?.contentView else { return }

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .top
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(makeColumn(leftContent))
        stack.addArrangedSubview(makeColumn(rightContent))

        let footer = Self.makeFooter()
        footer.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)
        contentView.addSubview(footer)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -24),

            footer.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -12),
            footer.heightAnchor.constraint(equalToConstant: 30),
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

    // MARK: - Footer

    private static func makeFooter() -> NSView {
        let text = NSMutableAttributedString()
        let font = NSFont.systemFont(ofSize: 11)
        let color = NSColor.labelColor
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        centered.lineSpacing = 4

        text.append(NSAttributedString(string: "Zdeněk Kopš", attributes: [
            .font: font, .link: Constants.GitHub.profile, .paragraphStyle: centered,
        ]))
        text.append(NSAttributedString(string: " · Built \(BuildInfo.date)\n", attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: centered,
        ]))
        text.append(NSAttributedString(string: "GitHub", attributes: [
            .font: font, .link: Constants.GitHub.repository, .paragraphStyle: centered,
        ]))
        text.append(NSAttributedString(string: " · ", attributes: [
            .font: font, .foregroundColor: color, .paragraphStyle: centered,
        ]))
        text.append(NSAttributedString(string: "Report an Issue", attributes: [
            .font: font, .link: Constants.GitHub.issues, .paragraphStyle: centered,
        ]))

        return CredentialGuide.makeView(text, height: 36)
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

        heading(String(localized: "about.heading.menu_bar", bundle: .module), into: s)
        s.append(line(String(localized: "about.line.shows_usage", bundle: .module)))
        s.append(line(""))
        s.append(line("  " + String(localized: "about.line.first_window", bundle: .module)))
        s.append(line("  " + String(localized: "about.line.additional_windows", bundle: .module)))
        s.append(line(""))
        s.append(secondary(String(localized: "about.secondary.additional_explain", bundle: .module)))

        heading(String(localized: "about.heading.color_coding", bundle: .module), into: s)
        s.append(line(String(localized: "about.line.color_intro", bundle: .module)))
        s.append(line(""))
        s.append(line("  " + String(localized: "about.line.normal", bundle: .module)))
        let boldLabel = NSMutableAttributedString(string: "  ", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
        ])
        boldLabel.append(NSAttributedString(string: "Bold", attributes: [
            .font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
        ]))
        boldLabel.append(NSAttributedString(string: "      " + String(localized: "about.line.bold_suffix", bundle: .module) + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor,
        ]))
        s.append(boldLabel)
        s.append(NSAttributedString(string: "  " + String(localized: "about.line.orange", bundle: .module) + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.systemOrange,
        ]))
        s.append(NSAttributedString(string: "  " + String(localized: "about.line.red", bundle: .module) + "\n", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.systemRed,
        ]))
        s.append(line(""))
        s.append(secondary(String(localized: "about.secondary.outpacing", bundle: .module)))

        heading(String(localized: "about.heading.usage_graph", bundle: .module), into: s)
        s.append(secondary(String(localized: "about.secondary.usage_graph_explain", bundle: .module)))

        return s
    }

    private static func rightColumnContent() -> NSAttributedString {
        let s = NSMutableAttributedString()

        heading(String(localized: "about.heading.refresh", bundle: .module), into: s)
        s.append(secondary(String(localized: "about.secondary.refresh_explain", bundle: .module)))

        heading(String(localized: "about.heading.status_icon", bundle: .module), into: s)
        s.append(line("  " + String(localized: "about.line.green", bundle: .module)))
        s.append(line("  " + String(localized: "about.line.yellow", bundle: .module)))
        s.append(line("  " + String(localized: "about.line.orange_icon", bundle: .module)))
        s.append(line("  " + String(localized: "about.line.red_icon", bundle: .module)))
        s.append(line("  " + String(localized: "about.line.blue_icon", bundle: .module)))
        s.append(line("  " + String(localized: "about.line.warning_icon", bundle: .module)))

        heading(String(localized: "about.heading.100_percent", bundle: .module), into: s)
        s.append(secondary(String(localized: "about.secondary.100_percent_explain", bundle: .module)))

        heading(String(localized: "about.heading.shortcuts", bundle: .module), into: s)
        s.append(line("  ⌘R  " + String(localized: "menu.refresh", bundle: .module)))
        s.append(line("  ⌘,  " + String(localized: "menu.preferences", bundle: .module)))
        s.append(line("  ⌘Q  " + String(localized: "menu.quit", bundle: .module)))

        return s
    }
}
