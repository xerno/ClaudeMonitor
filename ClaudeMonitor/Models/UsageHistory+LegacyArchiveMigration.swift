import Foundation

/// Deliberately not surfaced in the UI (product decision, do not add): the user cannot act on a
/// storage migration. So `conflictCount` and `quarantineFailedCount`, which need a human, are
/// visible only to tests and debuggers.
struct LegacyArchiveMigrationResult: Sendable, Equatable {
    static let none = LegacyArchiveMigrationResult()

    let migratedCount: Int
    /// Legacy archives quarantined for failing to decode, failing round-trip verification, or
    /// being duplicated by a verified target. Never a quarantined target: see
    /// `corruptTargetQuarantinedCount`.
    let quarantinedCount: Int
    /// Retention depends on the `<start>_<end>` filename span, so a file with an unparseable one
    /// is never renamed, quarantined or removed.
    let skippedUnparseableCount: Int
    /// Current-format write failed; the legacy original is untouched and retried next run.
    let failedWriteCount: Int
    /// A valid target's samples differ from the legacy original's. Never auto-resolved, both
    /// files untouched: quarantining the original could lose data the target lacks, overwriting
    /// the target could lose data placed there by an out-of-band recovery.
    let conflictCount: Int
    /// Pre-existing target quarantined because it failed to decode or held zero samples. The
    /// legacy original is then migrated normally and counted in `migratedCount`.
    let corruptTargetQuarantinedCount: Int
    /// A quarantine rename failed (legacy original or corrupt target); the file is untouched
    /// and retried next run.
    let quarantineFailedCount: Int

    init(migratedCount: Int = 0, quarantinedCount: Int = 0, skippedUnparseableCount: Int = 0, failedWriteCount: Int = 0, conflictCount: Int = 0, corruptTargetQuarantinedCount: Int = 0, quarantineFailedCount: Int = 0) {
        self.migratedCount = migratedCount
        self.quarantinedCount = quarantinedCount
        self.skippedUnparseableCount = skippedUnparseableCount
        self.failedWriteCount = failedWriteCount
        self.conflictCount = conflictCount
        self.corruptTargetQuarantinedCount = corruptTargetQuarantinedCount
        self.quarantineFailedCount = quarantineFailedCount
    }
}

extension UsageHistory {
    private struct LegacyFile: Sendable {
        let url: URL
        let targetURL: URL?
    }

