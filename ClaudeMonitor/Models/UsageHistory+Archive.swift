import Foundation

extension UsageHistory {
    /// Migration and retention must agree on case variants, or a `.JSON.LZMA` file would be
    /// invisible to both and never migrated or deleted.
    nonisolated static func hasSuffixCaseInsensitive(_ name: String, _ suffix: String) -> Bool {
        name.lowercased().hasSuffix(suffix.lowercased())
    }

    /// Archive/quarantine filename format, not user-visible.
    ///
    /// `locale` must stay `en_US_POSIX`: without it `Locale.current` governs the calendar and
    /// numbering system even with an explicit `dateFormat`.
    /// - Non-ASCII digits make `date(from:)` fail on existing names, so `collectArchiveFiles`
    ///   skips the archive and retention never sees it.
    /// - A non-Gregorian calendar (Thai Buddhist) parses the same digits as another date
    ///   (2026 is Gregorian 1483), so `retentionCutoff` sees the archive as centuries old
    ///   and deletes it.
    ///
    /// `timeZone` is pinned to UTC because the format's `Z` is a literal.
    nonisolated static let archiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HHmm'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Lossless under step and linear interpolation: the dropped points are collinear.
    /// Never collapses across a gap >= `gapThreshold`: the app wasn't running, and the graph
    /// must show the discontinuity. Archive-only: the live instance feeds rate/EMA/projection
    /// and must stay dense.
    nonisolated static func collapsePlateaus(_ samples: [UtilizationSample], gapThreshold: TimeInterval) -> [UtilizationSample] {
        guard let first = samples.first else { return [] }
        var result: [UtilizationSample] = []
        var runStart = first
        var runLast = first
        for sample in samples.dropFirst() {
            let sameValue = sample.utilization == runLast.utilization
            let smallGap = sample.timestamp.timeIntervalSince(runLast.timestamp) < gapThreshold
            if sameValue && smallGap {
                runLast = sample
                continue
            }
            result.append(runStart)
            if runLast.timestamp != runStart.timestamp {
                result.append(runLast)
            }
            runStart = sample
            runLast = sample
        }
        result.append(runStart)
        if runLast.timestamp != runStart.timestamp {
            result.append(runLast)
        }
        return result
    }

    /// Applies `replacement` only if no `clearAll()`/`switchOrganization()` has bumped
    /// `generation` since the caller captured it.
    /// Separate and non-async so tests can pin the guard with a stale `capturedGeneration`;
    /// the race it protects against can't be reproduced reliably by timing.
    @discardableResult
    func applyArchiveReplacement(_ replacement: WindowInstance?, forIdentity identity: String, capturedGeneration: Int) -> Bool {
        guard generation == capturedGeneration else { return false }
        storage[identity] = replacement
        return true
    }

    /// Archives the stored instance for `identity` (if non-empty), then installs `replacement`;
    /// `nil` leaves the identity absent.
    ///
    /// Callers must write `storage[identity]` through `replacement`, never after this returns:
    /// `clearAll()`/`switchOrganization()` bump `generation` while the detached write is
    /// suspended, and `replacement` is then discarded instead of resurrecting cleared or
    /// other-organization data.
    @discardableResult
    func archiveWindow(identity: String, resetsAt: Date, windowDuration: TimeInterval, replacingWith replacement: WindowInstance?) async -> Bool {
        let capturedGeneration = generation
        guard let instance = storage[identity], !instance.samples.isEmpty else {
            applyArchiveReplacement(replacement, forIdentity: identity, capturedGeneration: capturedGeneration)
            return false
        }
        let samples = UsageHistory.collapsePlateaus(instance.samples, gapThreshold: Constants.History.gapThreshold)

        let windowEnd = resetsAt
        let windowStart = instance.samples.first?.timestamp ?? resetsAt.addingTimeInterval(-windowDuration)

        let formatter = UsageHistory.archiveDateFormatter
        let startStr = formatter.string(from: windowStart)
        let endStr = formatter.string(from: windowEnd)
        let filename = "\(startStr)_\(endStr).\(Constants.History.windowInstanceFileExtension)"

        let archiveDir = archiveDirectory.appendingPathComponent(identity)
        let archiveURL = archiveDir.appendingPathComponent(filename)

        let id = instance.id
        let firstObservedAt = instance.firstObservedAt
        let events = instance.events
        storage[identity] = nil

        await Task.detached {
            do {
                try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
                let data = try WindowInstanceCodec.encode(
                    id: id,
                    resetsAt: resetsAt,
                    firstObservedAt: firstObservedAt,
                    events: events,
                    samples: samples
                )
                try data.write(to: archiveURL, options: .atomic)
            } catch {
                // Environmental failure: never trap. `storage` is already cleared, so this window's history is lost.
            }
        }.value

        applyArchiveReplacement(replacement, forIdentity: identity, capturedGeneration: capturedGeneration)
        return true
    }

