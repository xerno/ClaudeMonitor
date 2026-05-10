import AppKit

extension StatusBarRenderer {
    static func nsColor(for level: Formatting.UsageLevel) -> NSColor {
        switch level {
        case .normal: .labelColor
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }
}
