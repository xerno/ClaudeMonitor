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
        case tracked
        case gap
    }
    let kind: Kind
    let samples: [UtilizationSample]
}

struct WindowAnalysis: Sendable, Equatable {
    let entry: WindowEntry
    let samples: [UtilizationSample]
    /// Copied from the window instance so the menu/graph layer never reads `usageHistory` directly.
    let events: [UsageEvent]
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
        events: [UsageEvent] = [],
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
        self.events = events
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

/// A mid-window utilization drop (credit) with no `resets_at` change. Never a window boundary.
struct UsageEvent: Sendable, Equatable, Codable {
    enum Kind: Sendable, Equatable, Codable { case credit }
    let at: Date
    let kind: Kind
    let from: Int
    let to: Int
    /// Timestamp of the sample this drop originated from. nil only in files written before this
    /// field existed: such an event can't be checked for boundary straddling and is placed by `at`.
    let fromTimestamp: Date?
}

/// One lifetime of a window (e.g. the 5h window that reset at 18:50). Owns its samples permanently.
struct WindowInstance: Sendable, Equatable {
    let id: UUID
    let storageIdentity: String
    var resetsAt: Date?
    let firstObservedAt: Date
    var samples: [UtilizationSample]
    var events: [UsageEvent]
}

extension WindowEntry {
    /// Graph x-axis only — never use for data ownership.
    var windowStart: Date? {
        window.resetsAt.map { $0.addingTimeInterval(-duration) }
    }

    var storageIdentity: String {
        let seconds = Int(duration)
        guard let model = modelScope else { return "\(seconds)" }
        return "\(seconds)_\(model.lowercased())"
    }

    /// For windows that vanished from the API, where only the stored identity remains.
    static func duration(fromStorageIdentity identity: String) -> TimeInterval? {
        let secondsPart = identity.split(separator: "_", maxSplits: 1).first.map(String.init) ?? identity
        return TimeInterval(secondsPart)
    }
}

@MainActor
final class UsageHistory {
    // Current instance per storageIdentity (e.g. "18000", "604800_sonnet"), not per raw API key.
    var storage: [String: WindowInstance] = [:]
    private var organizationId: String? = nil
    // When each identity was first absent from a successful fetch. Persisted in manifest.json
    // so the clock survives restarts.
    var missingWindowSince: [String: Date] = [:]

    /// Latest `record()` time per identity, including deduplicated observations. Dedup leaves
    /// `samples.last` untouched (advancing it would erase how long a plateau held), so its
    /// timestamp can lag; a credit's `fromTimestamp` must come from here or it can falsely
    /// straddle a boundary (see `partitionEvents`). Not persisted.
    private var lastObservedAt: [String: Date] = [:]

    // Bumped whenever `storage` is replaced wholesale. `archiveWindow` re-checks it after its
    // `await` so a suspended archive can't write stale data into a cleared or switched storage.
    private(set) var generation = 0

    let baseDirectory: URL

    /// Whether the latest `save()` wrote every identity; `true` before the first save.
    private(set) var lastSaveSucceeded = true

    /// Start of the current run of failing saves; `nil` while saves succeed.
    private(set) var persistenceFailingSince: Date?

    /// The running `migrateLegacyArchives()`, if any. Later callers await it instead of starting
    /// a second migration over the same directory (e.g. org switch A → B → A during detached I/O).
    var inFlightLegacyMigration: Task<LegacyArchiveMigrationResult, Never>?

    /// The running `pruneArchives()`, if any. Pruning and legacy migration each await the other's
    /// task, so they never run file I/O over `archiveDirectory` concurrently: a prune could
    /// otherwise delete a legacy `.json.lzma` archive before migration has written and verified
    /// its replacement.
    var inFlightPrune: Task<Void, Never>?

    /// The only place the production history path is built; callers must not build it themselves.
    static var productionBaseDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(Constants.History.productionSubdirectory)
    }

