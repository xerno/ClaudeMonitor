import Foundation

enum Constants {
    enum Keychain {
        static let cookieString = "cookieString"
        static let organizationId = "organizationId"
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
        static let failureThreshold: Int = 2
        static let staleDataMaxAge: TimeInterval = 3600
    }

    enum Network {
        static let requestTimeout: TimeInterval = 15
    }

    enum Time {
        static let secondsPerHour: TimeInterval = 3600
        static let secondsPerDay: TimeInterval = 86_400
    }

    enum Preferences {
        static let resetSoundEnabled = "resetSoundEnabled"
    }

    enum Sounds {
        static let criticalReset = "Tink"
    }

    enum GitHub {
        static let profile = URL(string: "https://github.com/xerno")!
        static let repository = URL(string: "https://github.com/xerno/ClaudeMonitor")!
        static let issues = URL(string: "https://github.com/xerno/ClaudeMonitor/issues")!
    }

    enum Demo {
        static let isActive: Bool = ProcessInfo.processInfo.arguments.contains("--demo")
        static let rotationOrder: [Int] = [3, 2, 1, 4]
        static let rotationInterval: TimeInterval = 5
    }

    enum History {
        static let deduplicationInterval: TimeInterval = 30
        static let gapThreshold: TimeInterval = 300
        static let archiveRetentionMultiplier = 11
    }

    enum Projection {
        static let boldThreshold: Double = 80
        static let warningThreshold: Double = 100
        static let criticalThreshold: Double = 120
        static let blockedUtilization: Int = 100
        static let fallbackBoldThreshold: Int = 80
        static let fallbackWarningThreshold: Int = 90
        static let fallbackCriticalThreshold: Int = 95
    }
}
