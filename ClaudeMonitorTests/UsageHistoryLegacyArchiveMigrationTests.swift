import Foundation
import Testing
@testable import ClaudeMonitor

@Suite @MainActor struct LegacyArchiveMigrationTests {

    /// Writes uncompressed JSON: the decoder falls back to raw JSON when LZMA decompression
    /// fails, so this takes the same path as real compressed archives.
    @discardableResult
    private func writeLegacyArchive(history: UsageHistory, identity: String, filename: String, samples: [UtilizationSample]) throws -> URL {
        let dir = history.archiveDirectory.appendingPathComponent(identity)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(filename)
        try UsageHistory.encodeCompact(samples).write(to: url)
        return url
    }

    private func makeSamples(count: Int, startEpoch: Int) -> [UtilizationSample] {
        (0..<count).map { UtilizationSample(utilization: $0 % 100, timestamp: Date(timeIntervalSince1970: TimeInterval(startEpoch + $0 * 60))) }
    }

    @Test func migratesMultipleLegacyArchivesToCurrentFormat() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let samplesA = makeSamples(count: 10, startEpoch: 1_700_000_000)
        let samplesB = makeSamples(count: 5, startEpoch: 1_700_100_000)
        let nameA = "2026-01-01T0000Z_2026-01-01T0500Z.json.lzma"
        let nameB = "2026-02-01T0000Z_2026-02-08T0000Z.json.lzma"
        try writeLegacyArchive(history: history, identity: "18000", filename: nameA, samples: samplesA)
        try writeLegacyArchive(history: history, identity: "604800", filename: nameB, samples: samplesB)

        let result = await history.migrateLegacyArchives()

        #expect(result.migratedCount == 2)
        #expect(result.skippedUnparseableCount == 0)
        #expect(result.quarantinedCount == 0)
        #expect(result.failedWriteCount == 0)

        let fm = FileManager.default
        let legacyA = history.archiveDirectory.appendingPathComponent("18000").appendingPathComponent(nameA)
        let legacyB = history.archiveDirectory.appendingPathComponent("604800").appendingPathComponent(nameB)
        #expect(!fm.fileExists(atPath: legacyA.path), "Legacy archive must be removed once migrated")
        #expect(!fm.fileExists(atPath: legacyB.path), "Legacy archive must be removed once migrated")

        let datA = history.archiveDirectory.appendingPathComponent("18000")
            .appendingPathComponent("2026-01-01T0000Z_2026-01-01T0500Z.\(Constants.History.windowInstanceFileExtension)")
        let datB = history.archiveDirectory.appendingPathComponent("604800")
            .appendingPathComponent("2026-02-01T0000Z_2026-02-08T0000Z.\(Constants.History.windowInstanceFileExtension)")
        #expect(fm.fileExists(atPath: datA.path), "Filename span must be preserved, only the extension changes")
        #expect(fm.fileExists(atPath: datB.path), "Filename span must be preserved, only the extension changes")