    init(baseDirectory: URL) {
        // `test.sh` exports `BuildInfo.underTestEnvVar`; it is the only reliable under-test signal,
        // because the Swift Testing runner sets none of the XCTest environment variables.
        let isUnderTest = ProcessInfo.processInfo.environment[BuildInfo.underTestEnvVar] != nil
        if isUnderTest {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            if let appSupport, baseDirectory.standardizedFileURL.path.hasPrefix(appSupport.standardizedFileURL.path) {
                preconditionFailure("UsageHistory must never be constructed with a baseDirectory inside Application Support during tests — inject a temporary directory instead (see TestHistoryRoot).")
            }
        }
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
        missingWindowSince = [:]
        lastObservedAt = [:]
        generation += 1
        if orgId != nil {
            load()
        }
    }

    func samples(for entry: WindowEntry) -> [UtilizationSample] {
        storage[entry.storageIdentity]?.samples ?? []
    }

    /// The user's explicit "Clear History". Also erases quarantined (`.corrupt`) files, unlike
    /// `save()`'s orphan sweep, which must preserve them.
    func clearAll() async {
        storage = [:]
        missingWindowSince = [:]
        lastObservedAt = [:]
        generation += 1
        let liveDir = liveDirectory
        await Task.detached {
            Self.clearLiveDirectoryEntries(in: liveDir, preservingQuarantine: false)
        }.value
    }

    /// Internal so tests can drive the state transitions without a real disk failure.
    func recordSaveResult(succeeded: Bool, at now: Date = Date()) {
        lastSaveSucceeded = succeeded
        if succeeded {
            persistenceFailingSince = nil
        } else if persistenceFailingSince == nil {
            persistenceFailingSince = now
        }
    }

    /// Splits events at a window boundary: `< boundary` is the old window, `>= boundary` the new.
    /// An event whose `fromTimestamp` and `at` fall on opposite sides is the misclassified reset
    /// itself and is dropped, but only when `boundaryIsProven` (a persisted `resets_at`). A derived
    /// boundary (`newResetsAt - duration`) may be slightly off, so there a straddling event is kept
    /// and placed by `at`.
    private nonisolated static func partitionEvents(_ events: [UsageEvent], at boundary: Date, boundaryIsProven: Bool) -> (prior: [UsageEvent], current: [UsageEvent]) {
        var prior: [UsageEvent] = []
        var current: [UsageEvent] = []
        for event in events {
            guard let fromTimestamp = event.fromTimestamp else {
                if event.at < boundary {
                    prior.append(event)
                } else {
                    current.append(event)
                }
                continue
            }
            let toTimestamp = event.at
            if fromTimestamp < boundary && toTimestamp < boundary {
                prior.append(event)
            } else if fromTimestamp >= boundary && toTimestamp >= boundary {
                current.append(event)
            } else if boundaryIsProven {
                // Straddles a proven boundary: the misclassified reset, dropped.
            } else {
                if event.at < boundary {
                    prior.append(event)
                } else {
                    current.append(event)
                }
            }
        }
        return (prior, current)
    }

