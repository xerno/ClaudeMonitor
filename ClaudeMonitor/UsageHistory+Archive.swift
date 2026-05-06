import Foundation

extension UsageHistory {
    nonisolated static let archiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmm'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    func archiveWindow(identity: String, resetsAt: Date, windowDuration: TimeInterval) async {
        guard let samples = storage[identity], !samples.isEmpty else { return }

        let windowEnd = resetsAt
        let windowStart = samples.first?.timestamp ?? resetsAt.addingTimeInterval(-windowDuration)

        let formatter = UsageHistory.archiveDateFormatter
        let startStr = formatter.string(from: windowStart)
        let endStr = formatter.string(from: windowEnd)
        let filename = "\(startStr)_\(endStr).json.lzma"

        let archiveDir = archiveDirectory.appendingPathComponent(identity)
        let archiveURL = archiveDir.appendingPathComponent(filename)

        let jsonData = UsageHistory.encodeCompact(samples)
        // Samples encoded before clearing — data persists on disk even if app crashes,
        // but in-memory samples are cleared unconditionally.
        storage[identity] = nil

        await Task.detached {
            do {
                try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
                let compressed = try (jsonData as NSData).compressed(using: .lzma) as Data
                try compressed.write(to: archiveURL, options: .atomic)
            } catch {
                // Archive write failed — samples were encoded before clearing storage,
                // so operational data is unaffected. Historical archive may be incomplete.
            }
        }.value
    }

    func pruneArchives(currentEntries: [WindowEntry]) async {
        guard !currentEntries.isEmpty else { return }
        let longestDuration = currentEntries.map { $0.duration }.max() ?? 0
        let retentionPeriod = longestDuration * Double(Constants.History.archiveRetentionMultiplier)
        let cutoff = Date().addingTimeInterval(-retentionPeriod)

        let archiveBase = archiveDirectory
        await Task.detached {
            guard let identityDirs = try? FileManager.default.contentsOfDirectory(at: archiveBase, includingPropertiesForKeys: nil) else { return }
            let formatter = UsageHistory.archiveDateFormatter

            for identityDir in identityDirs {
                guard let files = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil) else { continue }
                for file in files {
                    let lastComponent = file.lastPathComponent
                    let knownSuffix = ".json.lzma"
                    guard lastComponent.hasSuffix(knownSuffix) else { continue }
                    let name = String(lastComponent.dropLast(knownSuffix.count))
                    let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
                    guard parts.count == 2, let endDate = formatter.date(from: parts[1]) else { continue }
                    if endDate < cutoff {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
                if let remaining = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil),
                   remaining.isEmpty {
                    try? FileManager.default.removeItem(at: identityDir)
                }
            }
        }.value
    }
}
