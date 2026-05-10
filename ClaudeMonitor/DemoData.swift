import Foundation

enum DemoData {
    struct DemoFrame {
        let usage: UsageResponse
        let status: StatusSummary
        let samples: [String: [UtilizationSample]]
        let isOnline: Bool
        let isAnyServiceStale: Bool
        let hasRecentFailure: Bool
        let lastFailedAt: Date?
        let pollInterval: TimeInterval
    }

    private static let allOperationalComponents = [
        StatusComponent(id: "1", name: "API", status: .operational),
        StatusComponent(id: "2", name: "Claude.ai Web", status: .operational),
        StatusComponent(id: "3", name: "claude.ai on iOS", status: .operational),
        StatusComponent(id: "4", name: "API Cloudflare Worker", status: .operational),
    ]

    static func scenario(_ number: Int) -> DemoFrame {
        switch number {
        case 1: return scenario1()
        case 2: return scenario2()
        case 3: return scenario3()
        case 4: return scenario4()
        case 5: return scenario5()
        case 6: return scenario6()
        case 7: return scenario7()
        default: return scenario1()
        }
    }

    private static func makeSamples(_ offsets: [(TimeInterval, Int)], resetsAt: Date) -> [UtilizationSample] {
        offsets.map { UtilizationSample(utilization: $0.1, timestamp: resetsAt.addingTimeInterval($0.0)) }
    }

