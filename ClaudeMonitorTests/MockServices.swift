import Foundation
@testable import ClaudeMonitor

let testStatus = StatusSummary(
    components: [StatusComponent(id: "1", name: "API", status: .operational)],
    incidents: [],
    status: PageStatus(indicator: "none", description: "All Systems Operational")
)

let testUsage = UsageResponse(entries: [
    WindowEntry(key: "five_hour", duration: 18000, durationLabel: "5h", modelScope: nil,
                window: UsageWindow(utilization: 42, resetsAt: Date().addingTimeInterval(3600))),
    WindowEntry(key: "seven_day", duration: 604_800, durationLabel: "7d", modelScope: nil,
                window: UsageWindow(utilization: 18, resetsAt: Date().addingTimeInterval(86400))),
])

final class MockStatusService: StatusFetching, @unchecked Sendable {
    var result: Result<StatusSummary, Error> = .success(testStatus)
    var fetchCount = 0

    func fetch() async throws -> StatusSummary {
        fetchCount += 1
        return try result.get()
    }
}

final class MockUsageService: UsageFetching, @unchecked Sendable {
    var result: Result<UsageResponse, Error> = .success(testUsage)
    var fetchCount = 0
    var lastOrgId: String?
    var lastCookie: String?

    func fetch(organizationId: String, cookieString: String) async throws -> UsageResponse {
        fetchCount += 1
        lastOrgId = organizationId
        lastCookie = cookieString
        return try result.get()
    }
}

final class MockSystemIdleProvider: SystemIdleProviding, @unchecked Sendable {
    var idleTimeValue: TimeInterval = 0
    func idleTime() -> TimeInterval { idleTimeValue }
}