    func record(entries: [WindowEntry], at date: Date = Date()) {
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
            let utilization = entry.window.utilization

            guard var instance = storage[identity] else {
                storage[identity] = WindowInstance(
                    id: UUID(),
                    storageIdentity: identity,
                    resetsAt: entry.window.resetsAt,
                    firstObservedAt: date,
                    samples: [UtilizationSample(utilization: utilization, timestamp: date)],
                    events: []
                )
                lastObservedAt[identity] = date
                continue
            }

            if let last = instance.samples.last,
               last.utilization == utilization,
               date.timeIntervalSince(last.timestamp) < Constants.History.deduplicationInterval {
                lastObservedAt[identity] = date
                continue
            }

            if let last = instance.samples.last, utilization < last.utilization {
                // `lastObservedAt` is empty for the first record() after a restart.
                let origin = lastObservedAt[identity] ?? last.timestamp
                instance.events.append(UsageEvent(at: date, kind: .credit, from: last.utilization, to: utilization, fromTimestamp: origin))
            }

            instance.samples.append(UtilizationSample(utilization: utilization, timestamp: date))
            storage[identity] = instance
            lastObservedAt[identity] = date
        }
    }

    /// Driven only by `resets_at`, never utilization: a drop is a credit (see `record()`), not a reset.
    ///
    /// Returns `true` only if a prior window's history was actually archived, not merely because
    /// `resets_at` advanced.
    @discardableResult
    func detectAndHandleReset(entry: WindowEntry, newResetsAt: Date?, at now: Date = Date()) async -> Bool {
        let identity = entry.storageIdentity
        guard var instance = storage[identity] else { return false }

        guard let newResetsAt else {
            return false
        }

        guard let stored = instance.resetsAt else {
            // No persisted `resets_at` (nil at first observation, legacy v1 data, or a restart
            // that raced the first save). An empty instance just adopts it.
            if instance.samples.isEmpty {
                instance.resetsAt = newResetsAt
                storage[identity] = instance
                return false
            }

            // Legacy samples were pruned to the current window before saving, so they mostly belong
            // to it: partition against a `windowStart` derived from `newResetsAt`, don't archive
            // them wholesale. A derived boundary is trusted only here; the normal path below
            // requires a persisted `stored`.
            let windowStart = newResetsAt.addingTimeInterval(-entry.duration)
            let priorSamples = instance.samples.filter { $0.timestamp < windowStart }
            let currentSamples = instance.samples.filter { $0.timestamp >= windowStart }
            let (priorEvents, currentEvents) = UsageHistory.partitionEvents(instance.events, at: windowStart, boundaryIsProven: false)

            let firstObservedAt = currentSamples.first?.timestamp ?? now
            let currentInstance = WindowInstance(
                id: priorSamples.isEmpty ? instance.id : UUID(),
                storageIdentity: identity,
                resetsAt: newResetsAt,
                firstObservedAt: firstObservedAt,
                samples: currentSamples,
                events: currentEvents
            )

            if !priorSamples.isEmpty {
                // The prior window's end is unknown; `windowStart` (when the current one began)
                // approximates it, `now` would be an arbitrary later poll.
                storage[identity] = WindowInstance(
                    id: instance.id,
                    storageIdentity: identity,
                    resetsAt: windowStart,
                    firstObservedAt: instance.firstObservedAt,
                    samples: priorSamples,
                    events: priorEvents
                )
                // `currentInstance` goes through `replacingWith:` because a post-`await` write to
                // `storage` is only safe inside `archiveWindow` (generation guard).
                await archiveWindow(identity: identity, resetsAt: windowStart, windowDuration: entry.duration, replacingWith: currentInstance)
            } else {
                // No `await` here, so a direct write cannot race.
                storage[identity] = currentInstance
            }
            return !priorSamples.isEmpty
        }

        let tolerance = Constants.History.resetBoundaryTolerance
        let delta = newResetsAt.timeIntervalSince(stored)

        if delta > tolerance {
            if now >= stored - tolerance {
                // The API can drop utilization for the new instance one poll before it advances
                // `resets_at`, so samples at/after `stored` belong to the new window (`>=`: the
                // boundary instant starts it).
                let priorSamples = instance.samples.filter { $0.timestamp < stored }
                let currentSamples = instance.samples.filter { $0.timestamp >= stored }

                let (priorEvents, currentEvents) = UsageHistory.partitionEvents(instance.events, at: stored, boundaryIsProven: true)

                let firstObservedAt = currentSamples.first?.timestamp ?? now
                let freshInstance = WindowInstance(
                    id: UUID(),
                    storageIdentity: identity,
                    resetsAt: newResetsAt,
                    firstObservedAt: firstObservedAt,
                    samples: currentSamples,
                    events: currentEvents
                )
                // `archiveWindow` archives whatever `storage[identity]` holds, so it gets the
                // prior-only partition first; `freshInstance` goes through `replacingWith:`.
                storage[identity] = WindowInstance(
                    id: instance.id,
                    storageIdentity: identity,
                    resetsAt: stored,
                    firstObservedAt: instance.firstObservedAt,
                    samples: priorSamples,
                    events: priorEvents
                )
                // `archiveWindow` returns false when the prior-only partition has no samples.
                return await archiveWindow(identity: identity, resetsAt: stored, windowDuration: entry.duration, replacingWith: freshInstance)
            } else {
                // Forward move before the old reset has passed: drift, same instance.
                instance.resetsAt = newResetsAt
                storage[identity] = instance
                return false
            }
        } else if delta < -tolerance {
            return false
        } else {
            return false
        }
    }
}
