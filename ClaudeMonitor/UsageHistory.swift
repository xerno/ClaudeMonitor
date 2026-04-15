import Foundation

struct UtilizationSample: Sendable, Equatable {
    let utilization: Int
    let timestamp: Date
}

enum RateSource: Sendable, Equatable {
    case implied
    case insufficient
}

struct SampleSegment: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case inferred   // from (window_start, 0%) to first real sample
        case tracked    // real data from polling
        case gap        // no data period (sleep, app closed)
    }
    let kind: Kind
    let samples: [UtilizationSample]
}

struct WindowAnalysis: Sendable, Equatable {
    let entry: WindowEntry
    let samples: [UtilizationSample]
    let consumptionRate: Double
    let projectedAtReset: Double
    let timeToLimit: TimeInterval?
    let rateSource: RateSource
    let style: Formatting.UsageStyle
    let segments: [SampleSegment]
}

extension WindowEntry {
    var storageIdentity: String {
        let seconds = Int(duration)
        guard let model = modelScope else { return "\(seconds)" }
        return "\(seconds)_\(model.lowercased())"
    }
}

@MainActor
final class UsageHistory {
    // Key is storageIdentity (e.g. "18000", "604800_sonnet"), not raw API key
    private var storage: [String: [UtilizationSample]] = [:]
    private var manifestCache: [String: String]? = nil
    private var organizationId: String? = nil

    // MARK: - Directory Helpers