    private nonisolated static func hasLegacyArchives(archiveBase: URL) -> Bool {
        guard let identityDirs = try? FileManager.default.contentsOfDirectory(at: archiveBase, includingPropertiesForKeys: nil) else { return false }
        for identityDir in identityDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil) else { continue }
            if files.contains(where: { hasSuffixCaseInsensitive($0.lastPathComponent, Constants.History.legacyArchiveSuffix) }) { return true }
        }
        return false
    }

    /// Span parseability must match retention's `collectArchiveFiles` (start component unvalidated).
    private nonisolated static func collectLegacyFiles(archiveBase: URL) -> [LegacyFile] {
        guard let identityDirs = try? FileManager.default.contentsOfDirectory(at: archiveBase, includingPropertiesForKeys: nil) else { return [] }
        let formatter = UsageHistory.archiveDateFormatter
        var result: [LegacyFile] = []
        for identityDir in identityDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil) else { continue }
            for file in files where hasSuffixCaseInsensitive(file.lastPathComponent, Constants.History.legacyArchiveSuffix) {
                let stem = String(file.lastPathComponent.dropLast(Constants.History.legacyArchiveSuffix.count))
                let parts = stem.split(separator: "_", maxSplits: 1).map(String.init)
                let target: URL?
                if parts.count == 2, formatter.date(from: parts[1]) != nil {
                    target = identityDir.appendingPathComponent("\(stem).\(Constants.History.windowInstanceFileExtension)")
                } else {
                    target = nil
                }
                result.append(LegacyFile(url: file, targetURL: target))
            }
        }
        return result
    }

    /// Not `URL?`: call sites must switch exhaustively, so a failed quarantine can't pass as a success.
    private enum QuarantineAttempt: Sendable {
        case quarantined(URL)
        case failed
    }

    /// Same naming as the live-directory `quarantine`, so `isQuarantineFile`/`quarantineTimestamp`
    /// recognise the file and retention ages it out.
    private nonisolated static func quarantineArchiveFile(_ file: URL) -> QuarantineAttempt {
        let fm = FileManager.default
        let timestamp = archiveDateFormatter.string(from: Date())
        var candidate = file.appendingPathExtension("\(Constants.History.quarantinePrefix)\(timestamp)")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = file.appendingPathExtension("\(Constants.History.quarantinePrefix)\(timestamp)-\(suffix)")
            suffix += 1
        }
        do {
            try fm.moveItem(at: file, to: candidate)
            return .quarantined(candidate)
        } catch {
            return .failed
        }
    }

    /// Not for targets: a failed target quarantine must abort that file's migration.
    private nonisolated static func quarantineLegacyAndCount(
        _ url: URL, quarantinedCount: inout Int, quarantineFailedCount: inout Int
    ) {
        switch quarantineArchiveFile(url) {
        case .quarantined:
            quarantinedCount += 1
        case .failed:
            quarantineFailedCount += 1
        }
    }

    /// One-time migration of legacy `.json.lzma` archives to v3; a no-op once none remain, so safe
    /// on every launch.
    ///
    /// Samples migrate verbatim, without plateau-collapse, so the round-trip check is plain
    /// element-wise equality; a weaker equivalence isn't worth staking irreplaceable data on.
    ///
    /// The legacy original is removed only after its verified replacement is atomically written,
    /// so no backup is needed. A crash or failed removal leaves the original alone (retried next
    /// run) or both files (the existing-target branch finishes the cleanup). A target is never
    /// trusted on existence alone.
    func migrateLegacyArchives() async -> LegacyArchiveMigrationResult {
        if let existing = inFlightLegacyMigration {
            return await existing.value
        }
        // Wait for a running prune sweep so it can't delete a legacy file this migration is
        // still reading or hasn't yet replaced.
        if let inFlightPruneTask = inFlightPrune {
            await inFlightPruneTask.value
        }
        let archiveBase = archiveDirectory
        let task = Task<LegacyArchiveMigrationResult, Never> {
            await Self.runLegacyArchiveMigration(archiveBase: archiveBase)
        }
        inFlightLegacyMigration = task
        let result = await task.value
        inFlightLegacyMigration = nil
        return result
    }

    private nonisolated static func runLegacyArchiveMigration(archiveBase: URL) async -> LegacyArchiveMigrationResult {
        await Task.detached {
            let fm = FileManager.default

            guard UsageHistory.hasLegacyArchives(archiveBase: archiveBase) else { return .none }

            let legacyFiles = UsageHistory.collectLegacyFiles(archiveBase: archiveBase)
            var migratedCount = 0
            var quarantinedCount = 0
            var skippedUnparseableCount = 0
            var failedWriteCount = 0
            var conflictCount = 0
            var corruptTargetQuarantinedCount = 0
            var quarantineFailedCount = 0

            for legacy in legacyFiles {
                guard let target = legacy.targetURL else {
                    skippedUnparseableCount += 1
                    continue
                }

                if fm.fileExists(atPath: target.path) {
                    let targetVerified: DecodedWindowInstance? = {
                        guard let targetData = try? Data(contentsOf: target),
                              let targetDecoded = try? WindowInstanceCodec.decode(targetData),
                              !targetDecoded.samples.isEmpty else { return nil }
                        return targetDecoded
                    }()

                    if let targetVerified {
                        guard let legacyData = try? Data(contentsOf: legacy.url),
                              let legacyDecoded = try? WindowInstanceCodec.decode(legacyData) else {
                            UsageHistory.quarantineLegacyAndCount(legacy.url, quarantinedCount: &quarantinedCount, quarantineFailedCount: &quarantineFailedCount)
                            continue
                        }

                        if legacyDecoded.samples == targetVerified.samples {
                            UsageHistory.quarantineLegacyAndCount(legacy.url, quarantinedCount: &quarantinedCount, quarantineFailedCount: &quarantineFailedCount)
                        } else {
                            conflictCount += 1
                        }
                        continue
                    }

                    // Corrupt or empty target: quarantine it, then migrate normally. On failure do not
                    // fall through: the atomic write below would silently overwrite the corrupt bytes.
                    switch UsageHistory.quarantineArchiveFile(target) {
                    case .quarantined:
                        corruptTargetQuarantinedCount += 1
                    case .failed:
                        quarantineFailedCount += 1
                        continue
                    }
                }

                guard let data = try? Data(contentsOf: legacy.url),
                      let decoded = try? WindowInstanceCodec.decode(data) else {
                    UsageHistory.quarantineLegacyAndCount(legacy.url, quarantinedCount: &quarantinedCount, quarantineFailedCount: &quarantineFailedCount)
                    continue
                }

                guard let encoded = try? WindowInstanceCodec.encode(
                        id: decoded.id,
                        resetsAt: decoded.resetsAt,
                        firstObservedAt: decoded.firstObservedAt,
                        events: decoded.events,
                        samples: decoded.samples
                      ),
                      let reDecoded = try? WindowInstanceCodec.decode(encoded),
                      reDecoded.samples == decoded.samples else {
                    UsageHistory.quarantineLegacyAndCount(legacy.url, quarantinedCount: &quarantinedCount, quarantineFailedCount: &quarantineFailedCount)
                    continue
                }

                do {
                    try encoded.write(to: target, options: .atomic)
                } catch {
                    failedWriteCount += 1
                    continue
                }

                // Best-effort: if removal fails, the next run's target verification finishes the cleanup.
                try? fm.removeItem(at: legacy.url)
                migratedCount += 1
            }

            return LegacyArchiveMigrationResult(
                migratedCount: migratedCount,
                quarantinedCount: quarantinedCount,
                skippedUnparseableCount: skippedUnparseableCount,
                failedWriteCount: failedWriteCount,
                conflictCount: conflictCount,
                corruptTargetQuarantinedCount: corruptTargetQuarantinedCount,
                quarantineFailedCount: quarantineFailedCount
            )
        }.value
    }
}
