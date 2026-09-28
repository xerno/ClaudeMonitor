import Foundation
import Testing
@testable import ClaudeMonitor

/// Quarantine age comes from the `.corrupt_<timestamp>` filename, never mtime: a failed
/// `setAttributes` leaves the original file's inherited mtime, which would prune the file at
/// once or never.
@Suite @MainActor struct UsageHistoryQuarantineRetentionTests {

    @Test func oldTimestampedQuarantinedFileIsPrunedRecentOneSurvives() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let fm = FileManager.default
        let liveDir = history.liveDirectory
        try fm.createDirectory(at: liveDir, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_786_984_799)
        let years = 2
        let cutoff = try #require(UsageHistory.retentionCutoff(years: years, now: now))
        let formatter = UsageHistory.archiveDateFormatter

        let oldStamp = formatter.string(from: cutoff.addingTimeInterval(-3600))
        let oldQuarantined = liveDir.appendingPathComponent("18000.dat.corrupt_\(oldStamp)")
        try Data([0xDE, 0xAD]).write(to: oldQuarantined)
        // Decoy mtime, opposite to the filename's age.
        try fm.setAttributes([.modificationDate: now], ofItemAtPath: oldQuarantined.path)

        let recentStamp = formatter.string(from: cutoff.addingTimeInterval(3600))
        let recentQuarantined = liveDir.appendingPathComponent("604800.dat.corrupt_\(recentStamp)")
        try Data([0xBE, 0xEF]).write(to: recentQuarantined)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: recentQuarantined.path)

        let countBefore = await history.quarantinedFileCount()
        #expect(countBefore == 2)

        await history.pruneQuarantinedFiles(retentionYears: years, now: now)

        #expect(!fm.fileExists(atPath: oldQuarantined.path), "A quarantined file whose ENCODED timestamp is older than retention must be pruned.")
        #expect(fm.fileExists(atPath: recentQuarantined.path), "A quarantined file whose encoded timestamp is within retention must survive, regardless of its mtime.")

        let countAfter = await history.quarantinedFileCount()
        #expect(countAfter == 1)
    }

    @Test func oldShapeQuarantinedFileWithNoEncodedTimestampIsNeverPruned() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let fm = FileManager.default
        let liveDir = history.liveDirectory
        try fm.createDirectory(at: liveDir, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_786_984_799)
        let years = 2
        let cutoff = try #require(UsageHistory.retentionCutoff(years: years, now: now))

        let plainOldShape = liveDir.appendingPathComponent("18000.dat.corrupt")
        try Data([0xDE, 0xAD]).write(to: plainOldShape)
        try fm.setAttributes([.modificationDate: cutoff.addingTimeInterval(-3600)], ofItemAtPath: plainOldShape.path)

        let collisionOldShape = liveDir.appendingPathComponent("604800.dat.corrupt-2")
        try Data([0xBE, 0xEF]).write(to: collisionOldShape)
        try fm.setAttributes([.modificationDate: cutoff.addingTimeInterval(-3600)], ofItemAtPath: collisionOldShape.path)

        await history.pruneQuarantinedFiles(retentionYears: years, now: now)

        #expect(fm.fileExists(atPath: plainOldShape.path), "An old-shape `.corrupt` file with no encoded timestamp has unknown age and must never be pruned.")
        #expect(fm.fileExists(atPath: collisionOldShape.path), "An old-shape `.corrupt-N` file with no encoded timestamp has unknown age and must never be pruned.")
    }

    @Test func pruneArchivesAlsoPrunesQuarantinedFiles() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let fm = FileManager.default
        let liveDir = history.liveDirectory
        try fm.createDirectory(at: liveDir, withIntermediateDirectories: true)

        let now = Date(timeIntervalSince1970: 1_786_984_799)
        let years = 2
        let cutoff = try #require(UsageHistory.retentionCutoff(years: years, now: now))
        let oldStamp = UsageHistory.archiveDateFormatter.string(from: cutoff.addingTimeInterval(-3600))

        let oldQuarantined = liveDir.appendingPathComponent("18000.dat.corrupt_\(oldStamp)")
        try Data([0xDE, 0xAD]).write(to: oldQuarantined)

        await history.pruneArchives(retentionYears: years, now: now)

        #expect(!fm.fileExists(atPath: oldQuarantined.path))
    }

    @Test func quarantineEncodesTimestampInFilenameNotFilesystemAttribute() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let fm = FileManager.default
        let liveDir = history.liveDirectory
        try fm.createDirectory(at: liveDir, withIntermediateDirectories: true)

        let legacyURL = liveDir.appendingPathComponent("18000.json")
        try Data([0xFF, 0x00, 0xDE, 0xAD]).write(to: legacyURL)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 0)], ofItemAtPath: legacyURL.path)

        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        history.record(entries: [entry], at: Date())
        await history.save() // quarantines the undecodable legacy file

        let files = try fm.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)
        let quarantinedURL = try #require(files.first { UsageHistory.isQuarantineFile($0) && $0.deletingPathExtension().lastPathComponent == "18000.json" })

        let encodedTimestamp = try #require(UsageHistory.quarantineTimestamp(quarantinedURL))
        #expect(encodedTimestamp.timeIntervalSinceNow > -60, "The encoded timestamp must reflect quarantine time, not the original file's ancient modification date.")

        // The rename keeps the ancient mtime; only the filename timestamp protects the file.
        await history.pruneQuarantinedFiles()
        #expect(fm.fileExists(atPath: quarantinedURL.path))
    }
}

@Suite @MainActor struct UsageHistoryPersistenceFailureStateTests {

    @Test func successfulSaveReportsSuccessWithNoFailureClock() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        history.record(entries: [entry], at: Date())

        await history.save()

        #expect(history.lastSaveSucceeded)
        #expect(history.persistenceFailingSince == nil)
    }

    @Test func failingSaveSetsFailureStateAndClockOnlyOnce() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        history.record(entries: [entry], at: Date())

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: liveDir.path)
        defer {
            // Must restore: a read-only directory left behind wedges the test-root sweep.
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: liveDir.path)
        }

        await history.save()
        #expect(!history.lastSaveSucceeded)
        let firstFailureTime = try #require(history.persistenceFailingSince)

        await history.save()
        #expect(!history.lastSaveSucceeded)
        #expect(history.persistenceFailingSince == firstFailureTime)
    }

    @Test func recoveringSaveClearsTheFailureClock() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let entry = makeEntry(key: "five_hour", utilization: 42, resetsAt: Date().addingTimeInterval(3600))
        history.record(entries: [entry], at: Date())

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: liveDir.path)
        var restored = false
        defer {
            if !restored {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: liveDir.path)
            }
        }

        await history.save()
        #expect(!history.lastSaveSucceeded)
        #expect(history.persistenceFailingSince != nil)

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: liveDir.path)
        restored = true

        await history.save()
        #expect(history.lastSaveSucceeded)
        #expect(history.persistenceFailingSince == nil, "A fully successful save must clear the failure clock.")
    }
}
