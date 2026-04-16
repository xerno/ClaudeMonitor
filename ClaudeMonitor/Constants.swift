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
        static let cooldownStart: TimeInterval = 300    // 5 min: timeSinceLastChange to start cooldown
        static let cooldownEnd: TimeInterval = 3600     // 60 min: timeSinceLastChange for full cooldown
        static let maxIdleInterval: TimeInterval = 300  // Idle at desk cap
        static let maxAwayInterval: TimeInterval = 3600 // Away cap (60 min)
        static let awayThreshold: TimeInterval = 300    // systemIdle to enter Away mode
        static let awayRampEnd: TimeInterval = 7200     // systemIdle for max Away interval
        static let heartbeatInterval: TimeInterval = 60 // heartbeat check interval in Away mode
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
