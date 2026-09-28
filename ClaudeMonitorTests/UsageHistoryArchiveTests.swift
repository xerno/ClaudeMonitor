import Foundation
import Testing
@testable import ClaudeMonitor

@Suite(.serialized) @MainActor struct ArchiveTests {

    @Test func archiveWindowCreatesV2File() async throws {
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
        await history.archiveWindow(identity: identity, resetsAt: resetsAt, windowDuration: entry.duration, replacingWith: nil)

        let files = try fm.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)
        let v2Files = files.filter { $0.pathExtension == Constants.History.windowInstanceFileExtension }
        #expect(!v2Files.isEmpty, "Expected at least one current-format file in archive directory")
        if let file = v2Files.first {
            let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: file))
            #expect(decoded.samples.map(\.utilization) == [30, 42])
        }
    }

    @Test func pruneArchivesRemovesOldFilesAndKeepsNewOnes() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)
        let fiveHourDuration: TimeInterval = 18000
        let retentionYears = 2
        let now = Date()

        let fm = FileManager.default
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)

        try fm.createDirectory(at: identityDir, withIntermediateDirectories: true)

        let formatter = archiveDateFormatterForTests()

        let cutoff = UsageHistory.retentionCutoff(years: retentionYears, now: now)!
        let oldEnd = cutoff.addingTimeInterval(-86400)
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

        await history.pruneArchives(retentionYears: retentionYears, now: now)

        #expect(!fm.fileExists(atPath: oldFileURL.path),
                "Old archive file should have been pruned")
        #expect(fm.fileExists(atPath: newFileURL.path),
                "New archive file should NOT have been pruned")
    }
}