    private struct ArchiveFileEntry: Sendable {
        let url: URL
        let endDate: Date
    }

    /// Archive files with the window-end date parsed from their `<start>_<end>` names. Shared by
    /// `pruneArchives` and `archivedWindowCount` so the two can't disagree.
    private nonisolated static func collectArchiveFiles(archiveBase: URL) -> [ArchiveFileEntry] {
        guard let identityDirs = try? FileManager.default.contentsOfDirectory(at: archiveBase, includingPropertiesForKeys: nil) else { return [] }
        let formatter = UsageHistory.archiveDateFormatter

        let knownSuffixes = [".\(Constants.History.windowInstanceFileExtension)", Constants.History.legacyArchiveSuffix]
        var result: [ArchiveFileEntry] = []
        for identityDir in identityDirs {
            guard let files = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil) else { continue }
            for file in files {
                let lastComponent = file.lastPathComponent
                guard let knownSuffix = knownSuffixes.first(where: { hasSuffixCaseInsensitive(lastComponent, $0) }) else { continue }
                let name = String(lastComponent.dropLast(knownSuffix.count))
                let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
                guard parts.count == 2, let endDate = formatter.date(from: parts[1]) else { continue }
                result.append(ArchiveFileEntry(url: file, endDate: endDate))
            }
        }
        return result
    }

    /// Calendar year arithmetic, not a fixed seconds-per-year, so leap years don't drift the boundary.
    nonisolated static func retentionCutoff(years: Int = Constants.History.retentionYears(), now: Date = Date()) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar.date(byAdding: .year, value: -years, to: now)
    }

    /// Counts only the archives a retention of `years` would delete.
    func archivedWindowCount(retentionYears years: Int, now: Date = Date()) async -> Int {
        guard let cutoff = UsageHistory.retentionCutoff(years: years, now: now) else { return 0 }
        let archiveBase = archiveDirectory
        return await Task.detached {
            UsageHistory.collectArchiveFiles(archiveBase: archiveBase).filter { $0.endDate < cutoff }.count
        }.value
    }

    /// Deletes archives past the retention cutoff, then quarantined files (`pruneQuarantinedFiles`).
    func pruneArchives(retentionYears years: Int = Constants.History.retentionYears(), now: Date = Date()) async {
        // Wait for a running legacy migration over the same directory: a `.json.lzma` file
        // mid-migration must not be deleted out from under it.
        if let inFlightMigration = inFlightLegacyMigration {
            _ = await inFlightMigration.value
        }
        if let existing = inFlightPrune {
            await existing.value
            return
        }
        guard let cutoff = UsageHistory.retentionCutoff(years: years, now: now) else { return }
        let archiveBase = archiveDirectory
        let task = Task<Void, Never> {
            await Task.detached {
                for entry in UsageHistory.collectArchiveFiles(archiveBase: archiveBase) where entry.endDate < cutoff {
                    try? FileManager.default.removeItem(at: entry.url)
                }
                guard let identityDirs = try? FileManager.default.contentsOfDirectory(at: archiveBase, includingPropertiesForKeys: nil) else { return }
                for identityDir in identityDirs {
                    if let remaining = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil),
                       remaining.isEmpty {
                        try? FileManager.default.removeItem(at: identityDir)
                    }
                }
            }.value
        }
        inFlightPrune = task
        await task.value
        inFlightPrune = nil
        await pruneQuarantinedFiles(retentionYears: years, now: now)
    }

    /// Quarantined files in `liveDirectory` and every `archiveDirectory/<identity>/`, including
    /// quarantined archives, which `collectArchiveFiles` doesn't match. `quarantinedAt` comes
    /// from the filename and is `nil` when it carries no timestamp (age unknown).
    private nonisolated static func collectQuarantinedFiles(liveDir: URL, archiveBase: URL) -> [(url: URL, quarantinedAt: Date?)] {
        var result: [(url: URL, quarantinedAt: Date?)] = []
        if let files = try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil) {
            for file in files where isQuarantineFile(file) {
                result.append((url: file, quarantinedAt: quarantineTimestamp(file)))
            }
        }
        if let identityDirs = try? FileManager.default.contentsOfDirectory(at: archiveBase, includingPropertiesForKeys: nil) {
            for identityDir in identityDirs {
                guard let files = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil) else { continue }
                for file in files where isQuarantineFile(file) {
                    result.append((url: file, quarantinedAt: quarantineTimestamp(file)))
                }
            }
        }
        return result
    }

    /// Never deletes a file with `quarantinedAt == nil`: unknown age can't prove the retention
    /// window elapsed, and deleting on a guess is destructive.
    func pruneQuarantinedFiles(retentionYears years: Int = Constants.History.retentionYears(), now: Date = Date()) async {
        guard let cutoff = UsageHistory.retentionCutoff(years: years, now: now) else { return }
        let liveDir = liveDirectory
        let archiveBase = archiveDirectory
        await Task.detached {
            for entry in UsageHistory.collectQuarantinedFiles(liveDir: liveDir, archiveBase: archiveBase) {
                guard let quarantinedAt = entry.quarantinedAt, quarantinedAt < cutoff else { continue }
                try? FileManager.default.removeItem(at: entry.url)
            }
        }.value
    }

    func quarantinedFileCount() async -> Int {
        let liveDir = liveDirectory
        let archiveBase = archiveDirectory
        return await Task.detached {
            UsageHistory.collectQuarantinedFiles(liveDir: liveDir, archiveBase: archiveBase).count
        }.value
    }

    /// Archives live instances whose key has been absent from the API response long enough to be
    /// unambiguous (`Constants.History.missingWindowArchiveMultiplier`). Call only with identities
    /// from a successful, complete fetch: a failed or partial one must never advance the clock.
    func archiveMissingWindows(currentIdentities: Set<String>, at now: Date = Date()) async {
        let before = missingWindowSince

        // Snapshot the keys: archiveWindow() mutates `storage` across the await.
        for identity in Array(storage.keys) where !currentIdentities.contains(identity) {
            guard let firstMissingAt = missingWindowSince[identity] else {
                missingWindowSince[identity] = now
                continue
            }
            guard let duration = WindowEntry.duration(fromStorageIdentity: identity) else { continue }
            let threshold = duration * Constants.History.missingWindowArchiveMultiplier
            guard now.timeIntervalSince(firstMissingAt) >= threshold else { continue }
            guard let instance = storage[identity] else { continue }
            let resetsAt = instance.resetsAt ?? now
            await archiveWindow(identity: identity, resetsAt: resetsAt, windowDuration: duration, replacingWith: nil)
            missingWindowSince[identity] = nil
        }
        for identity in currentIdentities {
            missingWindowSince[identity] = nil
        }

        // Persisted so a restart doesn't reset the clock; otherwise the threshold would need one
        // uninterrupted window duration of runtime.
        if missingWindowSince != before {
            await saveMissingWindowSince()
        }
    }
}
