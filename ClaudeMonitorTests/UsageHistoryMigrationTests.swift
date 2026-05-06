import Foundation
import Testing
@testable import ClaudeMonitor

@Suite @MainActor struct MigrationTests {

    @Test func migrationDeletesLegacyDirectoriesAndPreservesOrgSubdirs() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeMonitorTests-\(UUID().uuidString).migration", isDirectory: true)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: tmpDir) }

        let liveDir = tmpDir.appendingPathComponent("live")
        let archiveDir = tmpDir.appendingPathComponent("archive/bar")
        let orgLiveDir = tmpDir.appendingPathComponent("orgA/live")

        try fm.createDirectory(at: liveDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: archiveDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: orgLiveDir, withIntermediateDirectories: true)

        try "{}".data(using: .utf8)!.write(to: liveDir.appendingPathComponent("foo.json"))
        try "{}".data(using: .utf8)!.write(to: archiveDir.appendingPathComponent("baz.json.lzma"))
        try "{}".data(using: .utf8)!.write(to: orgLiveDir.appendingPathComponent("qux.json"))

        UsageHistory.migrateAndDeleteLegacyData(baseDirectory: tmpDir)

        #expect(!fm.fileExists(atPath: tmpDir.appendingPathComponent("live").path),
                "Legacy live/ directory should have been deleted")
        #expect(!fm.fileExists(atPath: tmpDir.appendingPathComponent("archive").path),
                "Legacy archive/ directory should have been deleted")
        #expect(fm.fileExists(atPath: orgLiveDir.appendingPathComponent("qux.json").path),
                "Per-org live file must not be deleted by migration")
    }

    @Test func migrationIsIdempotentOnEmptyDirectory() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeMonitorTests-\(UUID().uuidString).migration-empty", isDirectory: true)
        let fm = FileManager.default
        defer { try? fm.removeItem(at: tmpDir) }

        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        UsageHistory.migrateAndDeleteLegacyData(baseDirectory: tmpDir)

        #expect(!fm.fileExists(atPath: tmpDir.appendingPathComponent("live").path))
        #expect(!fm.fileExists(atPath: tmpDir.appendingPathComponent("archive").path))
    }
}
