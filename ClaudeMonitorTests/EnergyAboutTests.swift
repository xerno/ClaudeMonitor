import Testing
import AppKit
@testable import ClaudeMonitor

/// The About window is where the single reading's provenance lives, so it has to actually say it.
@MainActor
struct EnergyAboutTests {

    private func aboutText(energy: EnergyEstimate?) -> String {
        let controller = AboutWindowController(energy: energy)
        defer { controller.window?.close() }
        guard let content = controller.window?.contentView else { return "" }
        var collected = ""
        func walk(_ view: NSView) {
            if let text = view as? NSTextView { collected += text.string }
            if let field = view as? NSTextField { collected += field.stringValue }
            view.subviews.forEach(walk)
        }
        walk(content)
        return collected
    }

    @Test func aboutNamesTheSourceAndTheAccountingBoundary() {
        let text = aboutText(energy: EnergyModel.estimate(outputTokens: 16_112_710))
        #expect(text.contains("Joule"), "the anchor has to be named, not just implied")
        #expect(text.contains("0.31 Wh"))
        #expect(text.contains("datacentre"))
        #expect(text.contains("training"), "readers will assume training is included unless told otherwise")
    }

    /// The menu shows one number; the spread belongs here, computed on the user's own totals.
    @Test func aboutStatesTheSpreadForTheCurrentTotals() {
        let estimate = EnergyModel.estimate(outputTokens: 16_112_710)
        #expect(aboutText(energy: estimate).contains(estimate.rangeDescription))
    }

    @Test func aboutStillRendersBeforeTheFirstScan() {
        let text = aboutText(energy: nil)
        #expect(text.contains("Joule"))
        #expect(!text.contains("works out to"), "no spread can be quoted without totals")
    }
}
