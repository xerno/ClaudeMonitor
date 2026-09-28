import AppKit

/// Softer than `systemGreen`, which reads as neon on the dropdown's small dark panel.
extension NSColor {
    /// The calm state: "All systems operational" and the fill of a usage bar with headroom. One
    /// colour on purpose; a window at `blockedUtilization` leaves it for `systemRed`.
    static let restingAccent = dynamic(
        dark: NSColor(srgbRed: 0.353, green: 0.667, blue: 0.475, alpha: 1),
        light: NSColor(srgbRed: 0.180, green: 0.455, blue: 0.290, alpha: 1)
    )

    /// Resolved per appearance: a plain sRGB value would keep its shade after a mid-session
    /// light/dark switch.
    private static func dynamic(dark: NSColor, light: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
