import Testing
import AppKit
@testable import ClaudeMonitor

@MainActor struct CredentialGuideTests {
    private let body: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 12),
        .foregroundColor: NSColor.labelColor,
    ]
    private let bold: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: 12),
        .foregroundColor: NSColor.labelColor,
    ]

    // MARK: - parseBoldMarkdown

    @Test func plainTextNoMarkers() {
        let result = CredentialGuide.parseBoldMarkdown("Hello world", body: body, bold: bold)
        #expect(result.string == "Hello world")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font == NSFont.systemFont(ofSize: 12))
    }

    @Test func singleBoldMarker() {
        let result = CredentialGuide.parseBoldMarkdown("Open **DevTools** now", body: body, bold: bold)
        #expect(result.string == "Open DevTools now")
        // "Open " at index 0 is regular
        let regularFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(regularFont == NSFont.systemFont(ofSize: 12))
        // "DevTools" starts at index 5, is bold
        let boldFont = result.attribute(.font, at: 5, effectiveRange: nil) as? NSFont
        #expect(boldFont == NSFont.boldSystemFont(ofSize: 12))
        // " now" at index 13 is regular
        let afterFont = result.attribute(.font, at: 13, effectiveRange: nil) as? NSFont
        #expect(afterFont == NSFont.systemFont(ofSize: 12))
    }

    @Test func multipleBoldMarkers() {
        let result = CredentialGuide.parseBoldMarkdown("**A** and **B**", body: body, bold: bold)
        #expect(result.string == "A and B")
        let aFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(aFont == NSFont.boldSystemFont(ofSize: 12))
        let andFont = result.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        #expect(andFont == NSFont.systemFont(ofSize: 12))
        let bFont = result.attribute(.font, at: 6, effectiveRange: nil) as? NSFont
        #expect(bFont == NSFont.boldSystemFont(ofSize: 12))
    }

    @Test func unclosedMarkerTreatedAsLiteral() {
        let result = CredentialGuide.parseBoldMarkdown("Open **DevTools now", body: body, bold: bold)
        #expect(result.string == "Open **DevTools now")
    }

    @Test func emptyBoldMarker() {
        let result = CredentialGuide.parseBoldMarkdown("A****B", body: body, bold: bold)
        #expect(result.string == "AB")
    }

    @Test func adjacentBoldMarkers() {
        let result = CredentialGuide.parseBoldMarkdown("**A****B**", body: body, bold: bold)
        #expect(result.string == "AB")
        let aFont = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(aFont == NSFont.boldSystemFont(ofSize: 12))
        let bFont = result.attribute(.font, at: 1, effectiveRange: nil) as? NSFont
        #expect(bFont == NSFont.boldSystemFont(ofSize: 12))
    }

    @Test func emptyString() {
        let result = CredentialGuide.parseBoldMarkdown("", body: body, bold: bold)
        #expect(result.string == "")
    }

    @Test func onlyBoldText() {
        let result = CredentialGuide.parseBoldMarkdown("**everything bold**", body: body, bold: bold)
        #expect(result.string == "everything bold")
        let font = result.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font == NSFont.boldSystemFont(ofSize: 12))
    }

    @Test func realStep2String() {
        let input = "2. Open **DevTools** (⌥⌘I) → **Network** tab"
        let result = CredentialGuide.parseBoldMarkdown(input, body: body, bold: bold)
        #expect(result.string == "2. Open DevTools (⌥⌘I) → Network tab")
        // "DevTools" starts at index 8
        let devToolsFont = result.attribute(.font, at: 8, effectiveRange: nil) as? NSFont
        #expect(devToolsFont == NSFont.boldSystemFont(ofSize: 12))
    }

    @Test func realStep5String() {
        let input = "5. Click the same request → **Headers** → copy the entire **Cookie** header value"
        let result = CredentialGuide.parseBoldMarkdown(input, body: body, bold: bold)
        #expect(result.string == "5. Click the same request → Headers → copy the entire Cookie header value")
    }
}