    private static let sampleData: [String: [(TimeInterval, Int)]] = {
        guard let url = Bundle.module.url(forResource: "DemoSamples", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [[Double]]].self, from: data)
        else { return [:] }
        return raw.mapValues { $0.map { ($0[0], Int($0[1])) } }
    }()

    private static func scenario1() -> DemoFrame {
        let (usage, samples) = makeS1UsageAndSamples()
        let status = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "API", status: .majorOutage),
                StatusComponent(id: "2", name: "Claude.ai Web", status: .partialOutage),
                StatusComponent(id: "3", name: "claude.ai on iOS", status: .operational),
                StatusComponent(id: "4", name: "API Cloudflare Worker", status: .operational),
            ],
            incidents: [
                Incident(
                    id: "i1",
                    name: "API Errors and Degraded Performance",
                    shortlink: "https://stspg.io/demo1a"
                ),
                Incident(
                    id: "i2",
                    name: "Elevated Error Rates on claude.ai",
                    shortlink: "https://stspg.io/demo1b"
                ),
            ]
        )
        return DemoFrame(usage: usage, status: status, samples: samples, isOnline: true, isAnyServiceStale: false, hasRecentFailure: false, lastFailedAt: nil, pollInterval: 80)
    }

    private static func scenario2() -> DemoFrame {
        let (usage, samples) = makeS2UsageAndSamples()
        let status = StatusSummary(
            components: [
                StatusComponent(id: "1", name: "API", status: .degradedPerformance),
                StatusComponent(id: "2", name: "Claude.ai Web", status: .operational),
                StatusComponent(id: "3", name: "claude.ai on iOS", status: .operational),
                StatusComponent(id: "4", name: "API Cloudflare Worker", status: .operational),
            ],
            incidents: [
                Incident(
                    id: "i3",
                    name: "Increased API Latency",
                    shortlink: "https://stspg.io/demo2"
                ),
            ]
        )
        return DemoFrame(usage: usage, status: status, samples: samples, isOnline: true, isAnyServiceStale: false, hasRecentFailure: false, lastFailedAt: nil, pollInterval: 60)
    }

    private static func scenario3() -> DemoFrame {
        let (usage, samples) = makeS3UsageAndSamples()
        return DemoFrame(usage: usage, status: allSystemsOperationalStatus, samples: samples, isOnline: true, isAnyServiceStale: false, hasRecentFailure: false, lastFailedAt: nil, pollInterval: 24)
    }

    private static func scenario4() -> DemoFrame {
        let resetsAt5h = Date().addingTimeInterval(2.25 * Constants.Time.secondsPerHour)
        let resetsAt7d = Date().addingTimeInterval(3.5 * Constants.Time.secondsPerDay)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 100, resetsAt: resetsAt5h)!,
            .make(key: "seven_day", utilization: 38, resetsAt: resetsAt7d)!,
            .make(key: "seven_day_sonnet", utilization: 22, resetsAt: resetsAt7d)!,
        ])
        let samples = [
            "five_hour": makeSamples(sampleData["s4_5h"] ?? [], resetsAt: resetsAt5h),
            "seven_day": makeSamples(sampleData["s4_7d"] ?? [], resetsAt: resetsAt7d),
            "seven_day_sonnet": makeSamples(sampleData["s4_7d_sonnet"] ?? [], resetsAt: resetsAt7d),
        ]
        return DemoFrame(usage: usage, status: allSystemsOperationalStatus, samples: samples, isOnline: true, isAnyServiceStale: false, hasRecentFailure: false, lastFailedAt: nil, pollInterval: 300)
    }

    private static let allSystemsOperationalStatus = StatusSummary(
        components: allOperationalComponents,
        incidents: []
    )

    private static func makeS1UsageAndSamples() -> (UsageResponse, [String: [UtilizationSample]]) {
        let resetsAt5h = Date().addingTimeInterval(2.7 * Constants.Time.secondsPerHour)
        let resetsAt7d = Date().addingTimeInterval(4.5 * Constants.Time.secondsPerDay)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 42, resetsAt: resetsAt5h)!,
            .make(key: "seven_day", utilization: 18, resetsAt: resetsAt7d)!,
        ])
        let samples = [
            "five_hour": makeSamples(sampleData["s1_5h"] ?? [], resetsAt: resetsAt5h),
            "seven_day": makeSamples(sampleData["s1_7d"] ?? [], resetsAt: resetsAt7d),
        ]
        return (usage, samples)
    }

    private static func makeS2UsageAndSamples() -> (UsageResponse, [String: [UtilizationSample]]) {
        let resetsAt5h = Date().addingTimeInterval(1.4 * Constants.Time.secondsPerHour)
        let resetsAt7d = Date().addingTimeInterval(4.2 * Constants.Time.secondsPerDay)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 74, resetsAt: resetsAt5h)!,
            .make(key: "seven_day", utilization: 61, resetsAt: resetsAt7d)!,
        ])
        let samples = [
            "five_hour": makeSamples(sampleData["s2_5h"] ?? [], resetsAt: resetsAt5h),
            "seven_day": makeSamples(sampleData["s2_7d"] ?? [], resetsAt: resetsAt7d),
        ]
        return (usage, samples)
    }

    private static func makeS3UsageAndSamples() -> (UsageResponse, [String: [UtilizationSample]]) {
        let resetsAt5h = Date().addingTimeInterval(0.8 * Constants.Time.secondsPerHour)
        let resetsAt7d = Date().addingTimeInterval(1.5 * Constants.Time.secondsPerDay)
        let usage = UsageResponse(entries: [
            .make(key: "five_hour", utilization: 91, resetsAt: resetsAt5h)!,
            .make(key: "seven_day", utilization: 85, resetsAt: resetsAt7d)!,
            .make(key: "seven_day_sonnet", utilization: 52, resetsAt: resetsAt7d)!,
        ])
        let samples = [
            "five_hour": makeSamples(sampleData["s3_5h"] ?? [], resetsAt: resetsAt5h),
            "seven_day": makeSamples(sampleData["s3_7d"] ?? [], resetsAt: resetsAt7d),
            "seven_day_sonnet": makeSamples(sampleData["s3_7d_sonnet"] ?? [], resetsAt: resetsAt7d),
        ]
        return (usage, samples)
    }

    private static func scenario5() -> DemoFrame {
        let (usage, samples) = makeS2UsageAndSamples()
        return DemoFrame(usage: usage, status: allSystemsOperationalStatus, samples: samples, isOnline: true, isAnyServiceStale: false, hasRecentFailure: true, lastFailedAt: Date().addingTimeInterval(-90), pollInterval: 53)
    }

    private static func scenario6() -> DemoFrame {
        let (usage, samples) = makeS3UsageAndSamples()
        return DemoFrame(usage: usage, status: allSystemsOperationalStatus, samples: samples, isOnline: false, isAnyServiceStale: true, hasRecentFailure: false, lastFailedAt: Date().addingTimeInterval(-180), pollInterval: 40)
    }

    private static func scenario7() -> DemoFrame {
        let (usage, samples) = makeS1UsageAndSamples()
        return DemoFrame(usage: usage, status: allSystemsOperationalStatus, samples: samples, isOnline: true, isAnyServiceStale: true, hasRecentFailure: false, lastFailedAt: Date().addingTimeInterval(-240), pollInterval: 120)
    }
}
