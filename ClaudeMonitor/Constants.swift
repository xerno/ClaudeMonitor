import Foundation

enum Constants {
    enum Keychain {
        static let cookieString = "cookieString"
        static let organizationId = "organizationId"
        static let keySalt = ".com.claudemonitor"
        static let encryptionService = "com.claudemonitor.encryption"
        static let fallbackUUIDAccount = "fallbackUUID"
    }

    enum Profiles {
        static let registryKey = "profiles"
        static let corruptRegistryKeyPrefix = "profiles.corrupt."
        static let activeIdKey = "activeProfileId"
        static let maxCount = 5
        private static let cookieKeyPrefix = "cookieString."

        static func cookieKey(profileId: String) -> String {
            cookieKeyPrefix + profileId
        }
    }

    enum IOKit {
        static let hidSystemServiceName = "IOHIDSystem"
        static let hidIdleTimeKey = "HIDIdleTime"
    }

    enum API {
        static let statusURL = URL(string: "https://status.claude.com/api/v2/summary.json")!
        static let usageBasePath = "https://claude.ai/api/organizations"
        static let referer = "https://claude.ai"

        static let userAgent: String = {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(v.majorVersion)_\(v.minorVersion)_\(v.patchVersion)) AppleWebKit/605.1.15 (KHTML, like Gecko)"
        }()