    private static var baseUsageDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClaudeMonitor/usage")
    }

    private var usageDirectory: URL {
        let base = UsageHistory.baseUsageDirectory
        guard let orgId = organizationId else { return base }
        return base.appendingPathComponent(orgId)
    }

    private var liveDirectory: URL {
        usageDirectory.appendingPathComponent("live")
    }

    private var archiveDirectory: URL {
        usageDirectory.appendingPathComponent("archive")
    }

    private var manifestPath: URL {
        usageDirectory.appendingPathComponent("manifest.json")
    }

    func switchOrganization(_ orgId: String?) {
        guard orgId != organizationId else { return }
        organizationId = orgId
        storage = [:]
        manifestCache = nil
        if orgId != nil {
            load()
        }
    }

    static func migrateAndDeleteLegacyData() {
        let base = baseUsageDirectory
        let fm = FileManager.default
        let liveDir = base.appendingPathComponent("live")
        let archiveDir = base.appendingPathComponent("archive")
        let manifest = base.appendingPathComponent("manifest.json")
        try? fm.removeItem(at: liveDir)
        try? fm.removeItem(at: archiveDir)
        try? fm.removeItem(at: manifest)
    }

    // MARK: - Compact JSON

    private nonisolated static func encodeCompact(_ samples: [UtilizationSample]) -> Data {
        let pairs = samples.map { "[\(Int($0.timestamp.timeIntervalSince1970)),\($0.utilization)]" }
        let json = "[" + pairs.joined(separator: ",") + "]"
        return Data(json.utf8)
    }

    private nonisolated static func decodeCompact(_ data: Data) -> [UtilizationSample]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [[Any]] else { return nil }
        return raw.compactMap { pair -> UtilizationSample? in
            guard pair.count == 2,
                  let epoch = pair[0] as? Double,
                  let util = pair[1] as? Int else { return nil }
            return UtilizationSample(utilization: util, timestamp: Date(timeIntervalSince1970: epoch))
        }
    }

    // MARK: - Manifest

    private func loadManifest() -> [String: String] {
        if let cached = manifestCache { return cached }
        let path = manifestPath
        guard FileManager.default.fileExists(atPath: path.path),
              let data = try? Data(contentsOf: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let v = obj["v"] as? Int, v == 1,
              let keys = obj["keys"] as? [String: String] else {
            manifestCache = [:]
            return [:]
        }
        manifestCache = keys
        return keys
    }

    private func saveManifest(_ manifest: [String: String]) {
        manifestCache = manifest
        let obj: [String: Any] = ["v": 1, "keys": manifest]
        guard let data = try? JSONSerialization.data(withJSONObject: obj) else { return }
        let path = manifestPath
        try? FileManager.default.createDirectory(at: path.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: path, options: .atomic)
    }

    // MARK: - Persistence

    func save() {
        let snapshot = storage
        let liveDir = liveDirectory
        Task.detached {
            do {
                try FileManager.default.createDirectory(at: liveDir, withIntermediateDirectories: true)
                for (identity, samples) in snapshot {
                    let url = liveDir.appendingPathComponent("\(identity).json")
                    let data = UsageHistory.encodeCompact(samples)
                    try data.write(to: url, options: .atomic)
                }
                // Remove live files for identities no longer in storage
                let existingFiles = (try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)) ?? []
                let activeIdentities = Set(snapshot.keys.map { "\($0).json" })
                for file in existingFiles where !activeIdentities.contains(file.lastPathComponent) {
                    try? FileManager.default.removeItem(at: file)
                }
            } catch {
                // Fire-and-forget: ignore errors silently
            }
        }
    }

    func load() {
        let liveDir = liveDirectory
        guard FileManager.default.fileExists(atPath: liveDir.path) else { return }
        do {
            let files = try FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                let identity = file.deletingPathExtension().lastPathComponent
                guard let data = try? Data(contentsOf: file),
                      let samples = UsageHistory.decodeCompact(data) else { continue }
                storage[identity] = samples
            }
        } catch {
            storage = [:]
        }
    }

    func archiveWindow(identity: String, resetsAt: Date, windowDuration: TimeInterval) {
        guard let samples = storage[identity], !samples.isEmpty else { return }

        let windowEnd = resetsAt
        let windowStart: Date
        if let first = samples.min(by: { $0.timestamp < $1.timestamp }) {
            windowStart = first.timestamp
        } else {
            windowStart = resetsAt.addingTimeInterval(-windowDuration)
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmm'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let startStr = formatter.string(from: windowStart)
        let endStr = formatter.string(from: windowEnd)
        let filename = "\(startStr)_\(endStr).json.lzma"

        let archiveDir = archiveDirectory.appendingPathComponent(identity)
        let archiveURL = archiveDir.appendingPathComponent(filename)

        let jsonData = UsageHistory.encodeCompact(samples)

        Task.detached {
            do {
                try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
                let compressed = try (jsonData as NSData).compressed(using: .lzma) as Data
                try compressed.write(to: archiveURL, options: .atomic)
            } catch {
                // Fire-and-forget: ignore errors silently
            }
        }

        storage[identity] = nil
    }

    func pruneArchives(currentEntries: [WindowEntry]) {
        guard !currentEntries.isEmpty else { return }
        let longestDuration = currentEntries.map { $0.duration }.max() ?? 0
        let retentionPeriod = longestDuration * Double(Constants.History.archiveRetentionMultiplier)
        let cutoff = Date().addingTimeInterval(-retentionPeriod)

        let archiveBase = archiveDirectory
        Task.detached {
            guard let identityDirs = try? FileManager.default.contentsOfDirectory(at: archiveBase, includingPropertiesForKeys: nil) else { return }
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HHmm'Z'"
            formatter.timeZone = TimeZone(identifier: "UTC")

            for identityDir in identityDirs {
                guard let files = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil) else { continue }
                for file in files {
                    // Filename: {startISO}_{endISO}.json.lzma
                    let name = file.deletingPathExtension().deletingPathExtension().lastPathComponent
                    let parts = name.split(separator: "_", maxSplits: 1).map(String.init)
                    guard parts.count == 2, let endDate = formatter.date(from: parts[1]) else { continue }
                    if endDate < cutoff {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
                // Clean up empty directory
                if let remaining = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil),
                   remaining.isEmpty {
                    try? FileManager.default.removeItem(at: identityDir)
                }
            }
        }
    }

    // MARK: - Recording

    func record(entries: [WindowEntry], at date: Date = Date()) {
        // Collision guard: detect if two entries share the same identity
        var seenIdentities: [String: String] = [:]
        var identityMap: [String: String] = [:] // entry.key → resolved identity

        for entry in entries {
            let baseIdentity = entry.storageIdentity
            if seenIdentities[baseIdentity] != nil {
                // Collision: two API keys map to same identity — shouldn't happen but guard anyway
                let hash = abs(entry.key.hashValue) % 10000
                let resolvedIdentity = "\(baseIdentity)_\(hash)"
                identityMap[entry.key] = resolvedIdentity
            } else {
                seenIdentities[baseIdentity] = entry.key
                identityMap[entry.key] = baseIdentity
            }
        }

        for entry in entries {
            let identity = identityMap[entry.key] ?? entry.storageIdentity
            var samples = storage[identity] ?? []
            if let last = samples.last,
               last.utilization == entry.window.utilization,
               date.timeIntervalSince(last.timestamp) < Constants.History.deduplicationInterval {
                continue
            }
            samples.append(UtilizationSample(utilization: entry.window.utilization, timestamp: date))
            // Use window boundary (resetsAt - duration) as cutoff, not just age from now.
            // This ensures samples from a previous window period are pruned after a reset
            // that happened while the app was closed.
            let windowStart = entry.window.resetsAt.map { $0.addingTimeInterval(-entry.duration) }
            let cutoff = windowStart ?? date.addingTimeInterval(-entry.duration)
            samples = samples.filter { $0.timestamp >= cutoff }
            storage[identity] = samples
        }

        // Update manifest
        var manifest = loadManifest()
        var manifestChanged = false
        for entry in entries {
            let identity = identityMap[entry.key] ?? entry.storageIdentity
            if manifest[entry.key] != identity {
                manifest[entry.key] = identity
                manifestChanged = true
            }
        }
        if manifestChanged {
            saveManifest(manifest)
        }
    }

    func detectAndHandleReset(entry: WindowEntry, newResetsAt: Date?, previousResetsAt: Date?) {
        guard let newResetsAt, let previousResetsAt else { return }
        guard newResetsAt > previousResetsAt else { return }
        if newResetsAt.timeIntervalSince(previousResetsAt) > entry.duration * 0.5 {
            storage[entry.storageIdentity] = nil
        }
    }

    func samples(for entry: WindowEntry) -> [UtilizationSample] {
        let all = storage[entry.storageIdentity] ?? []
        if let resetsAt = entry.window.resetsAt {
            let windowStart = resetsAt.addingTimeInterval(-entry.duration)
            return all.filter { $0.timestamp >= windowStart }.sorted { $0.timestamp < $1.timestamp }
        }
        return all.sorted { $0.timestamp < $1.timestamp }
    }

    func clearAll() {
        storage = [:]
        let liveDir = liveDirectory
        Task.detached {
            let files = (try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    // MARK: - Segment Detection

    static func segmentSamples(
        _ samples: [UtilizationSample],
        windowStart: Date,
        gapThreshold: TimeInterval = Constants.History.gapThreshold
    ) -> [SampleSegment] {
        guard !samples.isEmpty else { return [] }

        let sorted = samples.sorted { $0.timestamp < $1.timestamp }
        var result: [SampleSegment] = []

        // If first sample is significantly after window start, add an inferred segment
        // from 0% (window resets to 0) to the first real sample.
        if sorted[0].timestamp > windowStart.addingTimeInterval(60) {
            let inferredStart = UtilizationSample(utilization: 0, timestamp: windowStart)
            result.append(SampleSegment(kind: .inferred, samples: [inferredStart, sorted[0]]))
        }

        // Walk through samples grouping into tracked and gap segments
        var currentTracked: [UtilizationSample] = [sorted[0]]

        for i in 1..<sorted.count {
            let prev = sorted[i - 1]
            let curr = sorted[i]
            let gap = curr.timestamp.timeIntervalSince(prev.timestamp)

            if gap > gapThreshold {
                // End current tracked segment
                if !currentTracked.isEmpty {
                    result.append(SampleSegment(kind: .tracked, samples: currentTracked))
                    currentTracked = []
                }
                // Add gap segment
                result.append(SampleSegment(kind: .gap, samples: [prev, curr]))
                // Start fresh tracked from post-gap sample
                currentTracked = [curr]
            } else {
                currentTracked.append(curr)
            }
        }

        // Flush remaining tracked samples
        if !currentTracked.isEmpty {
            result.append(SampleSegment(kind: .tracked, samples: currentTracked))
        }

        return result
    }

    // MARK: - Rate / Projection / Style

    static func computeRate(
        windowDuration: TimeInterval,
        currentUtilization: Int,
        resetsAt: Date?,
        now: Date = Date()
    ) -> (rate: Double, source: RateSource) {
        guard let resetsAt else { return (0, .insufficient) }

        let timeElapsed = windowDuration - max(0, resetsAt.timeIntervalSince(now))
        guard timeElapsed > 0 else { return (0, .insufficient) }

        let rate = Double(currentUtilization) / timeElapsed
        return (rate, .implied)
    }

    static func project(
        currentUtilization: Int,
        rate: Double,
        timeRemaining: TimeInterval
    ) -> (projectedAtReset: Double, timeToLimit: TimeInterval?) {
        let projectedAtReset = Double(currentUtilization) + rate * timeRemaining
        var timeToLimit: TimeInterval? = nil
        if rate > 0 && currentUtilization < 100 {
            let ttl = Double(100 - currentUtilization) / rate
            if ttl <= timeRemaining {
                timeToLimit = ttl
            }
        }
        return (projectedAtReset, timeToLimit)
    }

    static func computeStyle(
        projectedAtReset: Double,
        utilization: Int,
        resetsAt: Date?,
        timeRemaining: TimeInterval
    ) -> Formatting.UsageStyle {
        if utilization >= Constants.Projection.blockedUtilization {
            return Formatting.UsageStyle(level: .critical, isBold: true)
        }
        guard resetsAt != nil else {
            let isCritical = utilization >= Constants.Projection.fallbackCriticalThreshold
            let isWarning = utilization >= Constants.Projection.fallbackWarningThreshold
            let isBold = utilization >= Constants.Projection.fallbackBoldThreshold
            let level: Formatting.UsageLevel = isCritical ? .critical : isWarning ? .warning : .normal
            return Formatting.UsageStyle(level: level, isBold: isBold || isCritical || isWarning)
        }
        guard timeRemaining > 0 else {
            return Formatting.UsageStyle(level: .normal, isBold: false)
        }
        if projectedAtReset >= Constants.Projection.criticalThreshold {
            return Formatting.UsageStyle(level: .critical, isBold: true)
        }
        if projectedAtReset >= Constants.Projection.warningThreshold {
            return Formatting.UsageStyle(level: .warning, isBold: true)
        }
        if projectedAtReset >= Constants.Projection.boldThreshold {
            return Formatting.UsageStyle(level: .normal, isBold: true)
        }
        return Formatting.UsageStyle(level: .normal, isBold: false)
    }

    static func analyze(entry: WindowEntry, samples: [UtilizationSample], now: Date = Date()) -> WindowAnalysis {
        let timeRemaining = max(0, (entry.window.resetsAt ?? now).timeIntervalSince(now))
        let (rate, source) = computeRate(
            windowDuration: entry.duration,
            currentUtilization: entry.window.utilization,
            resetsAt: entry.window.resetsAt,
            now: now
        )
        let (projectedAtReset, timeToLimit) = project(
            currentUtilization: entry.window.utilization,
            rate: rate,
            timeRemaining: timeRemaining
        )
        let style = computeStyle(
            projectedAtReset: projectedAtReset,
            utilization: entry.window.utilization,
            resetsAt: entry.window.resetsAt,
            timeRemaining: timeRemaining
        )
        let windowStart = entry.window.resetsAt.map { $0.addingTimeInterval(-entry.duration) } ?? now
        let segs = segmentSamples(samples, windowStart: windowStart)
        return WindowAnalysis(
            entry: entry,
            samples: samples,
            consumptionRate: rate,
            projectedAtReset: projectedAtReset,
            timeToLimit: timeToLimit,
            rateSource: source,
            style: style,
            segments: segs
        )
    }
}