        let decodedA = try WindowInstanceCodec.decode(try Data(contentsOf: datA))
        let decodedB = try WindowInstanceCodec.decode(try Data(contentsOf: datB))
        #expect(decodedA.samples == samplesA, "Migrated archive must round-trip exactly (element-wise), verbatim, no plateau-collapse")
        #expect(decodedB.samples == samplesB, "Migrated archive must round-trip exactly (element-wise), verbatim, no plateau-collapse")
    }

    @Test func idempotentSecondRunChangesNothing() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let samples = makeSamples(count: 8, startEpoch: 1_700_000_000)
        try writeLegacyArchive(history: history, identity: "18000", filename: "2026-01-01T0000Z_2026-01-01T0500Z.json.lzma", samples: samples)

        let first = await history.migrateLegacyArchives()
        #expect(first.migratedCount == 1)

        let identityDir = history.archiveDirectory.appendingPathComponent("18000")
        let fm = FileManager.default
        let filesAfterFirst = try fm.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        let contentsAfterFirst = try filesAfterFirst.map { try Data(contentsOf: $0) }

        let second = await history.migrateLegacyArchives()
        #expect(second == .none, "Second run must find nothing left to migrate — a true no-op")

        let filesAfterSecond = try fm.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil).sorted { $0.path < $1.path }
        let contentsAfterSecond = try filesAfterSecond.map { try Data(contentsOf: $0) }
        #expect(filesAfterFirst.map(\.lastPathComponent) == filesAfterSecond.map(\.lastPathComponent), "Running twice must not change which files exist")
        #expect(contentsAfterFirst == contentsAfterSecond, "Running twice must not change file contents")
    }

    @Test func noOpWhenNoLegacyArchivesPresent() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let identityDir = history.archiveDirectory.appendingPathComponent("18000")
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let datURL = identityDir.appendingPathComponent("2026-01-01T0000Z_2026-01-01T0500Z.\(Constants.History.windowInstanceFileExtension)")
        let encoded = try WindowInstanceCodec.encode(id: UUID(), resetsAt: nil, firstObservedAt: Date(timeIntervalSince1970: 1_700_000_000), events: [], samples: makeSamples(count: 3, startEpoch: 1_700_000_000))
        try encoded.write(to: datURL)
        let contentsBefore = try Data(contentsOf: datURL)

        let result = await history.migrateLegacyArchives()

        #expect(result == .none, "No legacy artifacts present must be a cheap, total no-op")
        let contentsAfter = try Data(contentsOf: datURL)
        #expect(contentsBefore == contentsAfter, "The existing current-format file must not be rewritten")
    }

    @Test func mixedDirectoryOnlyMigratesLegacyFiles() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let identityDir = history.archiveDirectory.appendingPathComponent("18000")
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)

        let existingDatURL = identityDir.appendingPathComponent("2020-01-01T0000Z_2020-01-01T0500Z.\(Constants.History.windowInstanceFileExtension)")
        let existingSamples = makeSamples(count: 2, startEpoch: 1_577_836_800)
        let existingEncoded = try WindowInstanceCodec.encode(id: UUID(), resetsAt: nil, firstObservedAt: Date(timeIntervalSince1970: 1_577_836_800), events: [], samples: existingSamples)
        try existingEncoded.write(to: existingDatURL)

        let legacySamples = makeSamples(count: 6, startEpoch: 1_700_000_000)
        try writeLegacyArchive(history: history, identity: "18000", filename: "2026-01-01T0000Z_2026-01-01T0500Z.json.lzma", samples: legacySamples)

        let result = await history.migrateLegacyArchives()

        #expect(result.migratedCount == 1)
        #expect(result.quarantinedCount == 0)

        let existingAfter = try Data(contentsOf: existingDatURL)
        #expect(existingAfter == existingEncoded, "A pre-existing current-format archive must never be rewritten by migration")

        let migratedDatURL = identityDir.appendingPathComponent("2026-01-01T0000Z_2026-01-01T0500Z.\(Constants.History.windowInstanceFileExtension)")
        let migratedDecoded = try WindowInstanceCodec.decode(try Data(contentsOf: migratedDatURL))
        #expect(migratedDecoded.samples == legacySamples)
    }

    @Test func unparseableFilenameIsNeverDeleted() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let unparseableName = "not-a-valid-window-span-name.json.lzma"
        let url = try writeLegacyArchive(history: history, identity: "18000", filename: unparseableName, samples: makeSamples(count: 4, startEpoch: 1_700_000_000))
        let contentsBefore = try Data(contentsOf: url)

        let result = await history.migrateLegacyArchives()

        #expect(result.migratedCount == 0)
        #expect(result.skippedUnparseableCount == 1)
        #expect(result.quarantinedCount == 0)
        #expect(FileManager.default.fileExists(atPath: url.path), "A legacy archive whose filename span cannot be parsed must never be deleted")
        let contentsAfter = try Data(contentsOf: url)
        #expect(contentsBefore == contentsAfter, "An unparseable-name legacy archive must be left byte-for-byte untouched (not even quarantined)")
    }

    @Test func undecodableArchiveIsQuarantinedWhileOthersStillMigrate() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let goodSamples = makeSamples(count: 5, startEpoch: 1_700_000_000)
        let goodName = "2026-01-01T0000Z_2026-01-01T0500Z.json.lzma"
        try writeLegacyArchive(history: history, identity: "18000", filename: goodName, samples: goodSamples)

        let badName = "2026-03-01T0000Z_2026-03-08T0000Z.json.lzma"
        let badDir = history.archiveDirectory.appendingPathComponent("604800")
        try FileManager.default.createDirectory(at: badDir, withIntermediateDirectories: true)
        let badURL = badDir.appendingPathComponent(badName)
        let badContentsBefore = Data([0xFF, 0x00, 0xDE, 0xAD, 0xBE, 0xEF])
        try badContentsBefore.write(to: badURL)

        let result = await history.migrateLegacyArchives()

        #expect(result.migratedCount == 1, "The good archive in the SAME run must still migrate — one bad file must not block another")
        #expect(result.quarantinedCount == 1)

        let goodDat = history.archiveDirectory.appendingPathComponent("18000")
            .appendingPathComponent("2026-01-01T0000Z_2026-01-01T0500Z.\(Constants.History.windowInstanceFileExtension)")
        #expect(FileManager.default.fileExists(atPath: goodDat.path))
        let goodDecoded = try WindowInstanceCodec.decode(try Data(contentsOf: goodDat))
        #expect(goodDecoded.samples == goodSamples)

        #expect(!FileManager.default.fileExists(atPath: badURL.path), "The undecodable archive must no longer sit at its original path")
        let fm = FileManager.default
        let siblings = try fm.contentsOfDirectory(at: badDir, includingPropertiesForKeys: nil)
        let quarantinedURL = try #require(siblings.first {
            UsageHistory.isQuarantineFile($0) && $0.deletingPathExtension().lastPathComponent == badURL.lastPathComponent
        })
        #expect(try Data(contentsOf: quarantinedURL) == badContentsBefore, "The undecodable archive's bytes must be preserved verbatim under quarantine")
    }

    // MARK: - Real fixtures (RealV2Fixtures.swift)

    @Test func migratesRealLegacyLZMAFixturesExactly() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let smallestData = try #require(Data(base64Encoded: RealV2Fixtures.legacyLZMASmallestBase64))
        let weeklyData = try #require(Data(base64Encoded: RealV2Fixtures.legacyLZMAWeeklyWithRealCreditBase64))

        let smallestName = "2026-06-07T1130Z_2026-06-07T1630Z.json.lzma"
        let weeklyName = "2026-07-11T2048Z_2026-07-18T1959Z.json.lzma"

        let smallestDir = history.archiveDirectory.appendingPathComponent("18000")
        try FileManager.default.createDirectory(at: smallestDir, withIntermediateDirectories: true)
        try smallestData.write(to: smallestDir.appendingPathComponent(smallestName))

        let weeklyDir = history.archiveDirectory.appendingPathComponent("604800")
        try FileManager.default.createDirectory(at: weeklyDir, withIntermediateDirectories: true)
        try weeklyData.write(to: weeklyDir.appendingPathComponent(weeklyName))

        let result = await history.migrateLegacyArchives()

        #expect(result.migratedCount == 2)
        #expect(result.quarantinedCount == 0)

        let smallestDat = smallestDir.appendingPathComponent("2026-06-07T1130Z_2026-06-07T1630Z.\(Constants.History.windowInstanceFileExtension)")
        let weeklyDat = weeklyDir.appendingPathComponent("2026-07-11T2048Z_2026-07-18T1959Z.\(Constants.History.windowInstanceFileExtension)")

        let smallestDecoded = try WindowInstanceCodec.decode(try Data(contentsOf: smallestDat))
        #expect(smallestDecoded.samples.count == 79)
        #expect(smallestDecoded.samples.first == UtilizationSample(utilization: 0, timestamp: Date(timeIntervalSince1970: 1_780_831_803)))
        #expect(smallestDecoded.samples.last == UtilizationSample(utilization: 18, timestamp: Date(timeIntervalSince1970: 1_780_849_765)))

        let weeklyDecoded = try WindowInstanceCodec.decode(try Data(contentsOf: weeklyDat))
        #expect(weeklyDecoded.samples.count == 1554)
        #expect(weeklyDecoded.samples.first == UtilizationSample(utilization: 0, timestamp: Date(timeIntervalSince1970: 1_783_802_921)))
        #expect(weeklyDecoded.samples.last == UtilizationSample(utilization: 5, timestamp: Date(timeIntervalSince1970: 1_784_241_425)))
    }

    // MARK: - Defect 1: pre-existing target is verified, never trusted on existence alone

    @Test func corruptTargetIsQuarantinedAndGoodLegacyDataBecomesAuthoritative_zeroLength() async throws {
        try await assertCorruptTargetIsReplacedByGoodLegacyData(corruptTargetContents: Data())
    }

    @Test func corruptTargetIsQuarantinedAndGoodLegacyDataBecomesAuthoritative_truncated() async throws {
        let validButUnrelated = try WindowInstanceCodec.encode(
            id: UUID(), resetsAt: nil, firstObservedAt: Date(timeIntervalSince1970: 1_650_000_000),
            events: [], samples: makeSamples(count: 6, startEpoch: 1_650_000_000)
        )
        // Long enough to clear the codec's too-short-for-CRC guard, so it fails as a CRC mismatch.
        try await assertCorruptTargetIsReplacedByGoodLegacyData(corruptTargetContents: validButUnrelated.prefix(validButUnrelated.count - 6))
    }

    @Test func corruptTargetIsQuarantinedAndGoodLegacyDataBecomesAuthoritative_bitRotted() async throws {
        var validButUnrelated = try WindowInstanceCodec.encode(
            id: UUID(), resetsAt: nil, firstObservedAt: Date(timeIntervalSince1970: 1_650_000_000),
            events: [], samples: makeSamples(count: 6, startEpoch: 1_650_000_000)
        )
        // Byte inside the CRC-covered body, not the trailing CRC field itself.
        validButUnrelated[validButUnrelated.index(validButUnrelated.startIndex, offsetBy: validButUnrelated.count - 8)] ^= 0xFF
        try await assertCorruptTargetIsReplacedByGoodLegacyData(corruptTargetContents: validButUnrelated)
    }

    private func assertCorruptTargetIsReplacedByGoodLegacyData(corruptTargetContents: Data) async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let goodSamples = makeSamples(count: 9, startEpoch: 1_700_000_000)
        let span = "2026-01-01T0000Z_2026-01-01T0500Z"
        try writeLegacyArchive(history: history, identity: "18000", filename: "\(span).json.lzma", samples: goodSamples)

        let identityDir = history.archiveDirectory.appendingPathComponent("18000")
        let targetURL = identityDir.appendingPathComponent("\(span).\(Constants.History.windowInstanceFileExtension)")
        try corruptTargetContents.write(to: targetURL)
        let targetDecodesToNonEmptySamples = (try? WindowInstanceCodec.decode(corruptTargetContents).samples.isEmpty) == false
        #expect(!targetDecodesToNonEmptySamples, "Test setup bug: the 'corrupt' target must not actually decode to non-empty samples")

        let result = await history.migrateLegacyArchives()

        #expect(result.migratedCount == 1, "The good legacy file must still be migrated once the corrupt target is out of the way")
        #expect(result.corruptTargetQuarantinedCount == 1, "The CORRUPT TARGET must be quarantined and counted distinctly from an ordinary quarantined legacy file")
        #expect(result.quarantinedCount == 0, "No LEGACY file was quarantined here — only the corrupt target — so this must stay 0")
        #expect(result.conflictCount == 0)
        #expect(result.failedWriteCount == 0)

        let legacyURL = identityDir.appendingPathComponent("\(span).json.lzma")
        #expect(!FileManager.default.fileExists(atPath: legacyURL.path), "The good legacy original must have been consumed by a successful migration, not left in place")

        #expect(FileManager.default.fileExists(atPath: targetURL.path))
        let finalDecoded = try WindowInstanceCodec.decode(try Data(contentsOf: targetURL))
        #expect(finalDecoded.samples == goodSamples, "The good legacy data must end up authoritative at the target path")

        let siblings = try FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil)
        let quarantinedTarget = try #require(siblings.first {
            UsageHistory.isQuarantineFile($0) && $0.deletingPathExtension().lastPathComponent == targetURL.lastPathComponent
        })
        #expect(try Data(contentsOf: quarantinedTarget) == corruptTargetContents, "The corrupt target's original bytes must be preserved verbatim under quarantine")
    }

    /// A readable target that disagrees with the legacy data is a conflict, not corruption:
    /// neither file is touched rather than guessing which is right.
    @Test func conflictingTargetLeavesBothFilesUntouched() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let legacySamples = makeSamples(count: 5, startEpoch: 1_700_000_000)
        let span = "2026-01-01T0000Z_2026-01-01T0500Z"
        try writeLegacyArchive(history: history, identity: "18000", filename: "\(span).json.lzma", samples: legacySamples)

        let identityDir = history.archiveDirectory.appendingPathComponent("18000")
        let targetURL = identityDir.appendingPathComponent("\(span).\(Constants.History.windowInstanceFileExtension)")
        let differentSamples = makeSamples(count: 3, startEpoch: 1_800_000_000)
        let targetEncoded = try WindowInstanceCodec.encode(id: UUID(), resetsAt: nil, firstObservedAt: Date(timeIntervalSince1970: 1_800_000_000), events: [], samples: differentSamples)
        try targetEncoded.write(to: targetURL)

        let legacyContentsBefore = try Data(contentsOf: identityDir.appendingPathComponent("\(span).json.lzma"))

        let result = await history.migrateLegacyArchives()

        #expect(result.conflictCount == 1)
        #expect(result.migratedCount == 0)
        #expect(result.quarantinedCount == 0)

        let legacyURL = identityDir.appendingPathComponent("\(span).json.lzma")
        #expect(FileManager.default.fileExists(atPath: legacyURL.path), "The legacy original must be left in place on a genuine conflict")
        #expect(try Data(contentsOf: legacyURL) == legacyContentsBefore, "The legacy original must be byte-for-byte untouched")
        #expect(try Data(contentsOf: targetURL) == targetEncoded, "The target must be byte-for-byte untouched")
    }

    // MARK: - Defect 1: a failed quarantine attempt must never be followed by a write/remove

    @Test func failedQuarantineOfCorruptTargetLeavesBothFilesUntouchedAndCounted() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let goodSamples = makeSamples(count: 5, startEpoch: 1_700_000_000)
        let span = "2026-01-01T0000Z_2026-01-01T0500Z"
        try writeLegacyArchive(history: history, identity: "18000", filename: "\(span).json.lzma", samples: goodSamples)

        let identityDir = history.archiveDirectory.appendingPathComponent("18000")
        let targetURL = identityDir.appendingPathComponent("\(span).\(Constants.History.windowInstanceFileExtension)")
        try Data().write(to: targetURL)

        let legacyURL = identityDir.appendingPathComponent("\(span).json.lzma")
        let legacyContentsBefore = try Data(contentsOf: legacyURL)

        let fm = FileManager.default
        // Denies the quarantine rename.
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: identityDir.path)
        // Must restore: a read-only directory left behind wedges the next run's test-root sweep.
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: identityDir.path)
        }

        let result = await history.migrateLegacyArchives()

        #expect(result.quarantineFailedCount == 1, "The failed quarantine attempt must be counted, never silently ignored")
        #expect(result.corruptTargetQuarantinedCount == 0, "Quarantine did not actually succeed, so this must stay 0")
        #expect(result.migratedCount == 0, "Must NOT fall through to the shared write path and overwrite the corrupt target")
        #expect(result.quarantinedCount == 0)

        let targetAfter = try Data(contentsOf: targetURL)
        #expect(targetAfter.isEmpty, "The corrupt target must be left exactly as it was — never overwritten when its quarantine failed")
        let legacyAfter = try Data(contentsOf: legacyURL)
        #expect(legacyAfter == legacyContentsBefore, "The legacy original must be left completely untouched when the target's quarantine failed")
    }

    @Test func failedQuarantineOfUndecodableLegacyFileLeavesItInPlaceAndCounted() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let identityDir = history.archiveDirectory.appendingPathComponent("18000")
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let badURL = identityDir.appendingPathComponent("2026-03-01T0000Z_2026-03-08T0000Z.json.lzma")
        let badContentsBefore = Data([0xFF, 0x00, 0xDE, 0xAD, 0xBE, 0xEF])
        try badContentsBefore.write(to: badURL)

        let fm = FileManager.default
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: identityDir.path)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: identityDir.path)
        }

        let result = await history.migrateLegacyArchives()

        #expect(result.quarantineFailedCount == 1, "The failed quarantine attempt must be counted")
        #expect(result.quarantinedCount == 0, "Quarantine did not actually succeed, so this must stay 0")
        #expect(result.migratedCount == 0)

        let contentsAfter = try Data(contentsOf: badURL)
        #expect(contentsAfter == badContentsBefore, "The undecodable legacy file must be left byte-for-byte in place when its quarantine failed")
    }

    // MARK: - Defect 2: concurrent migrateLegacyArchives() calls are coalesced, never doubled

    @Test func concurrentMigrationCallsCoalesceIntoOneRun() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let samples = makeSamples(count: 6, startEpoch: 1_700_000_000)
        try writeLegacyArchive(history: history, identity: "18000", filename: "2026-01-01T0000Z_2026-01-01T0500Z.json.lzma", samples: samples)

        async let first = history.migrateLegacyArchives()
        async let second = history.migrateLegacyArchives()
        let (resultA, resultB) = await (first, second)

        // One file: an uncoalesced second run would find nothing (`.none`) and disagree with the first.
        #expect(resultA == resultB, "Concurrent calls must coalesce onto the same run rather than each independently migrating (or racing over) the same files")
        #expect(resultA.migratedCount == 1)

        let identityDir = history.archiveDirectory.appendingPathComponent("18000")
        let datURL = identityDir.appendingPathComponent("2026-01-01T0000Z_2026-01-01T0500Z.\(Constants.History.windowInstanceFileExtension)")
        #expect(FileManager.default.fileExists(atPath: datURL.path))
        let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: datURL))
        #expect(decoded.samples == samples)
    }

    // MARK: - Prune/migration structural exclusion

    /// Prune must wait for the migration: it could otherwise delete a past-retention legacy file
    /// before its replacement is written and verified.
    @Test func pruneWaitsForInFlightMigrationBeforeDeletingLegacyFile() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let years = 2
        let cutoff = try #require(UsageHistory.retentionCutoff(years: years, now: now))
        let end = cutoff.addingTimeInterval(-3600)
        let start = end.addingTimeInterval(-18000)
        let formatter = UsageHistory.archiveDateFormatter
        let legacyName = "\(formatter.string(from: start))_\(formatter.string(from: end)).json.lzma"
        let legacyURL = try writeLegacyArchive(history: history, identity: "18000", filename: legacyName, samples: makeSamples(count: 4, startEpoch: 1_700_000_000))

        let (stream, continuation) = AsyncStream<Void>.makeStream()
        history.inFlightLegacyMigration = Task<LegacyArchiveMigrationResult, Never> {
            for await _ in stream { break }
            return .none
        }

        let pruneTask = Task { await history.pruneArchives(retentionYears: years, now: now) }

        // Time for a wrongly unblocked prune to delete the file.
        try await Task.sleep(for: .milliseconds(200))
        #expect(FileManager.default.fileExists(atPath: legacyURL.path), "Prune must not delete a past-retention legacy archive while a migration is still in flight over the same directory")

        continuation.finish()
        await pruneTask.value

        #expect(!FileManager.default.fileExists(atPath: legacyURL.path), "Once the in-flight migration finishes, prune must proceed and delete the past-retention legacy archive")
    }

    // MARK: - Multi-file realism (developer's real corpus: 11 five-hour + 1 weekly)

    @Test func realisticMultiFileRunProducesIndependentPerFileOutcomes() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let smallestData = try #require(Data(base64Encoded: RealV2Fixtures.legacyLZMASmallestBase64))
        let weeklyData = try #require(Data(base64Encoded: RealV2Fixtures.legacyLZMAWeeklyWithRealCreditBase64))

        let fiveHourDir = history.archiveDirectory.appendingPathComponent("18000")
        try FileManager.default.createDirectory(at: fiveHourDir, withIntermediateDirectories: true)

        var goodFiveHourNames: [String] = []
        for day in 1...9 {
            let name = String(format: "2026-06-%02dT1130Z_2026-06-%02dT1630Z.json.lzma", day, day)
            try smallestData.write(to: fiveHourDir.appendingPathComponent(name))
            goodFiveHourNames.append(name)
        }
        let badName = "2026-06-10T1130Z_2026-06-10T1630Z.json.lzma"
        try Data([0xDE, 0xAD, 0xBE, 0xEF]).write(to: fiveHourDir.appendingPathComponent(badName))
        let unparseableName = "not-a-window-span.json.lzma"
        try smallestData.write(to: fiveHourDir.appendingPathComponent(unparseableName))

        let weeklyDir = history.archiveDirectory.appendingPathComponent("604800")
        try FileManager.default.createDirectory(at: weeklyDir, withIntermediateDirectories: true)
        let weeklyName = "2026-07-11T2048Z_2026-07-18T1959Z.json.lzma"
        try weeklyData.write(to: weeklyDir.appendingPathComponent(weeklyName))

        let result = await history.migrateLegacyArchives()

        #expect(result.migratedCount == 10, "9 good five-hour + 1 good weekly")
        #expect(result.quarantinedCount == 1, "The one undecodable five-hour archive")
        #expect(result.skippedUnparseableCount == 1, "The one unparseable-filename five-hour archive")
        #expect(result.conflictCount == 0)
        #expect(result.failedWriteCount == 0)

        for name in goodFiveHourNames {
            let stem = String(name.dropLast(".json.lzma".count))
            let datURL = fiveHourDir.appendingPathComponent("\(stem).\(Constants.History.windowInstanceFileExtension)")
            #expect(FileManager.default.fileExists(atPath: datURL.path), "\(name) must have migrated to \(stem).dat")
            #expect(!FileManager.default.fileExists(atPath: fiveHourDir.appendingPathComponent(name).path), "\(name)'s legacy original must be gone")
            let decoded = try WindowInstanceCodec.decode(try Data(contentsOf: datURL))
            #expect(decoded.samples.count == 79, "\(name) must round-trip the real fixture's 79 samples")
        }

        #expect(!FileManager.default.fileExists(atPath: fiveHourDir.appendingPathComponent(badName).path))
        let badSiblings = try FileManager.default.contentsOfDirectory(at: fiveHourDir, includingPropertiesForKeys: nil)
        #expect(badSiblings.contains { UsageHistory.isQuarantineFile($0) && $0.deletingPathExtension().lastPathComponent == badName })

        #expect(FileManager.default.fileExists(atPath: fiveHourDir.appendingPathComponent(unparseableName).path))
        #expect(try Data(contentsOf: fiveHourDir.appendingPathComponent(unparseableName)) == smallestData)

        let weeklyDat = weeklyDir.appendingPathComponent("2026-07-11T2048Z_2026-07-18T1959Z.\(Constants.History.windowInstanceFileExtension)")
        #expect(FileManager.default.fileExists(atPath: weeklyDat.path))
        #expect(!FileManager.default.fileExists(atPath: weeklyDir.appendingPathComponent(weeklyName).path))
        let weeklyDecoded = try WindowInstanceCodec.decode(try Data(contentsOf: weeklyDat))
        #expect(weeklyDecoded.samples.count == 1554)
    }

    // MARK: - End-to-end v2 -> v3 live file (load() -> save() -> decode)

    @Test func realV2LiveFileSurvivesLoadThenSaveRoundTripUnchanged() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)

        let v2Data = try #require(Data(base64Encoded: RealV2Fixtures.liveV2Base64))
        let originalDecoded = try WindowInstanceCodec.decode(v2Data)

        let liveDir = history.liveDirectory
        try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
        let identity = "18000"
        let liveURL = liveDir.appendingPathComponent("\(identity).\(Constants.History.windowInstanceFileExtension)")
        try v2Data.write(to: liveURL)

        history.load()
        let loadedSamples = try #require(history.storage[identity]?.samples, "load() must read the real v2 file into storage")
        #expect(loadedSamples.count == originalDecoded.samples.count, "load() must read every sample out of the real v2 file")
        #expect(loadedSamples == originalDecoded.samples)

        await history.save()

        let resaved = try Data(contentsOf: liveURL)
        let resavedDecoded = try WindowInstanceCodec.decode(resaved)
        #expect(resavedDecoded.samples == originalDecoded.samples, "The sample sequence must survive load() -> save() unchanged")
        #expect(resavedDecoded.id == originalDecoded.id)
        #expect(resavedDecoded.resetsAt == originalDecoded.resetsAt)
        #expect(resavedDecoded.firstObservedAt == originalDecoded.firstObservedAt)
    }
}
