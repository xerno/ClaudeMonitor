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
    let timeSinceLastChange: TimeInterval?
}

extension WindowEntry {
    var windowStart: Date? {
        window.resetsAt.map { $0.addingTimeInterval(-duration) }
    }

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

    func switchOrganization(_ orgId: String?) {
        guard orgId != organizationId else { return }
        organizationId = orgId
        storage = [:]
        if orgId != nil {
            load()
        }
    }

    static func migrateAndDeleteLegacyData() {
        let base = baseUsageDirectory
        let fm = FileManager.default
        let liveDir = base.appendingPathComponent("live")
        let archiveDir = base.appendingPathComponent("archive")
        try? fm.removeItem(at: liveDir)
        try? fm.removeItem(at: archiveDir)
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
                  let util = (pair[1] as? NSNumber)?.intValue else { return nil }
            return UtilizationSample(utilization: util, timestamp: Date(timeIntervalSince1970: epoch))
        }
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

    private nonisolated static let archiveDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HHmm'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    func archiveWindow(identity: String, resetsAt: Date, windowDuration: TimeInterval) {
        guard let samples = storage[identity], !samples.isEmpty else { return }

        let windowEnd = resetsAt
        // samples are in chronological order (insertion invariant maintained by record())
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

        Task.detached {
            do {
                try FileManager.default.createDirectory(at: archiveDir, withIntermediateDirectories: true)
                let compressed = try (jsonData as NSData).compressed(using: .lzma) as Data
                try compressed.write(to: archiveURL, options: .atomic)
            } catch {
                // Archive write failed — samples were encoded before clearing storage,
                // so operational data is unaffected. Historical archive may be incomplete.
            }
        }
    }

    func pruneArchives(currentEntries: [WindowEntry]) {
        guard !currentEntries.isEmpty else { return }
        let longestDuration = currentEntries.map { $0.duration }.max() ?? 0
        let retentionPeriod = longestDuration * Double(Constants.History.archiveRetentionMultiplier)
        let cutoff = Date().addingTimeInterval(-retentionPeriod)

        let archiveBase = archiveDirectory
        Task.detached {
            guard let identityDirs = try? FileManager.default.contentsOfDirectory(at: archiveBase, includingPropertiesForKeys: nil) else { return }
            let formatter = UsageHistory.archiveDateFormatter

            for identityDir in identityDirs {
                guard let files = try? FileManager.default.contentsOfDirectory(at: identityDir, includingPropertiesForKeys: nil) else { continue }
                for file in files {
                    // Filename: {startISO}_{endISO}.json.lzma — strip the known compound suffix explicitly
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
        // Collision guard: two entries sharing the same storageIdentity shouldn't happen.
        #if DEBUG
        var seenIdentities: [String: String] = [:]
        for entry in entries {
            let identity = entry.storageIdentity
            assert(seenIdentities[identity] == nil, "storageIdentity collision: \(identity) used by \(entry.key) and \(seenIdentities[identity]!)")
            seenIdentities[identity] = entry.key
        }
        #endif

        for entry in entries {
            let identity = entry.storageIdentity
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
            let cutoff = entry.windowStart ?? date.addingTimeInterval(-entry.duration)
            samples = samples.filter { $0.timestamp >= cutoff }
            storage[identity] = samples
        }
    }

    @discardableResult
    func detectAndHandleReset(entry: WindowEntry, newResetsAt: Date?, previousResetsAt: Date?) -> Bool {
        guard let newResetsAt, let previousResetsAt else { return false }
        guard newResetsAt > previousResetsAt else { return false }
        if newResetsAt.timeIntervalSince(previousResetsAt) > entry.duration * 0.5 {
            archiveWindow(identity: entry.storageIdentity, resetsAt: previousResetsAt, windowDuration: entry.duration)
            return true
        }
        return false
    }

    func samples(for entry: WindowEntry) -> [UtilizationSample] {
        // Samples are maintained in chronological order by record()
        let all = storage[entry.storageIdentity] ?? []
        if let windowStart = entry.windowStart {
            return all.filter { $0.timestamp >= windowStart }
        }
        return all
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

        // samples are in chronological order (insertion invariant maintained by record())
        var result: [SampleSegment] = []

        // If first sample is significantly after window start, add an inferred segment
        // from 0% (window resets to 0) to the first real sample.
        if samples[0].timestamp > windowStart.addingTimeInterval(60) {
            let inferredStart = UtilizationSample(utilization: 0, timestamp: windowStart)
            result.append(SampleSegment(kind: .inferred, samples: [inferredStart, samples[0]]))
        }

        // Walk through samples grouping into tracked and gap segments
        var currentTracked: [UtilizationSample] = [samples[0]]

        for i in 1..<samples.count {
            let prev = samples[i - 1]
            let curr = samples[i]
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

    static func computeTimeSinceLastChange(
        currentUtilization: Int,
        samples: [UtilizationSample],
        now: Date = Date()
    ) -> TimeInterval? {
        guard !samples.isEmpty else { return nil }
        // samples are in chronological order (insertion invariant maintained by record())

        // Walk backwards to find the most recent sample with a DIFFERENT utilization
        for i in stride(from: samples.count - 1, through: 0, by: -1) {
            if samples[i].utilization != currentUtilization {
                // The change happened at the next sample (which has currentUtilization)
                if i + 1 < samples.count {
                    return now.timeIntervalSince(samples[i + 1].timestamp)
                }
                // Edge: last sample differs but there's nothing after → change is "now"
                return 0
            }
        }

        // All samples have the same utilization → hasn't changed since first sample
        return now.timeIntervalSince(samples.first!.timestamp)
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
        let style = Formatting.usageStyle(
            projectedAtReset: projectedAtReset,
            utilization: entry.window.utilization,
            resetsAt: entry.window.resetsAt,
            timeRemaining: timeRemaining
        )
        let windowStart = entry.windowStart ?? now
        let segs = segmentSamples(samples, windowStart: windowStart)
        let timeSinceLastChange = computeTimeSinceLastChange(
            currentUtilization: entry.window.utilization,
            samples: samples,
            now: now
        )
        return WindowAnalysis(
            entry: entry,
            samples: samples,
            consumptionRate: rate,
            projectedAtReset: projectedAtReset,
            timeToLimit: timeToLimit,
            rateSource: source,
            style: style,
            segments: segs,
            timeSinceLastChange: timeSinceLastChange
        )
    }
}
