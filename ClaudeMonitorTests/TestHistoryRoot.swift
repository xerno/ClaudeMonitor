import Darwin
import Foundation
import Testing

/// Isolated on-disk root for `UsageHistory` tests: under `NSTemporaryDirectory()`, never `Application Support`.
enum TestHistoryRoot {
    private static let containerName = "ClaudeMonitorTests"

    /// Marker file content: `"<pid> <start.tv_sec> <start.tv_usec>"`.
    static let pidMarkerName = ".owner.pid"

    static let current: URL = {
        let container = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent(containerName, isDirectory: true)

        let runID = "\(ProcessInfo.processInfo.processIdentifier)-\(UUID().uuidString)"
        let root = container.appendingPathComponent(runID, isDirectory: true)

        // Clean at start, never at end: teardown would delete a failed run's evidence (`#expect` doesn't halt).
        // Only previous runs are swept; this run's directory is left for post-mortem.
        Self.sweepPreviousRuns(container: container)

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        Self.writePIDMarker(in: root)
        return root
    }()

    /// Removes run directories whose owner is dead, or whose marker is missing or unparsable.
    /// A live owner's directory is left alone: overlapping `test.sh` runs must not destroy each other's data.
    static func sweepPreviousRuns(container: URL) {
        let fm = FileManager.default
        guard let existing = try? fm.contentsOfDirectory(at: container, includingPropertiesForKeys: nil) else { return }
        for dir in existing {
            guard !isOwnerAlive(dir) else { continue }
            removeStaleDirectory(dir, fm: fm)
        }
    }

    /// Retries once after restoring write permissions: a read-only directory left behind (tests that
    /// chmod must restore it) would otherwise wedge every future sweep.
    private static func removeStaleDirectory(_ dir: URL, fm: FileManager) {
        do {
            try fm.removeItem(at: dir)
            return
        } catch {
            // Retried below.
        }

        restoreWritePermissions(in: dir, fm: fm)
        do {
            try fm.removeItem(at: dir)
        } catch {
            Issue.record("TestHistoryRoot sweep failed to remove stale directory at \(dir.path) even after restoring write permissions: \(error)")
        }
    }

    /// Recursive chmod: pass only directories inside the test container.
    /// Best-effort: an entry that stays unwritable surfaces through the removal failure, not here.
    private static func restoreWritePermissions(in dir: URL, fm: FileManager) {
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [], errorHandler: { _, _ in true }) else {
            return
        }
        for case let url as URL in enumerator {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            try? fm.setAttributes([.posixPermissions: isDirectory ? 0o755 : 0o644], ofItemAtPath: url.path)
        }
    }

    private static func writePIDMarker(in root: URL) {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Without a start time, write the PID alone: `isOwnerAlive` reads it as dead, so the worst case is an early sweep.
        guard let start = processStartTime(pid: pid) else {
            try? String(pid).write(to: root.appendingPathComponent(pidMarkerName), atomically: true, encoding: .utf8)
            return
        }
        let marker = "\(pid) \(start.tv_sec) \(start.tv_usec)"
        try? marker.write(to: root.appendingPathComponent(pidMarkerName), atomically: true, encoding: .utf8)
    }

    /// A bare PID check is not enough: PIDs are recycled, so a dead run's PID can belong to an
    /// unrelated live process and its directory would never be swept. The recorded start time must match too.
    static func isOwnerAlive(_ dir: URL) -> Bool {
        let markerURL = dir.appendingPathComponent(pidMarkerName)
        guard let content = try? String(contentsOf: markerURL, encoding: .utf8) else { return false }
        let parts = content.split(whereSeparator: { $0 == " " || $0.isNewline })
        guard parts.count == 3,
              let pid = pid_t(parts[0]),
              let recordedSec = Int(parts[1]),
              let recordedUsec = Int32(parts[2]) else {
            return false
        }
        guard let liveStart = processStartTime(pid: pid) else { return false }
        return Int(liveStart.tv_sec) == recordedSec && liveStart.tv_usec == recordedUsec
    }

    static func processStartTime(pid: pid_t) -> timeval? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return info.kp_proc.p_starttime
    }

    static func makeSubdirectory() -> URL {
        let dir = current.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
