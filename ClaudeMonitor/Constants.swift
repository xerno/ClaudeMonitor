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
        // Blocked general window: utilization is frozen until the reset, which nextPollInterval targets.
        static let blockedBaseInterval: TimeInterval = 300
        static let minInterval: TimeInterval = 24

        static let rateEmaTau: TimeInterval = 60

        // Percentage points; the API reports whole percents, the finest granularity.
        static let resolutionPerPoll: Double = 1.0

        // Rate drives polling at full strength for `grace`, fades linearly over `decay`, then
        // `baseline` holds baseInterval; cooldown follows.
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

        // Lets the first post-reset poll see the reset state rather than race it.
        static let resetPadding: TimeInterval = 1
    }

    enum Retry {
        static let initialBackoff: TimeInterval = 10
        static let maxBackoff: TimeInterval = 300
        /// Consecutive failures that add the "Last update failed" row; data still counts as fresh.
        static let warnThreshold: Int = 2
        /// Consecutive failures that make data stale: banner, dimmed colors, "!" prefix, backoff.
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

        /// Off leaves only the status icon in the menu bar. The countdown timer runs either way:
        /// it also triggers the refresh when the block expires.
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
        /// Claude Code's session logs: JSON lines, appended live.
        static let logsDirectory = "~/.claude/projects"
        static let logFileExtension = "jsonl"
        /// Bytes per read; a scan holds at most one chunk plus one partial line.
        static let chunkSize = 256 * 1024
        /// Scan offsets, dedup hashes and carried totals, relative to Application Support.
        static let stateSubdirectory = "ClaudeMonitor/energy"
        static let stateFileName = "scan-state.json"

        // MARK: - Energy coefficients
        //
        // Anchor: Oviedo et al. (Microsoft), "Energy use of AI inference, efficiency pathways, and
        // test-time scaling", Joule 10(8):102430, 2026. Models >200B on H100: median 0.31 Wh per
        // query, interquartile range 0.16–0.60, at a median of 300 output tokens; effective length
        // is approximated by output length.
        //
        // Full-node figures: host CPU, DRAM, idle capacity and PUE included.
        // Low and high are asymmetric quartiles, not an error bar, hence three constants.
        static let anchorWhPerQueryLow = 0.16
        static let anchorWhPerQueryMedian = 0.31
        static let anchorWhPerQueryHigh = 0.60
        static let anchorOutputTokensPerQuery = 300.0
        /// 1.0: the anchor already includes PUE. Kept so a GPU-level anchor can be swapped in.
        static let pue = 1.0

        /// Paced by how fast the number changes, not scan cost (a repeat scan takes tens of ms).
        static let scanInterval: TimeInterval = 120
        /// Losing unwritten state costs one background cold scan, cheaper than writing ~1 MB per scan.
        static let statePersistInterval: TimeInterval = 600
    }

    enum History {
        static let deduplicationInterval: TimeInterval = 30
        static let gapThreshold: TimeInterval = 300
        // resets_at moves within this tolerance, in either direction, are jitter, not a boundary.
        static let resetBoundaryTolerance: TimeInterval = 60
        static let inferredSegmentMinGap: TimeInterval = 60
        // Relative to the Application Support directory.
        static let productionSubdirectory = "ClaudeMonitor/usage"
        // Live instances and archives. Named after the file kind, not a format version: the codec
        // version changes while the extension stays ".dat".
        static let windowInstanceFileExtension = "dat"
        // Legacy v1 archives (LZMA-compressed JSON). Read by retention and the legacy migration,
        // never written.
        static let legacyArchiveSuffix = ".json.lzma"
        // Per-organization metadata (persisted missingWindowSince), next to live/ and archive/.
        static let manifestFilename = "manifest.json"
        // v1 lacked `missingWindowSince`.
        static let manifestVersion = 2

        // MARK: - Retention

        static let defaultRetentionYears = 2
        static let minRetentionYears = 1
        static let maxRetentionYears = 99
        // Daily is ample: retention is measured in years.
        static let pruneInterval: TimeInterval = Constants.Time.secondsPerDay

        /// A missing key reads as 0 and 0 years would prune every archive, so anything out of range
        /// falls back to the default.
        static func retentionYears(defaults: UserDefaults = .standard) -> Int {
            let stored = defaults.integer(forKey: Constants.Preferences.historyRetentionYears)
            guard (minRetentionYears...maxRetentionYears).contains(stored) else { return defaultRetentionYears }
            return stored
        }

        static func clampRetentionYears(_ value: Int) -> Int {
            min(max(value, minRetentionYears), maxRetentionYears)
        }

        // MARK: - Missing-window archiving

        /// How long, as a multiple of its duration, a window key must stay absent from successful,
        /// complete fetches before archiving: a live window would have reset and reappeared within one.
        static let missingWindowArchiveMultiplier: Double = 1.0

        // MARK: - Quarantine

        /// Quarantine names: `<original>.corrupt_<timestamp>`, with `-2`, `-3`, ... appended on a
        /// same-instant collision.
        static let quarantinePrefix = "corrupt_"
        /// Length of the `yyyy-MM-dd'T'HHmm'Z'` timestamp (e.g. "2026-08-17T1200Z"), the format
        /// archive filenames use.
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

        /// Floor on the elapsed time in the post-credit rate (`UsageHistory.computeRate`): seconds
        /// after a credit, one data point would give an absurd spike. Flooring rather than
        /// rejecting keeps a projection available immediately.
        static let minRateElapsedAfterCredit: TimeInterval = 60
    }
}
