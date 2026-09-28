import Foundation
import Testing
@testable import ClaudeMonitor

// MARK: - Legacy (v1) file deletion must never outrun a verified write

@Suite @MainActor struct LegacyDeletionSafetyTests {

    @Test func legacyFileDeletedWhenItsOwnContentIsRepresentedInVerifiedV2Write() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        let now = Date()
        history.record(entries: [entry], at: now)

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        let legacyURL = liveDir.appendingPathComponent("\(entry.storageIdentity).json")
        try UsageHistory.encodeCompact([UtilizationSample(utilization: 42, timestamp: now)]).write(to: legacyURL)
        #expect(FileManager.default.fileExists(atPath: legacyURL.path), "Setup: legacy file must exist before save()")

        await history.save()

        let v2URL = liveDir.appendingPathComponent("\(entry.storageIdentity).\(Constants.History.windowInstanceFileExtension)")
        #expect(FileManager.default.fileExists(atPath: v2URL.path), "current-format file must exist after save()")
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: v2URL))
        #expect(decoded.samples.map(\.utilization) == [42], "current-format file must contain the samples that were in memory at save() time")

        #expect(!FileManager.default.fileExists(atPath: legacyURL.path),
                "Legacy file must be deleted once ITS OWN content is provably represented in the verified current-format file.")
    }

    @Test func legacyFileWithContentNotRepresentedInV2IsNeverDeleted() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        let now = Date()
        history.record(entries: [entry], at: now)

        // `[[epoch, utilization]]`: this sample is not in memory, so deleting the file would lose it.
        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        let legacyURL = liveDir.appendingPathComponent("\(entry.storageIdentity).json")
        try "[[0,1]]".data(using: .utf8)!.write(to: legacyURL)

        await history.save()

        #expect(FileManager.default.fileExists(atPath: legacyURL.path),
                "A legacy file whose own content is NOT represented in the v2 file must be preserved, never deleted.")
    }

    @Test func undecodableLegacyFileIsQuarantinedNeverDeleted() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        history.record(entries: [entry], at: Date())

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        let legacyURL = liveDir.appendingPathComponent("\(entry.storageIdentity).json")
        try Data([0xFF, 0x00, 0xDE, 0xAD, 0xBE, 0xEF]).write(to: legacyURL)

        await history.save()

        #expect(!FileManager.default.fileExists(atPath: legacyURL.path),
                "The undecodable legacy file must no longer sit at its original path (it was quarantined, not left in place).")
        let siblings = try FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)
        let quarantinedURL = try #require(siblings.first {
            UsageHistory.isQuarantineFile($0) && $0.deletingPathExtension().lastPathComponent == legacyURL.lastPathComponent
        })
        #expect(FileManager.default.fileExists(atPath: quarantinedURL.path),
                "The undecodable legacy file's bytes must be preserved under a .corrupt_<timestamp> suffix, never deleted.")
    }

    @Test func partiallyMalformedLegacyJSONFailsWholeDecodeRatherThanDroppingEntries() {
        let malformed = Data("[[0,1],[\"not-a-number\",2],[120,3]]".utf8)
        #expect(UsageHistory.decodeCompact(malformed) == nil,
                "A single malformed [epoch,util] pair must fail the entire decode.")
    }

    // MARK: - Legacy-content containment is multiset-, not set-, aware

    @Test func legacyFileWithDuplicateKeyNotFullyCoveredByASingleVerifiedSampleIsPreserved() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        let now = Date()
        history.record(entries: [entry], at: now)

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        let legacyURL = liveDir.appendingPathComponent("\(entry.storageIdentity).json")
        let duplicated = [
            UtilizationSample(utilization: 42, timestamp: now),
            UtilizationSample(utilization: 42, timestamp: now),
        ]
        try UsageHistory.encodeCompact(duplicated).write(to: legacyURL)

        await history.save()

        #expect(FileManager.default.fileExists(atPath: legacyURL.path),
                "A legacy file claiming a key TWICE must not be deleted when the verified current-format file can only back it ONCE.")
    }

    // MARK: - clearAll()/save() quarantine handling is deliberate, not incidental

    @Test func saveOrphanSweepPreservesPreviouslyQuarantinedFile() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        // Its derived identity ("18000.json") matches no storageIdentity, so only the quarantine
        // exclusion keeps save()'s orphan sweep from deleting it.
        let quarantinedURL = liveDir.appendingPathComponent("18000.json.corrupt")
        try Data([0xDE, 0xAD]).write(to: quarantinedURL)

        await history.save()

        #expect(FileManager.default.fileExists(atPath: quarantinedURL.path),
                "save()'s background orphan sweep must never delete a quarantined file.")
    }

    @Test func clearAllDeletesEverythingIncludingQuarantinedFiles() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        let quarantinedURL = liveDir.appendingPathComponent("18000.json.corrupt")
        try Data([0xDE, 0xAD]).write(to: quarantinedURL)

        await history.clearAll()

        #expect(!FileManager.default.fileExists(atPath: quarantinedURL.path),
                "clearAll() is the user's explicit \"Clear History\" action — it must erase quarantined files too, unlike save()'s background sweep above.")
    }
}

// MARK: - Environmental write failures never trap the process

@Suite @MainActor struct UnwritableDirectoryTests {

    @Test func unwritableLiveDirectoryDoesNotCrashAndPreservesInMemoryData() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let orgId = UUID().uuidString
        history.switchOrganization(orgId)

        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        history.record(entries: [entry], at: Date())

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        // Read-only directory stands in for a full disk or revoked permission.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: liveDir.path)
        defer {
            // Must restore: a read-only directory left behind wedges the test-root sweep.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: liveDir.path)
        }

        await history.save()

        #expect(history.storage[entry.storageIdentity]?.samples.map(\.utilization) == [42],
                "A write failure must never lose in-memory data.")
        let url = liveDir.appendingPathComponent("\(entry.storageIdentity).\(Constants.History.windowInstanceFileExtension)")
        #expect(!FileManager.default.fileExists(atPath: url.path),
                "Sanity check: the directory really was unwritable, so no file should have been created.")
    }
}
