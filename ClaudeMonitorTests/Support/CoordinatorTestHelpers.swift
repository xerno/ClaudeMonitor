import Foundation
import Testing
@testable import ClaudeMonitor

func makeTestDefaults(_ label: String) -> UserDefaults {
    UserDefaults(suiteName: TestPreferencesRoot.makeSuiteName(label))!
}

@MainActor
func makeTestProfileStore(
    secrets: InMemorySecrets,
    label: String = "coord",
    defaults: UserDefaults? = nil
) -> ProfileStore {
    ProfileStore(
        defaults: defaults ?? makeTestDefaults(label),
        loadSecret: { secrets.load($0) },
        saveSecret: { secrets.save($0, $1) },
        removeSecret: { secrets.remove($0) }
    )
}

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
    let defaults = makeTestDefaults("coord")
    let store = makeTestProfileStore(secrets: InMemorySecrets(), defaults: defaults)
    if let cookie = creds[Constants.Keychain.cookieString],
       let orgId = creds[Constants.Keychain.organizationId],
       !cookie.isEmpty, !orgId.isEmpty {
        do {
            let profile = try store.addProfile(name: "Test", organizationId: orgId, cookie: cookie)
            store.setActive(id: profile.id)
        } catch {
            Issue.record(error)
        }
    }

    let coordinator = DataCoordinator(
        statusService: status,
        usageService: usage,
        systemIdleProvider: idle,
        pathMonitor: path ?? MockPathMonitor(),
        profileStore: store,
        defaults: defaults,
        usageHistory: fixture.history
    )
    return (coordinator, testOrgId)
}
