import Foundation

extension UsageHistory {
    nonisolated static func encodeCompact(_ samples: [UtilizationSample]) -> Data {
        let pairs = samples.map { "[\(Int($0.timestamp.timeIntervalSince1970)),\($0.utilization)]" }
        let json = "[" + pairs.joined(separator: ",") + "]"
        return Data(json.utf8)
    }

    nonisolated static func decodeCompact(_ data: Data) -> [UtilizationSample]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return nil }
        return raw.compactMap { pair -> UtilizationSample? in
            guard pair.count == 2,
                  let epoch = pair[0] as? Double,
                  let util = (pair[1] as? NSNumber)?.intValue else { return nil }
            return UtilizationSample(utilization: util, timestamp: Date(timeIntervalSince1970: epoch))
        }
    }

    func save() async {
        let snapshot = storage
        let liveDir = liveDirectory
        await Task.detached {
            do {
                try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
                for (identity, samples) in snapshot {
                    let url = liveDir.appendingPathComponent("\(identity).json")
                    let data = UsageHistory.encodeCompact(samples)
                    try data.write(to: url, options: .atomic)
                }
                let existingFiles = (try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)) ?? []
                let activeIdentities = Set(snapshot.keys.map { "\($0).json" })
                for file in existingFiles where !activeIdentities.contains(file.lastPathComponent) {
                    try? FileManager.default.removeItem(at: file)
                }
            } catch {
                assertionFailure("UsageHistory.save failed: \(error)")
            }
        }.value
    }

    // Synchronous by design — called once at startup before any UI is shown,
    // so a brief main-thread disk read is acceptable and avoids fire-and-forget races.
    func load() {
        guard FileManager.default.fileExists(atPath: liveDirectory.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: liveDirectory, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                let identity = file.deletingPathExtension().lastPathComponent
                guard let data = try? Data(contentsOf: file),
                      let samples = UsageHistory.decodeCompact(data) else { continue }
                storage[identity] = samples
            }
        } catch {}
    }

    static func migrateAndDeleteLegacyData(baseDirectory: URL = UsageHistory.defaultBaseDirectory) {
        let base = baseDirectory
        let fm = FileManager.default
        let liveDir = base.appendingPathComponent("live")
        let archiveDir = base.appendingPathComponent("archive")
        try? fm.removeItem(at: liveDir)
        try? fm.removeItem(at: archiveDir)
    }
}
