import Foundation

/// Per-organization state not owned by any `WindowInstance`; `v` is the schema version.
struct HistoryManifest: Codable, Sendable, Equatable {
    var v: Int
    var missingWindowSince: [String: Date]?
}

extension UsageHistory {
    var manifestURL: URL {
        usageDirectory.appendingPathComponent(Constants.History.manifestFilename)
    }

    nonisolated static func decodeManifest(_ data: Data) -> HistoryManifest? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(HistoryManifest.self, from: data)
    }

    nonisolated static func encodeManifest(_ manifest: HistoryManifest) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(manifest)
    }

    /// Synchronous: called once from `load()` at startup.
    /// Timestamps after `now` are clamped to `now`; a future value (corrupt or hand-edited
    /// manifest) would understate the elapsed time `archiveMissingWindows` computes.
    func loadMissingWindowSince(at now: Date = Date()) {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = UsageHistory.decodeManifest(data),
              let stored = manifest.missingWindowSince else { return }
        for (identity, date) in stored {
            missingWindowSince[identity] = min(date, now)
        }
    }

    func saveMissingWindowSince() async {
        let snapshot = missingWindowSince
        let url = manifestURL
        await Task.detached {
            let manifest = HistoryManifest(v: Constants.History.manifestVersion, missingWindowSince: snapshot)
            guard let data = UsageHistory.encodeManifest(manifest) else { return }
            do {
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            } catch {
                // Best-effort: a failed write only delays missing-window archiving.
            }
        }.value
    }
}
