import Foundation

extension UsageHistory {
    // Legacy (v1) format: bare JSON array `[[epoch,util],...]`. The writer never emits it.
    nonisolated static func encodeCompact(_ samples: [UtilizationSample]) -> Data {
        let pairs = samples.map { "[\(Int($0.timestamp.timeIntervalSince1970)),\($0.utilization)]" }
        let json = "[" + pairs.joined(separator: ",") + "]"
        return Data(json.utf8)
    }

    /// One unparsable `[epoch,util]` pair fails the whole decode (`nil`): the caller must see a
    /// failure and preserve the file, not partial data that looks complete.
    nonisolated static func decodeCompact(_ data: Data) -> [UtilizationSample]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return nil }
        var samples: [UtilizationSample] = []
        samples.reserveCapacity(raw.count)
        for pair in raw {
            guard pair.count == 2,
                  let epoch = pair[0] as? Double,
                  let util = (pair[1] as? NSNumber)?.intValue else { return nil }
            samples.append(UtilizationSample(utilization: util, timestamp: Date(timeIntervalSince1970: epoch)))
        }
        return samples
    }

    func save() async {
        let snapshot = storage
        let liveDir = liveDirectory
        let allSucceeded = await Task.detached { () -> Bool in
            do {
                try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
            } catch {
                // Environmental failure (full disk, read-only volume), not a programmer error: never trap.
                return false
            }
            var succeeded = true
            for (identity, instance) in snapshot {
                if !Self.saveInstance(identity: identity, instance: instance, liveDir: liveDir) {
                    succeeded = false
                }
            }
            Self.clearLiveDirectoryEntries(in: liveDir, preservingQuarantine: true, keepingIdentities: Set(snapshot.keys))
            return succeeded
        }.value
        recordSaveResult(succeeded: allSucceeded)
    }

    /// Deletes the legacy (v1) sibling only if its own bytes decode and every decoded sample is
    /// in the read-back of the new file; an undecodable one is quarantined, never deleted.
    /// Returns whether the current-format write succeeded; the legacy handling never affects it.
    @discardableResult
    private nonisolated static func saveInstance(identity: String, instance: WindowInstance, liveDir: URL) -> Bool {
        let url = liveDir.appendingPathComponent("\(identity).\(Constants.History.windowInstanceFileExtension)")
        do {
            let data = try WindowInstanceCodec.encode(
                id: instance.id,
                resetsAt: instance.resetsAt,
                firstObservedAt: instance.firstObservedAt,
                events: instance.events,
                samples: instance.samples
            )
            try data.write(to: url, options: .atomic)
        } catch {
            // Environmental failure: never trap. Returning here skips the legacy handling, so a
            // failed write can't cost the legacy file.
            return false
        }

        let legacyURL = liveDir.appendingPathComponent("\(identity).json")
        guard FileManager.default.fileExists(atPath: legacyURL.path) else { return true }

        // Verify against the legacy file's own decoded bytes, never the in-memory instance.
        // `decode` falls back to its legacy path for data without the magic prefix.
        guard let legacyData = try? Data(contentsOf: legacyURL),
              let legacyDecoded = try? WindowInstanceCodec.decode(legacyData) else {
            quarantine(legacyURL)
            return true
        }

        if let readBack = try? Data(contentsOf: url),
           let verified = try? WindowInstanceCodec.decode(readBack),
           samplesRepresented(legacyDecoded.samples, in: verified.samples) {
            try? FileManager.default.removeItem(at: legacyURL)
        }
        // Otherwise the legacy file stays and is reconsidered on the next save().
        return true
    }

    /// Whole-second epoch, the codec's on-disk precision: the round trip truncates sub-second
    /// parts, so exact `Date` equality would fail for every freshly recorded sample.
    private struct SampleKey: Hashable {
        let utilization: Int
        let epochSeconds: Int
    }

    private nonisolated static func sampleKey(_ sample: UtilizationSample) -> SampleKey {
        SampleKey(utilization: sample.utilization, epochSeconds: Int(sample.timestamp.timeIntervalSince1970))
    }

    /// Multiset containment, not set membership: a key held twice by the legacy file but once
    /// in the read-back must fail, or the legacy file would be deleted with one occurrence
    /// unverified.
    private nonisolated static func samplesRepresented(_ legacySamples: [UtilizationSample], in verifiedSamples: [UtilizationSample]) -> Bool {
        guard !legacySamples.isEmpty else { return true }
        var remainingCounts: [SampleKey: Int] = [:]
        for sample in verifiedSamples {
            remainingCounts[sampleKey(sample), default: 0] += 1
        }
        for sample in legacySamples {
            let key = sampleKey(sample)
            guard let remaining = remainingCounts[key], remaining > 0 else { return false }
            remainingCounts[key] = remaining - 1
        }
        return true
    }

    /// Matches the old timestamp-less `.corrupt`/`.corrupt-N` shape and the current
    /// `.corrupt_<timestamp>`/`.corrupt_<timestamp>-N` shape.
    nonisolated static func isQuarantineFile(_ file: URL) -> Bool {
        let ext = file.pathExtension
        return ext == "corrupt" || ext.hasPrefix("corrupt-") || ext.hasPrefix(Constants.History.quarantinePrefix)
    }

    /// `nil` (age unknown) for the old timestamp-less shape or an unparseable name.
    nonisolated static func quarantineTimestamp(_ file: URL) -> Date? {
        let ext = file.pathExtension
        guard ext.hasPrefix(Constants.History.quarantinePrefix) else { return nil }
        let remainder = ext.dropFirst(Constants.History.quarantinePrefix.count)
        guard remainder.count >= Constants.History.quarantineTimestampLength else { return nil }
        let datePart = String(remainder.prefix(Constants.History.quarantineTimestampLength))
        return archiveDateFormatter.date(from: datePart)
    }

    /// Route every live-directory clearing through here so quarantine handling is decided explicitly.
    /// - `preservingQuarantine: true`: background sweeps (`save()`). A quarantined file's
    ///   derived identity (e.g. "18000.json") never matches a storageIdentity, so it would
    ///   be swept as an orphan.
    /// - `false`: `clearAll()` only; an explicit "Clear History" erases everything.
    ///
    /// `keepingIdentities` protects files backed by an active `storage` entry; `clearAll()`
    /// passes `nil` because it already emptied `storage`.
    nonisolated static func clearLiveDirectoryEntries(in liveDir: URL, preservingQuarantine: Bool, keepingIdentities activeIdentities: Set<String>? = nil) {
        let files = (try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            if preservingQuarantine && isQuarantineFile(file) { continue }
            if let activeIdentities, activeIdentities.contains(file.deletingPathExtension().lastPathComponent) { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Renames to `.corrupt_<timestamp>` instead of deleting, so undecodable data survives for
    /// recovery; the new extension keeps it out of `load()`'s `.dat`/`.json` filters.
    /// A same-instant name collision gets a numeric suffix (`-2`, `-3`) rather than overwriting.
    ///
    /// The timestamp lives in the name, not a filesystem attribute: `setAttributes` can fail
    /// silently, leaving the original file's mtime, so pruning would delete it at once or never.
    private nonisolated static func quarantine(_ file: URL) {
        let fm = FileManager.default
        let timestamp = archiveDateFormatter.string(from: Date())
        var candidate = file.appendingPathExtension("\(Constants.History.quarantinePrefix)\(timestamp)")
        var suffix = 2
        while fm.fileExists(atPath: candidate.path) {
            candidate = file.appendingPathExtension("\(Constants.History.quarantinePrefix)\(timestamp)-\(suffix)")
            suffix += 1
        }
        try? fm.moveItem(at: file, to: candidate)
    }

    // Synchronous by design: runs once at startup before any UI, which avoids fire-and-forget races.
    func load() {
        // Before the guard below: the manifest can exist without live/.
        loadMissingWindowSince()
        guard FileManager.default.fileExists(atPath: liveDirectory.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: liveDirectory, includingPropertiesForKeys: nil)
            // Current-format files first, legacy only for uncovered identities: directory order is
            // unspecified, and a stale legacy sibling (process killed between save()'s write and
            // its legacy delete) must not override the verified samples.
            let currentFormatFiles = files.filter { $0.pathExtension == Constants.History.windowInstanceFileExtension }
            let legacyFiles = files.filter { $0.pathExtension == "json" }
            for file in currentFormatFiles {
                loadInstanceFile(file)
            }
            for file in legacyFiles {
                let identity = file.deletingPathExtension().lastPathComponent
                guard storage[identity] == nil else { continue }
                loadInstanceFile(file)
            }
        } catch {}
    }

    private func loadInstanceFile(_ file: URL) {
        let identity = file.deletingPathExtension().lastPathComponent
        guard let data = try? Data(contentsOf: file) else { return }
        do {
            let decoded = try WindowInstanceCodec.decode(data)
            storage[identity] = WindowInstance(
                id: decoded.id,
                storageIdentity: identity,
                resetsAt: decoded.resetsAt,
                firstObservedAt: decoded.firstObservedAt,
                samples: decoded.samples,
                events: decoded.events
            )
        } catch {
            // Corrupt input is expected (partial write, bit rot): quarantine, never trap or delete.
            Self.quarantine(file)
        }
    }

    /// Deletes the pre-per-organization `live/` and `archive/` directories directly under
    /// `baseDirectory`. Unlike the sweeps of the current `<orgId>/live`, it does not preserve
    /// `.corrupt` files and bypasses `clearLiveDirectoryEntries`: nothing reads this location
    /// any more, so a preserved file would sit unreachable forever.
    static func migrateAndDeleteLegacyData(baseDirectory: URL) {
        let base = baseDirectory
        let fm = FileManager.default
        let liveDir = base.appendingPathComponent("live")
        let archiveDir = base.appendingPathComponent("archive")
        try? fm.removeItem(at: liveDir)
        try? fm.removeItem(at: archiveDir)
    }
}
