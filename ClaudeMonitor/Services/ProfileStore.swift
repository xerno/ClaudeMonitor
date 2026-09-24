import Foundation

enum ProfileStoreError: Error, Equatable {
    case duplicateOrganization
    case saveFailed
    case limitReached
}

@MainActor
final class ProfileStore {
    private let defaults: UserDefaults
    let loadSecret: (String) -> String?
    let saveSecret: (String, String) -> Bool
    let removeSecret: (String) -> Void

    private(set) var profiles: [Profile]
    private(set) var activeId: String?

    static func production() -> ProfileStore {
        ProfileStore(
            defaults: .standard,
            loadSecret: { EncryptedDefaultsService.load(key: $0) },
            saveSecret: { EncryptedDefaultsService.save(key: $0, value: $1) },
            removeSecret: { EncryptedDefaultsService.remove(key: $0) }
        )
    }

    init(
        defaults: UserDefaults,
        loadSecret: @escaping (String) -> String?,
        saveSecret: @escaping (String, String) -> Bool,
        removeSecret: @escaping (String) -> Void
    ) {
        let isUnderTest = ProcessInfo.processInfo.environment[BuildInfo.underTestEnvVar] != nil
        if isUnderTest && defaults === UserDefaults.standard {
            preconditionFailure("ProfileStore must never be constructed with UserDefaults.standard during tests — inject an isolated suite instead (see TestPreferencesRoot).")
        }
        self.defaults = defaults
        self.loadSecret = loadSecret
        self.saveSecret = saveSecret
        self.removeSecret = removeSecret

        profiles = Self.loadRegistry(from: defaults)
        activeId = defaults.string(forKey: Constants.Profiles.activeIdKey)

        migrateLegacyCredentialsIfNeeded()
        reconcileActiveId()
    }

    var activeProfile: Profile? {
        guard let activeId else { return nil }
        return profiles.first { $0.id == activeId }
    }

    var activeCookie: String? {
        activeProfile.flatMap { cookie(for: $0) }
    }

    var canAddProfile: Bool {
        profiles.count < Constants.Profiles.maxCount
    }

    func cookie(for profile: Profile) -> String? {
        loadSecret(Constants.Profiles.cookieKey(profileId: profile.id))
    }

    @discardableResult
    func addProfile(name: String, organizationId: String, cookie: String) throws -> Profile {
        guard canAddProfile else {
            throw ProfileStoreError.limitReached
        }
        guard !isOrganizationInUse(organizationId) else {
            throw ProfileStoreError.duplicateOrganization
        }
        let profile = Profile(name: name, organizationId: organizationId)
        guard saveSecret(Constants.Profiles.cookieKey(profileId: profile.id), cookie) else {
            throw ProfileStoreError.saveFailed
        }
        profiles.append(profile)
        persist()
        return profile
    }

    func updateProfile(id: String, name: String, organizationId: String, cookie: String) throws {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else { return }
        guard !isOrganizationInUse(organizationId, excludingProfileId: id) else {
            throw ProfileStoreError.duplicateOrganization
        }
        guard saveSecret(Constants.Profiles.cookieKey(profileId: id), cookie) else {
            throw ProfileStoreError.saveFailed
        }
        profiles[index].name = name
        profiles[index].organizationId = organizationId
        persist()
    }

    func removeProfile(id: String) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        removeSecret(Constants.Profiles.cookieKey(profileId: id))
        profiles.removeAll { $0.id == id }
        if activeId == id {
            activeId = profiles.first?.id
        }
        persist()
    }

    @discardableResult
    func setActive(id: String) -> Bool {
        guard profiles.contains(where: { $0.id == id }) else { return false }
        activeId = id
        persistActiveId()
        return true
    }

    private func migrateLegacyCredentialsIfNeeded() {
        guard defaults.object(forKey: Constants.Profiles.registryKey) == nil else { return }
        switch migrateLegacyCredentials() {
        case .nothingToMigrate:
            persist()
        case .migrated(let profile):
            profiles = [profile]
            activeId = profile.id
            persist()
            removeLegacyCredentials()
        case .saveFailed:
            break
        }
    }

    private func reconcileActiveId() {
        guard activeProfile == nil else { return }
        activeId = profiles.first?.id
        persistActiveId()
    }

    private func isOrganizationInUse(_ organizationId: String, excludingProfileId excludedId: String? = nil) -> Bool {
        profiles.contains { $0.id != excludedId && Self.isSameOrganization($0.organizationId, organizationId) }
    }

    private static func isSameOrganization(_ lhs: String, _ rhs: String) -> Bool {
        if let lhsUUID = UUID(uuidString: lhs), let rhsUUID = UUID(uuidString: rhs) {
            return lhsUUID == rhsUUID
        }
        return lhs.caseInsensitiveCompare(rhs) == .orderedSame
    }

    private static func loadRegistry(from defaults: UserDefaults) -> [Profile] {
        guard let stored = defaults.object(forKey: Constants.Profiles.registryKey) else { return [] }
        guard let data = stored as? Data,
              let decoded = try? JSONDecoder().decode([Profile].self, from: data) else {
            quarantineRegistry(stored, in: defaults)
            defaults.removeObject(forKey: Constants.Profiles.registryKey)
            return []
        }
        let valid = decoded.filter { UUID(uuidString: $0.organizationId) != nil }
        if valid.count != decoded.count {
            quarantineRegistry(stored, in: defaults)
        }
        return valid
    }

    private static func quarantineRegistry(_ stored: Any, in defaults: UserDefaults) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        defaults.set(stored, forKey: Constants.Profiles.corruptRegistryKeyPrefix + timestamp)
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Constants.Profiles.registryKey)
        }
        persistActiveId()
    }

    private func persistActiveId() {
        if let activeId {
            defaults.set(activeId, forKey: Constants.Profiles.activeIdKey)
        } else {
            defaults.removeObject(forKey: Constants.Profiles.activeIdKey)
        }
    }
}
