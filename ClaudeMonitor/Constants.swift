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

        static var userAgent: String {
            let v = ProcessInfo.processInfo.operatingSystemVersion
            return "Mozilla/5.0 (Macintosh; Intel Mac OS X \(v.majorVersion)_\(v.minorVersion)_\(v.patchVersion)) AppleWebKit/605.1.15 (KHTML, like Gecko)"
        }

        static func usageURL(organizationId: String) -> URL? {
            URL(string: "\(usageBasePath)/\(organizationId)/usage")
        }
    }

    enum Polling {
        static let baseInterval: TimeInterval = 60
        static let minInterval: TimeInterval = 24
        static let maxInterval: TimeInterval = 600
        static let criticalFloor: TimeInterval = 120
        static let speedupFactor: Double = 0.8
        static let cooldownCycles: Int = 3
        static let highUtilizationThreshold: Int = 90
    }

    enum UsageWindows {
        static let fiveHourDuration: TimeInterval = 5 * 3600
        static let sevenDayDuration: TimeInterval = 7 * 86400
    }

    enum Retry {
        static let initialBackoff: TimeInterval = 10
        static let maxBackoff: TimeInterval = 300
        static let failureThreshold = 2
        static let staleDataMaxAge: TimeInterval = 3600
    }

    enum Network {
        static let requestTimeout: TimeInterval = 15
    }

    enum Preferences {
        static let resetSoundEnabled = "resetSoundEnabled"
    }

    enum Sounds {
        static let criticalReset = "Tink"
    }

    enum Demo {
        static let isActive: Bool = ProcessInfo.processInfo.arguments.contains("--demo")
        static let rotationOrder: [Int] = [3, 2, 1, 4]
        static let rotationInterval: TimeInterval = 5
    }
}
