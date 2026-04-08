import AppKit

@MainActor
enum WindowManager {
    static func bringToFront(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        window?.level = .floating
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Task { @MainActor in
            window?.level = .normal
        }
    }

    static func revertActivationPolicyIfNeeded(excluding closingWindow: NSWindow? = nil) {
        Task { @MainActor in
            let hasVisibleWindows = NSApp.windows.contains {
                $0 !== closingWindow && $0.isVisible && $0.windowController != nil
            }
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
