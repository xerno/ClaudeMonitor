import AppKit

@MainActor
enum WindowManager {
    static func bringToFront(_ window: NSWindow?) {
        NSApp.setActivationPolicy(.regular)
        // Defer past the current run loop so the menu's dismissal sequence completes before we grab focus.
        DispatchQueue.main.async {
            window?.level = .floating
            window?.makeKeyAndOrderFront(nil)
            NSApp.activate()
            Task { @MainActor in window?.level = .normal }
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
