import Foundation
@testable import ClaudeMonitor

enum TestFixtures {
    static func status() -> StatusSummary {
        StatusSummary(
            components: [StatusComponent(id: "1", name: "API", status: .operational)],
            incidents: []
        )
    }

    static func usage() -> UsageResponse {
        UsageResponse(entries: [
            WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                        window: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(3600))),
            WindowEntry(key: "seven_day", duration: 604_800, durationLabel: "7d", modelScope: nil,
                        window: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(86400))),
        ])
    }
}

final class MockStatusService: StatusFetching, @unchecked Sendable {
    var result: Result<StatusSummary, Error> = .success(TestFixtures.status())
    var fetchCount = 0
    var beforeReturn: (@Sendable () async -> Void)?

    func fetch() async throws -> StatusSummary {
        fetchCount += 1
        if let beforeReturn {
            await beforeReturn()
        }
        return try result.get()
    }
}

final class MockUsageService: UsageFetching, @unchecked Sendable {
    var result: Result<UsageResponse, Error> = .success(TestFixtures.usage())
    var resultsByOrgId: [String: Result<UsageResponse, Error>] = [:]
    var fetchCount = 0
    var lastOrgId: String?
    var lastCookie: String?

    /// Opt-in suspension hook for tests that need a `fetch()` call to genuinely suspend
    /// mid-flight (e.g. to construct an org-switch-during-in-flight-fetch race). Awaited
    /// inside `fetch` only when non-nil, right before the result is returned, so every
    /// existing test (which never sets this) sees byte-for-byte unchanged behaviour —
    /// `fetch` returns synchronously-in-effect with no added suspension point.
    var beforeReturn: (@Sendable () async -> Void)?

    func fetch(organizationId: String, cookieString: String) async throws -> UsageResponse {
        fetchCount += 1
        lastOrgId = organizationId
        lastCookie = cookieString
        if let beforeReturn {
            await beforeReturn()
        }
        return try (resultsByOrgId[organizationId] ?? result).get()
    }
}

final class MockSystemIdleProvider: SystemIdleProviding, @unchecked Sendable {
    var idleTimeValue: TimeInterval = 0
    func idleTime() -> TimeInterval { idleTimeValue }
}

final class MockPathMonitor: PathMonitoring {
    @MainActor private(set) var isSatisfied: Bool
    @MainActor private var onPathChange: (@MainActor (Bool) -> Void)?

    init(initialSatisfied: Bool = true) {
        isSatisfied = initialSatisfied
    }

    @MainActor func setOnPathChange(_ handler: @escaping @MainActor (Bool) -> Void) {
        onPathChange = handler
    }

    nonisolated func start() {}
    nonisolated func cancel() {}

    @MainActor func simulate(satisfied: Bool) {
        guard satisfied != isSatisfied else { return }
        isSatisfied = satisfied
        onPathChange?(satisfied)
    }
}
