import AppKit

enum CredentialGuide {
    static func orgInstructions() -> NSAttributedString {
        let body = bodyAttrs()
        let bold = boldAttrs()
        let mono: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]
        let monoHighlight: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium),
            .foregroundColor: NSColor.systemBlue,
        ]

        let s = NSMutableAttributedString()

        s.append(NSAttributedString(string: "1. Open ", attributes: body))
        s.append(NSAttributedString(string: "claude.ai/settings/usage", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .link: URL(string: "https://claude.ai/settings/usage")!,
        ]))
        s.append(NSAttributedString(string: "\n", attributes: body))

        s.append(NSAttributedString(string: "2. Open ", attributes: body))
        s.append(NSAttributedString(string: "DevTools", attributes: bold))
        s.append(NSAttributedString(string: " (⌥⌘I) → ", attributes: body))
        s.append(NSAttributedString(string: "Network", attributes: bold))
        s.append(NSAttributedString(string: " tab\n", attributes: body))

        s.append(NSAttributedString(string: "3. Click the refresh button  ", attributes: body))
        let attachment = NSTextAttachment()
        if let icon = NSImage(named: "RefreshUsage") {
            icon.size = NSSize(width: 14, height: 14)
            attachment.image = icon
        }
        s.append(NSAttributedString(attachment: attachment))
        s.append(NSAttributedString(string: "  on the usage page\n", attributes: body))

        s.append(NSAttributedString(string: "4. In DevTools, find the request URL:\n", attributes: body))
        s.append(NSAttributedString(string: "   https://claude.ai/api/organizations/", attributes: mono))
        s.append(NSAttributedString(string: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", attributes: monoHighlight))
        s.append(NSAttributedString(string: "/usage\n", attributes: mono))
        s.append(NSAttributedString(string: "   The blue part is your ", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        s.append(NSAttributedString(string: "Organization ID", attributes: bold))

        return s
    }

    static func cookieInstructions() -> NSAttributedString {
        let body = bodyAttrs()
        let bold = boldAttrs()

        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "5. Click the same request → ", attributes: body))
        s.append(NSAttributedString(string: "Headers", attributes: bold))
        s.append(NSAttributedString(string: " → copy the entire ", attributes: body))
        s.append(NSAttributedString(string: "Cookie", attributes: bold))
        s.append(NSAttributedString(string: " header value", attributes: body))
        return s
    }

    static func makeView(_ content: NSAttributedString, height: CGFloat) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.heightAnchor.constraint(equalToConstant: height).isActive = true

        let tv = NSTextView()
        tv.isEditable = false
        tv.isSelectable = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.textContainer?.widthTracksTextView = true
        tv.autoresizingMask = [.width]
        tv.isAutomaticLinkDetectionEnabled = false
        tv.textStorage?.setAttributedString(content)
        scrollView.documentView = tv
        return scrollView
    }

    private static func bodyAttrs() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
    }

    private static func boldAttrs() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
    }
}
