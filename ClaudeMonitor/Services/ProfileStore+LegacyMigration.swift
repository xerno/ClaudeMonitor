import Foundation

extension ProfileStore {
    enum LegacyMigrationOutcome {
        case nothingToMigrate
        case migrated(Profile)
        case saveFailed
    }

    func migrateLegacyCredentials() -> LegacyMigrationOutcome {
        guard let cookie = loadSecret(Constants.Keychain.cookieString), !cookie.isEmpty,
              let organizationId = loadSecret(Constants.Keychain.organizationId),
              UUID(uuidString: organizationId) != nil else {
            return .nothingToMigrate
        }
        let profile = Profile(
            name: String(localized: "profiles.migrated_default_name", bundle: .module),
            organizationId: organizationId
        )
        guard saveSecret(Constants.Profiles.cookieKey(profileId: profile.id), cookie) else {
            return .saveFailed
        }
        return .migrated(profile)
    }

    func removeLegacyCredentials() {
        removeSecret(Constants.Keychain.cookieString)
        removeSecret(Constants.Keychain.organizationId)
    }
}
