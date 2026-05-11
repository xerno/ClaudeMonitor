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
    let recentRate: Double?

    init(
        entry: WindowEntry,
        samples: [UtilizationSample],
        consumptionRate: Double,
        projectedAtReset: Double,
        timeToLimit: TimeInterval?,
        rateSource: RateSource,
        style: Formatting.UsageStyle,
        segments: [SampleSegment],
        timeSinceLastChange: TimeInterval?,
        recentRate: Double? = nil
    ) {
        self.entry = entry
        self.samples = samples
        self.consumptionRate = consumptionRate
        self.projectedAtReset = projectedAtReset
        self.timeToLimit = timeToLimit
        self.rateSource = rateSource
        self.style = style
        self.segments = segments
        self.timeSinceLastChange = timeSinceLastChange
        self.recentRate = recentRate
    }
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
    var storage: [String: [UtilizationSample]] = [:]
    private var organizationId: String? = nil

    static var defaultBaseDirectory: URL {
        #if DEBUG
        // Guard against test contamination of production data — see git history for the incident.
        if NSClassFromString("XCTest") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            preconditionFailure("UsageHistory.defaultBaseDirectory must not be used during tests — inject baseDirectory via UsageHistoryTestFixture")
        }
        #endif
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("ClaudeMonitor/usage")
    }

    let baseDirectory: URL

    init(baseDirectory: URL = UsageHistory.defaultBaseDirectory) {
        self.baseDirectory = baseDirectory
    }

    var usageDirectory: URL {
        guard let orgId = organizationId else { return baseDirectory }
        return baseDirectory.appendingPathComponent(orgId)
    }

    var liveDirectory: URL {
        usageDirectory.appendingPathComponent("live")
    }

    var archiveDirectory: URL {
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

    func samples(for entry: WindowEntry) -> [UtilizationSample] {
        // Samples are maintained in chronological order by record()
        let all = storage[entry.storageIdentity] ?? []
        if let windowStart = entry.windowStart {
            return all.filter { $0.timestamp >= windowStart }
        }
        return all
    }

    func clearAll() async {
        storage = [:]
        let liveDir = liveDirectory
        await Task.detached {
            let files = (try? FileManager.default.contentsOfDirectory(at: liveDir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }.value
    }

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
    func detectAndHandleReset(entry: WindowEntry, newResetsAt: Date?, previousResetsAt: Date?) async -> Bool {
        guard let newResetsAt, let previousResetsAt else { return false }
        guard newResetsAt > previousResetsAt else { return false }
        if newResetsAt.timeIntervalSince(previousResetsAt) > entry.duration * Constants.History.resetWindowFraction {
            await archiveWindow(identity: entry.storageIdentity, resetsAt: previousResetsAt, windowDuration: entry.duration)
            return true
        }
        return false
    }
}
