import AppKit

/// The accent the dropdown paints with.
///
/// It exists because the system equivalent is tuned to catch the eye on a white sheet, and this UI
/// is a small dark panel the user has open all day: `systemGreen` on a one-line status reads as
/// neon against it. This sits a step back — same hue, lower saturation, darker in light mode where
/// the background stops doing the work.
extension NSColor {
    /// The calm state wherever the dropdown shows one: "All systems operational", and the fill of a
    /// usage bar that still has headroom. Deliberately one colour for both rather than two that
    /// happen to match — a window at `blockedUtilization` leaves it for `systemRed`.
    static let restingAccent = dynamic(
        dark: NSColor(srgbRed: 0.353, green: 0.667, blue: 0.475, alpha: 1),
        light: NSColor(srgbRed: 0.180, green: 0.455, blue: 0.290, alpha: 1)
    )

    /// Resolves per appearance rather than once at launch — the menu is rebuilt on every poll, but
    /// a colour captured as a plain sRGB value would keep the dark shade after a mid-session switch
    /// to light mode.
    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
