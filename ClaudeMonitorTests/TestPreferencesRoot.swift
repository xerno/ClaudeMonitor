import Foundation

/// Isolated `UserDefaults(suiteName:)` domains for tests, which never touch `UserDefaults.standard`.
/// Leftover plists are swept at startup: `removePersistentDomain(forName:)` clears the in-memory
/// domain but leaves the plist under `~/Library/Preferences/`.
enum TestPreferencesRoot {
    static let prefix = "com.claudemonitor.tests."

    /// Sweeps before this run creates any suite, so a run never deletes its own plists.
    private static let sweepOnce: Void = {
        sweepPreviousRuns()
    }()

    static func makeSuiteName(_ label: String) -> String {
        _ = sweepOnce
        return "\(prefix)\(label).\(UUID().uuidString)"
    }

    /// Only plists named `<prefix>*`: never another domain's, including the app's real one.
    static func sweepPreviousRuns() {
        guard let libraryDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let prefsDir = libraryDir.appendingPathComponent("Preferences", isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: prefsDir, includingPropertiesForKeys: nil) else { return }
        for file in files {
            guard file.lastPathComponent.hasPrefix(prefix) else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }
}
