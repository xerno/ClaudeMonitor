import Foundation

extension DataCoordinator {
    var hasCredentials: Bool {
        Constants.Demo.isActive || loadedCredentials != nil
    }

    func reloadCredentials() {
        guard !Constants.Demo.isActive,
              let cookie = loadCredential(Constants.Keychain.cookieString),
              let orgId = loadCredential(Constants.Keychain.organizationId),
              !cookie.isEmpty, !orgId.isEmpty else {
            if loadedCredentials != nil {
                usageHistory.switchOrganization(nil)
                windowAnalyses = []
            }
            loadedCredentials = nil
            return
        }
        let previousOrgId = loadedCredentials?.orgId
        loadedCredentials = (cookie, orgId)
        if orgId != previousOrgId {
            usageHistory.switchOrganization(orgId)
            windowAnalyses = []
        }
    }
}
