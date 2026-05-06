import Foundation
@testable import ClaudeMonitor

@MainActor
func makeCoordinator(
    fixture: UsageHistoryTestFixture,
    status: any StatusFetching = MockStatusService(),
    usage: any UsageFetching = MockUsageService(),
    idle: any SystemIdleProviding = MockSystemIdleProvider(),
    path: (any PathMonitoring)? = nil,
    testOrgId: String = UUID().uuidString,
    credentials: [String: String]? = nil
) -> (DataCoordinator, String) {
    let creds = credentials ?? [
        Constants.Keychain.cookieString: "test-cookie",
        Constants.Keychain.organizationId: testOrgId,
    ]
    let coordinator = DataCoordinator(
        statusService: status,
        usageService: usage,
        systemIdleProvider: idle,
        pathMonitor: path ?? MockPathMonitor(),
        loadCredential: { creds[$0] },
        usageHistory: fixture.history
    )
    return (coordinator, testOrgId)
}
