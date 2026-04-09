import AppKit

@MainActor
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

        s.append(NSAttributedString(string: String(localized: "guide.step1.prefix", bundle: .module), attributes: body))
        s.append(NSAttributedString(string: "claude.ai/settings/usage", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .link: URL(string: "https://claude.ai/settings/usage")!,
        ]))
        s.append(NSAttributedString(string: "\n", attributes: body))

        let step2 = String(localized: "guide.step2", bundle: .module)
        s.append(parseBoldMarkdown(step2 + "\n", body: body, bold: bold))

        s.append(NSAttributedString(string: String(localized: "guide.step3.prefix", bundle: .module), attributes: body))
        let attachment = NSTextAttachment()
        if let icon = NSImage(named: "RefreshUsage") {
            icon.size = NSSize(width: 14, height: 14)
            attachment.image = icon
        }
        s.append(NSAttributedString(attachment: attachment))
        s.append(NSAttributedString(string: String(localized: "guide.step3.suffix", bundle: .module) + "\n", attributes: body))

        s.append(NSAttributedString(string: String(localized: "guide.step4.prefix", bundle: .module) + "\n", attributes: body))
        s.append(NSAttributedString(string: "   https://claude.ai/api/organizations/", attributes: mono))
        s.append(NSAttributedString(string: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", attributes: monoHighlight))
        s.append(NSAttributedString(string: "/usage\n", attributes: mono))
        s.append(NSAttributedString(string: String(localized: "guide.step4.hint", bundle: .module), attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        s.append(NSAttributedString(string: String(localized: "guide.org_id_label", bundle: .module), attributes: bold))

        return s
    }

    static func cookieInstructions() -> NSAttributedString {
        let body = bodyAttrs()
        let bold = boldAttrs()

        let s = NSMutableAttributedString()
        let step5 = String(localized: "guide.step5", bundle: .module)
        s.append(parseBoldMarkdown(step5, body: body, bold: bold))
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

    static func parseBoldMarkdown(
        _ text: String,
        body: [NSAttributedString.Key: Any],
        bold: [NSAttributedString.Key: Any]
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        var remaining = text[text.startIndex...]

        while let openRange = remaining.range(of: "**") {
            result.append(NSAttributedString(
                string: String(remaining[remaining.startIndex..<openRange.lowerBound]),
                attributes: body
            ))
            remaining = remaining[openRange.upperBound...]

            guard let closeRange = remaining.range(of: "**") else {
                result.append(NSAttributedString(string: "**" + String(remaining), attributes: body))
                return result
            }
            result.append(NSAttributedString(
                string: String(remaining[remaining.startIndex..<closeRange.lowerBound]),
                attributes: bold
            ))
            remaining = remaining[closeRange.upperBound...]
        }

        if !remaining.isEmpty {
            result.append(NSAttributedString(string: String(remaining), attributes: body))
        }
        return result
    }

    private static func bodyAttrs() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
    }

    private static func boldAttrs() -> [NSAttributedString.Key: Any] {
        [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
    }
}