        static func usageURL(organizationId: String) -> URL? {
            URL(string: "\(usageBasePath)/\(organizationId)/usage")
        }
    }

    enum Polling {
        static let baseInterval: TimeInterval = 60
        // When a general (non-model-specific) window is blocked, utilization won't
        // change until reset — poll slowly and rely on the post-reset 1s snap instead.
        static let blockedBaseInterval: TimeInterval = 300
        static let minInterval: TimeInterval = 24

        static let rateEmaTau: TimeInterval = 60

        // Target utilization delta per poll (percentage points). Anthropic reports
        // utilization in whole percents, so 1.0 matches the finest signal granularity.
        static let resolutionPerPoll: Double = 1.0

        // Four-phase activity model: during `grace` the rate drives polling at full
        // strength; over `decay` the rate's influence fades linearly to zero; across
        // `baseline` polling stays at baseInterval with no rate influence; after
        // that, cooldown interpolation begins.
        static let activityGrace: TimeInterval = 300
        static let activityDecay: TimeInterval = 1200
        static let activityBaseline: TimeInterval = 600

        static let cooldownStart: TimeInterval = activityGrace + activityDecay + activityBaseline
        static let cooldownRamp: TimeInterval = 3600
        static let cooldownEnd: TimeInterval = cooldownStart + cooldownRamp

        static let nearLimitCooldownCap: TimeInterval = 120

        static let maxIdleInterval: TimeInterval = 300
        static let maxAwayInterval: TimeInterval = 3600
        static let awayThreshold: TimeInterval = 300
        static let awayRampEnd: TimeInterval = 7200
        static let heartbeatInterval: TimeInterval = 60

        // Delay added after a detected reset so the first post-reset poll sees the
        // reset state (utilization=0) rather than racing it.
        static let resetPadding: TimeInterval = 1
    }

    enum Retry {
        static let initialBackoff: TimeInterval = 10
        static let maxBackoff: TimeInterval = 300
        /// 2 consecutive failures: dropdown shows "Last update failed" row, data still considered fresh.
        static let warnThreshold: Int = 2
        /// 3 consecutive failures: data is stale (banner, dimmed colors, "!" prefix, backoff active).
        static let failureThreshold: Int = 3
        static let staleDataMaxAge: TimeInterval = 3600
    }

    enum Network {
        static let requestTimeout: TimeInterval = 15
        static let pathMonitorQueueLabel = "com.claudemonitor.pathmonitor"
    }

    enum Color {
        static let staleSaturationScale: CGFloat = 0.25
        static let staleLightnessShiftToMid: CGFloat = 0.5
    }

    enum Time {
        static let secondsPerHour: TimeInterval = 3600
        static let secondsPerDay: TimeInterval = 86_400
        static let daysHoursTierThreshold: Int = 25
    }

    enum Preferences {
        static let resetSoundEnabled = "resetSoundEnabled"
        static let historyRetentionYears = "historyRetentionYears"
        static let showUsageGraph = "showUsageGraph"
        static let compactServices = "compactServices"

        static func isUsageGraphEnabled(in defaults: UserDefaults) -> Bool {
            (defaults.object(forKey: showUsageGraph) as? Bool) ?? true
        }

        static func isServicesCompact(in defaults: UserDefaults) -> Bool {
            (defaults.object(forKey: compactServices) as? Bool) ?? true
        }

        static let showBlockedCountdown = "showBlockedCountdown"

        /// Whether the menu bar keeps showing the stop icon and the countdown while a window is
        /// blocked. Turned off, the title goes empty and only the status icon remains; the
        /// countdown still appears on the dropdown's badge, and the countdown timer keeps running
        /// either way — it is also what triggers the refresh when the block expires.
        /// Absent defaults to shown, so nobody's menu bar changes without them asking.
        static func isBlockedCountdownShown(in defaults: UserDefaults) -> Bool {
            (defaults.object(forKey: showBlockedCountdown) as? Bool) ?? true
        }
    }

    enum Sounds {
        static let criticalReset = "Glass"
    }

    enum Menu {
        static let appTitle = "Claude Monitor"
        static let ellipsis = "…"
        static let edgePadding: CGFloat = 14
        static let headerElementSpacing: CGFloat = 20
        static let footerHeight: CGFloat = 32
        static let footerButtonSize = NSSize(width: 44, height: 26)

        enum Symbol {
            static let refresh = "arrow.clockwise"
            static let preferences = "gearshape"
            static let about = "info.circle"
            static let quit = "power"
        }

        enum KeyEquivalent {
            static let refresh = "r"
            static let preferences = ","
            static let quit = "q"
        }
    }

    enum GitHub {
        static let profile = URL(string: "https://github.com/xerno")!
        static let repository = URL(string: "https://github.com/xerno/ClaudeMonitor")!
        static let issues = URL(string: "https://github.com/xerno/ClaudeMonitor/issues")!
    }

    enum Demo {
        static let isActive: Bool = ProcessInfo.processInfo.arguments.contains("--demo")
        static let rotationOrder: [Int] = [3, 2, 1, 4, 5, 6, 7]
        static let rotationInterval: TimeInterval = 5
    }

    enum Energy {
        /// Claude Code's session logs: one JSON object per line, appended live while it runs.
        static let logsDirectory = "~/.claude/projects"
        static let logFileExtension = "jsonl"
        /// Read size per step. Large enough that syscall overhead disappears, small enough that a
        /// scan of a 700 MB archive never holds more than a chunk plus one partial line.
        static let chunkSize = 256 * 1024
        /// Where the scan offsets, dedup hashes and carried totals live, relative to Application
        /// Support — mirrors `History.productionSubdirectory`.
        static let stateSubdirectory = "ClaudeMonitor/energy"
        static let stateFileName = "scan-state.json"

        // MARK: - Energy coefficients
        //
        // Anchor: Oviedo et al. (Microsoft), "Energy use of AI inference, efficiency pathways, and
        // test-time scaling", Joule 10(8):102430, 2026. Models >200B on H100: median 0.31 Wh per
        // query, interquartile range 0.16–0.60, at a median of 300 output tokens. The paper fixes
        // input length and approximates effective length by output length, on the grounds that
        // output tokens dominate.
        //
        // These are FULL-NODE figures: host CPU and DRAM, idle capacity and PUE are already inside
        // them. That is the accounting boundary this feature reports, and it is why `pue` below is
        // 1.0 — applying a datacentre multiplier on top would count it twice.
        //
        // Kept as three separate numbers rather than one value with a spread, because the low and
        // high are measured quartiles, not a symmetric error bar.
        static let anchorWhPerQueryLow = 0.16
        static let anchorWhPerQueryMedian = 0.31
        static let anchorWhPerQueryHigh = 0.60
        /// Output tokens the anchor's per-query figures correspond to.
        static let anchorOutputTokensPerQuery = 300.0
        /// Already contained in the anchor above. Present so a GPU-level anchor could be swapped in
        /// without the multiplier being lost, not because it should be changed to 1.12 here.
        static let pue = 1.0

        /// How often the logs are re-read. A repeat scan reads only what was appended and costs
        /// tens of milliseconds, so this is paced for how fast the number meaningfully changes,
        /// not for how expensive the scan is.
        static let scanInterval: TimeInterval = 120
        /// Scan state is only written this often. Losing it costs one background cold scan on the
        /// next launch, which is cheaper than writing a megabyte every two minutes.
        static let statePersistInterval: TimeInterval = 600
    }

    enum History {
        static let deduplicationInterval: TimeInterval = 30
        static let gapThreshold: TimeInterval = 300
        // Jitter allowance around a stored resets_at: moves within this tolerance
        // (either direction) are treated as the same window instance, not a boundary.
        static let resetBoundaryTolerance: TimeInterval = 60
        static let inferredSegmentMinGap: TimeInterval = 60
        // Single source of truth for where production window-history data lives,
        // relative to the Application Support directory.
        static let productionSubdirectory = "ClaudeMonitor/usage"
        // Single source of truth for the current on-disk window-instance file extension,
        // used for both live instances and archives (see WindowInstanceCodec). Named after
        // the file kind, not a format version: the codec has already moved from v2 to v3
        // (and may move again) while files keep this same ".dat" extension throughout, so a
        // version-numbered name here would go stale the next time the on-disk format bumps
        // (this is exactly what happened to the previous name, `v2FileExtension`, once the
        // encoder moved on to v3 — see WindowInstanceCodec.swift).
        static let windowInstanceFileExtension = "dat"
        // Legacy (v1) archive suffix — LZMA-compressed bare JSON array, superseded by the v3
        // binary format (`windowInstanceFileExtension`). Still recognized by readers/collectors
        // (retention's `collectArchiveFiles`, the one-time legacy-archive migration) so old
        // archives remain visible to both; never written by any current code path.
        static let legacyArchiveSuffix = ".json.lzma"
        // Per-organization metadata file (currently: persisted missingWindowSince), stored
        // alongside live/ and archive/ — see UsageHistory+Manifest.swift.
        static let manifestFilename = "manifest.json"
        // Current manifest schema version. v1 predates `missingWindowSince`; v2 adds it.
        static let manifestVersion = 2

        // MARK: - Retention

        static let defaultRetentionYears = 2
        static let minRetentionYears = 1
        static let maxRetentionYears = 99
        // How often pruneArchives() re-runs on its own periodic schedule (in addition to
        // running once at launch and once after any detected window boundary). Retention is
        // measured in years, so daily granularity is ample — running more often buys nothing.
        static let pruneInterval: TimeInterval = Constants.Time.secondsPerDay

        /// Reads the configured retention (in years) from `UserDefaults`, defensively
        /// resolving a missing, zero, negative, or out-of-range stored value to
        /// `defaultRetentionYears`. A corrupt or absent setting must never resolve to a
        /// value that deletes more history than the user ever configured.
        static func retentionYears(defaults: UserDefaults = .standard) -> Int {
            let stored = defaults.integer(forKey: Constants.Preferences.historyRetentionYears)
            guard (minRetentionYears...maxRetentionYears).contains(stored) else { return defaultRetentionYears }
            return stored
        }

        /// Clamps a user-entered retention value (Preferences stepper/text field) into the
        /// valid `[minRetentionYears, maxRetentionYears]` range.
        static func clampRetentionYears(_ value: Int) -> Int {
            min(max(value, minRetentionYears), maxRetentionYears)
        }

        // MARK: - Missing-window archiving (Task 5)

        /// A window key present in `storage` but absent from the API is archived once it has
        /// been continuously absent (across successful, complete usage fetches only) for at
        /// least its own window duration. Rationale: if the window were still valid, a full
        /// duration cycle would have elapsed and it would have reset and reappeared under a
        /// new `resets_at` — so surviving a full duration absent, polled repeatedly, rules out
        /// a single missed/failed refresh or transient key reshuffle and leaves "the API
        /// stopped reporting this window" as the only explanation.
        static let missingWindowArchiveMultiplier: Double = 1.0

        // MARK: - Quarantine

        /// Extension prefix used by the current quarantine naming scheme (see
        /// `UsageHistory.quarantine`): `<original>.corrupt_<timestamp>` or, on a same-instant
        /// collision, `<original>.corrupt_<timestamp>-2`, `-3`, ...
        static let quarantinePrefix = "corrupt_"
        /// The fixed-width (16-character, e.g. "2026-08-17T1200Z") `yyyy-MM-dd'T'HHmm'Z'`
        /// timestamp length used by the quarantine naming scheme — the same format archives
        /// already use for their `<start>_<end>` filenames.
        static let quarantineTimestampLength = 16
    }

    enum Projection {
        static let boldThreshold: Double = 80
        static let warningThreshold: Double = 100
        static let criticalThreshold: Double = 120
        static let blockedUtilization: Int = 100
        static let fallbackBoldThreshold: Int = 80
        static let fallbackWarningThreshold: Int = 90
        static let fallbackCriticalThreshold: Int = 95

        /// Floor applied to the elapsed-time denominator when computing the post-credit implied
        /// rate (`UsageHistory.computeRate`). Immediately after a credit, `now - creditAt` can be
        /// only seconds — dividing by that would produce an absurdly large instantaneous rate
        /// from a single data point. Flooring the denominator at this value (rather than
        /// rejecting the rate outright) bounds the maximum possible spike while still producing
        /// a usable projection right away. Matches the order of magnitude of
        /// `Constants.History.deduplicationInterval` — within one dedup interval of the credit,
        /// there isn't yet a second independent observation to trust a raw instantaneous rate.
        static let minRateElapsedAfterCredit: TimeInterval = 60
    }
}
