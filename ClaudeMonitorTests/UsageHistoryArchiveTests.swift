import Foundation
import Testing
@testable import ClaudeMonitor

@Suite(.serialized) @MainActor struct ArchiveTests {

    @Test func archiveWindowCreatesCompressedFile() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)
        let fm = FileManager.default
        let archiveDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)

        let now = Date()
        let resetsAt = now.addingTimeInterval(3600)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)

        history.record(entries: [makeEntry(key: "five_hour", utilization: 30, resetsAt: resetsAt)],
                       at: now.addingTimeInterval(-300))
        history.record(entries: [makeEntry(key: "five_hour", utilization: 42, resetsAt: resetsAt)],
                       at: now)

        let identity = entry.storageIdentity
        await history.archiveWindow(identity: identity, resetsAt: resetsAt, windowDuration: entry.duration)

        let files = try fm.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        let lzmaFiles = files.filter { $0.pathExtension == "lzma" }
        #expect(!lzmaFiles.isEmpty, "Expected at least one .lzma file in archive directory")
        await fixture.cleanup()
    }

    @Test func pruneArchivesRemovesOldFilesAndKeepsNewOnes() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)
        let fiveHourDuration: TimeInterval = 18000
        let retentionPeriod = fiveHourDuration * Double(Constants.History.archiveRetentionMultiplier)
        let now = Date()

        let fm = FileManager.default
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)

        try fm.createDirectory(at: identityDir, withIntermediateDirectories: true)

        let formatter = archiveDateFormatterForTests()

        let oldEnd = now.addingTimeInterval(-(retentionPeriod + 86400))
        let oldStart = oldEnd.addingTimeInterval(-fiveHourDuration)
        let oldFilename = "\(formatter.string(from: oldStart))_\(formatter.string(from: oldEnd)).json.lzma"
        let oldFileURL = identityDir.appendingPathComponent(oldFilename)
        let dummyData = "[]".data(using: .utf8)!
        try dummyData.write(to: oldFileURL)

        let newEnd = now.addingTimeInterval(-3600)
        let newStart = newEnd.addingTimeInterval(-fiveHourDuration)
        let newFilename = "\(formatter.string(from: newStart))_\(formatter.string(from: newEnd)).json.lzma"
        let newFileURL = identityDir.appendingPathComponent(newFilename)
        try dummyData.write(to: newFileURL)

        #expect(fm.fileExists(atPath: oldFileURL.path), "Setup: old file must exist before prune")
        #expect(fm.fileExists(atPath: newFileURL.path), "Setup: new file must exist before prune")

        let entry = makeEntry(key: "five_hour", utilization: 0, resetsAt: now.addingTimeInterval(3600))
        await history.pruneArchives(currentEntries: [entry])

        #expect(!fm.fileExists(atPath: oldFileURL.path),
                "Old archive file should have been pruned")
        #expect(fm.fileExists(atPath: newFileURL.path),
                "New archive file should NOT have been pruned")
        await fixture.cleanup()
    }

    @Test func pruneArchivesWithEmptyEntriesDeletesNothing() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)

        let fm = FileManager.default
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try fm.createDirectory(at: identityDir, withIntermediateDirectories: true)

        let formatter = archiveDateFormatterForTests()
        let now = Date()
        let end = now.addingTimeInterval(-3600)
        let start = end.addingTimeInterval(-18000)
        let filename = "\(formatter.string(from: start))_\(formatter.string(from: end)).json.lzma"
        let fileURL = identityDir.appendingPathComponent(filename)
        try "[]".data(using: .utf8)!.write(to: fileURL)

        await history.pruneArchives(currentEntries: [])

        #expect(fm.fileExists(atPath: fileURL.path),
                "Archive file must not be deleted when currentEntries is empty")
        await fixture.cleanup()
    }
}
