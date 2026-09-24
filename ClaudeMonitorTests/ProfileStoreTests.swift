import Foundation
import Testing
@testable import ClaudeMonitor

@MainActor
@Suite struct ProfileStoreTests {
    private func makeStore(
        secrets: InMemorySecrets = InMemorySecrets(),
        defaults: UserDefaults = makeTestDefaults("profiles")
    ) -> (ProfileStore, UserDefaults) {
        (makeTestProfileStore(secrets: secrets, defaults: defaults), defaults)
    }

    private func makeLegacySecrets(cookie: String = "legacy-cookie", orgId: String = UUID().uuidString) -> InMemorySecrets {
        let secrets = InMemorySecrets()
        secrets.store[Constants.Keychain.cookieString] = cookie
        secrets.store[Constants.Keychain.organizationId] = orgId
        return secrets
    }

    @Test func migratesLegacyCredentialsIntoProfileOne() throws {
        let orgId = UUID().uuidString
        let (store, defaults) = makeStore(secrets: makeLegacySecrets(orgId: orgId))

        #expect(store.profiles.count == 1)
        let active = try #require(store.activeProfile)
        #expect(active.organizationId == orgId)
        #expect(!active.name.isEmpty)
        #expect(active.name != "profiles.migrated_default_name")
        #expect(store.activeCookie == "legacy-cookie")
        #expect(defaults.object(forKey: Constants.Profiles.registryKey) != nil)
    }

    @Test func migrationRemovesLegacyKeys() {
        let secrets = makeLegacySecrets()

        _ = makeStore(secrets: secrets)

        #expect(secrets.store[Constants.Keychain.cookieString] == nil)
        #expect(secrets.store[Constants.Keychain.organizationId] == nil)
    }

    @Test func migrationSaveFailureDoesNotWriteMarker() {
        let secrets = makeLegacySecrets()
        secrets.isSaveFailing = true
        let defaults = makeTestDefaults("migration-save-failure")

        let (failed, _) = makeStore(secrets: secrets, defaults: defaults)

        #expect(failed.profiles.isEmpty)
        #expect(defaults.object(forKey: Constants.Profiles.registryKey) == nil)
        #expect(secrets.store[Constants.Keychain.cookieString] == "legacy-cookie")
        #expect(secrets.store[Constants.Keychain.organizationId] != nil)

        secrets.isSaveFailing = false
        let (retried, _) = makeStore(secrets: secrets, defaults: defaults)

        #expect(retried.profiles.count == 1)
        #expect(retried.activeCookie == "legacy-cookie")
        #expect(defaults.object(forKey: Constants.Profiles.registryKey) != nil)
    }

    @Test func migrationSkipsInvalidLegacyOrgId() {
        let secrets = makeLegacySecrets(orgId: "not-a-uuid")

        let (store, _) = makeStore(secrets: secrets)

        #expect(store.profiles.isEmpty)
        #expect(store.activeProfile == nil)
        #expect(secrets.store[Constants.Keychain.cookieString] == "legacy-cookie")
    }

    @Test func partialLegacyCredentialsDoNotMigrate() {
        let partialSets: [[String: String]] = [
            [Constants.Keychain.cookieString: "legacy-cookie"],
            [Constants.Keychain.organizationId: UUID().uuidString],
            [Constants.Keychain.cookieString: "", Constants.Keychain.organizationId: UUID().uuidString],
            [Constants.Keychain.cookieString: "legacy-cookie", Constants.Keychain.organizationId: ""],
        ]
        for partial in partialSets {
            let secrets = InMemorySecrets()
            secrets.store = partial

            let (store, _) = makeStore(secrets: secrets)

            #expect(store.profiles.isEmpty, "must not migrate from \(partial)")
            #expect(store.activeProfile == nil)
        }
    }

    @Test func migrationRunTwiceIsIdempotent() {
        let secrets = makeLegacySecrets()
        let defaults = makeTestDefaults("migration-twice")

        let (first, _) = makeStore(secrets: secrets, defaults: defaults)
        let (second, _) = makeStore(secrets: secrets, defaults: defaults)

        #expect(first.profiles.count == 1)
        #expect(second.profiles == first.profiles)
        #expect(second.activeId == first.activeId)
    }

    @Test func freshInstallWithNoLegacyMigratesToEmpty() {
        let (store, defaults) = makeStore()

        #expect(store.profiles.isEmpty)
        #expect(store.activeProfile == nil)
        #expect(defaults.object(forKey: Constants.Profiles.registryKey) != nil)
    }

    @Test func doesNotReMigrateWhenRegistryAlreadyExists() throws {
        let defaults = makeTestDefaults("noremigrate")
        defaults.set(try JSONEncoder().encode([Profile]()), forKey: Constants.Profiles.registryKey)

        let (store, _) = makeStore(secrets: makeLegacySecrets(cookie: "stale"), defaults: defaults)

        #expect(store.profiles.isEmpty)
        #expect(store.activeProfile == nil)
    }

    @Test func undecodableRegistryIsQuarantinedNotOverwritten() throws {
        let defaults = makeTestDefaults("corrupt-registry")
        let garbage = Data("not json".utf8)
        defaults.set(garbage, forKey: Constants.Profiles.registryKey)

        let (store, _) = makeStore(defaults: defaults)

        #expect(store.profiles.isEmpty)
        let quarantined = defaults.dictionaryRepresentation()
            .filter { $0.key.hasPrefix(Constants.Profiles.corruptRegistryKeyPrefix) }
        #expect(quarantined.count == 1)
        let preserved = try #require(quarantined.first?.value as? Data)
        #expect(preserved == garbage)
    }

    @Test func registryEntryWithInvalidOrgIdIsIgnored() throws {
        let defaults = makeTestDefaults("invalid-org")
        let valid = Profile(name: "Valid", organizationId: UUID().uuidString)
        let invalid = Profile(name: "Invalid", organizationId: "not-a-uuid")
        defaults.set(try JSONEncoder().encode([invalid, valid]), forKey: Constants.Profiles.registryKey)

        let (store, _) = makeStore(defaults: defaults)

        #expect(store.profiles == [valid])
        #expect(store.activeProfile == valid)
        let quarantinedKeys = defaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(Constants.Profiles.corruptRegistryKeyPrefix)
        }
        #expect(quarantinedKeys.count == 1)
        #expect(defaults.object(forKey: Constants.Profiles.registryKey) != nil)
    }

    @Test func addProfileStoresItAndItsCookie() throws {
        let (store, _) = makeStore()
        let profile = try store.addProfile(name: "Work", organizationId: UUID().uuidString, cookie: "c1")

        #expect(store.profiles.contains(profile))
        #expect(store.cookie(for: profile) == "c1")
    }

    @Test func addDoesNotChangeActive() throws {
        let (store, _) = makeStore()
        #expect(store.activeProfile == nil)
        _ = try store.addProfile(name: "Work", organizationId: UUID().uuidString, cookie: "c1")
        #expect(store.activeProfile == nil)
    }

    @Test func addProfileRejectsBeyondMaxCount() throws {
        let (store, _) = makeStore()
        for index in 0..<Constants.Profiles.maxCount {
            _ = try store.addProfile(name: "P\(index)", organizationId: UUID().uuidString, cookie: "c\(index)")
        }
        #expect(!store.canAddProfile)

        #expect(throws: ProfileStoreError.limitReached) {
            _ = try store.addProfile(name: "Extra", organizationId: UUID().uuidString, cookie: "c")
        }
        #expect(store.profiles.count == Constants.Profiles.maxCount)
    }

    @Test func addProfileSaveFailureLeavesRegistryUnchanged() throws {
        let secrets = InMemorySecrets()
        let (store, defaults) = makeStore(secrets: secrets)
        let existing = try store.addProfile(name: "Existing", organizationId: UUID().uuidString, cookie: "c1")
        let registryBefore = defaults.data(forKey: Constants.Profiles.registryKey)

        secrets.isSaveFailing = true
        #expect(throws: ProfileStoreError.saveFailed) {
            _ = try store.addProfile(name: "New", organizationId: UUID().uuidString, cookie: "c2")
        }

        #expect(store.profiles == [existing])
        #expect(defaults.data(forKey: Constants.Profiles.registryKey) == registryBefore)
    }

    @Test func setActiveSelectsProfile() throws {
        let (store, _) = makeStore()
        let p = try store.addProfile(name: "Work", organizationId: UUID().uuidString, cookie: "c1")

        #expect(store.setActive(id: p.id))
        #expect(store.activeProfile == p)
        #expect(store.activeCookie == "c1")
    }

    @Test func setActiveIgnoresUnknownId() throws {
        let (store, _) = makeStore()
        let p = try store.addProfile(name: "Work", organizationId: UUID().uuidString, cookie: "c1")
        store.setActive(id: p.id)

        #expect(!store.setActive(id: "does-not-exist"))
        #expect(store.activeProfile == p)
    }

    @Test func rejectsDuplicateOrganizationId() throws {
        let (store, _) = makeStore()
        let orgId = UUID().uuidString
        _ = try store.addProfile(name: "Personal", organizationId: orgId, cookie: "c1")

        #expect(throws: ProfileStoreError.duplicateOrganization) {
            _ = try store.addProfile(name: "Work", organizationId: orgId, cookie: "c2")
        }
        #expect(store.profiles.count == 1)
    }

    @Test func addRejectsDuplicateOrganizationDifferingOnlyInCase() throws {
        let (store, _) = makeStore()
        let orgId = UUID().uuidString.uppercased()
        _ = try store.addProfile(name: "Personal", organizationId: orgId, cookie: "c1")

        #expect(throws: ProfileStoreError.duplicateOrganization) {
            _ = try store.addProfile(name: "Work", organizationId: orgId.lowercased(), cookie: "c2")
        }
        #expect(store.profiles.count == 1)
    }

    @Test func updateRejectsDuplicateOrganizationDifferingOnlyInCase() throws {
        let (store, _) = makeStore()
        let orgB = UUID().uuidString.uppercased()
        let a = try store.addProfile(name: "A", organizationId: UUID().uuidString, cookie: "c1")
        _ = try store.addProfile(name: "B", organizationId: orgB, cookie: "c2")

        #expect(throws: ProfileStoreError.duplicateOrganization) {
            try store.updateProfile(id: a.id, name: "A", organizationId: orgB.lowercased(), cookie: "c1")
        }
    }

    @Test func removeProfileDropsItAndItsCookie() throws {
        let secrets = InMemorySecrets()
        let (store, _) = makeStore(secrets: secrets)
        let p = try store.addProfile(name: "Work", organizationId: UUID().uuidString, cookie: "c1")
        store.setActive(id: p.id)

        store.removeProfile(id: p.id)

        #expect(store.profiles.isEmpty)
        #expect(store.activeProfile == nil)
        #expect(secrets.store[Constants.Profiles.cookieKey(profileId: p.id)] == nil)
    }

    @Test func removeActiveFallsBackToRemaining() throws {
        let (store, _) = makeStore()
        let a = try store.addProfile(name: "A", organizationId: UUID().uuidString, cookie: "c1")
        let b = try store.addProfile(name: "B", organizationId: UUID().uuidString, cookie: "c2")
        store.setActive(id: a.id)

        store.removeProfile(id: a.id)

        #expect(store.activeProfile == b)
    }

    @Test func removeNonActiveKeepsActive() throws {
        let (store, _) = makeStore()
        let a = try store.addProfile(name: "A", organizationId: UUID().uuidString, cookie: "c1")
        let b = try store.addProfile(name: "B", organizationId: UUID().uuidString, cookie: "c2")
        store.setActive(id: b.id)

        store.removeProfile(id: a.id)

        #expect(store.profiles == [b])
        #expect(store.activeProfile == b)
    }

    @Test func profilesPersistAcrossInstances() throws {
        let secrets = InMemorySecrets()
        let defaults = makeTestDefaults("persist")

        let (storeA, _) = makeStore(secrets: secrets, defaults: defaults)
        let p = try storeA.addProfile(name: "Work", organizationId: UUID().uuidString, cookie: "c1")
        storeA.setActive(id: p.id)

        let (storeB, _) = makeStore(secrets: secrets, defaults: defaults)

        #expect(storeB.profiles == storeA.profiles)
        #expect(storeB.activeProfile == p)
    }

    @Test func updateProfileChangesNameOrgAndCookie() throws {
        let (store, _) = makeStore()
        let p = try store.addProfile(name: "Old", organizationId: UUID().uuidString, cookie: "c1")
        let newOrg = UUID().uuidString

        try store.updateProfile(id: p.id, name: "New", organizationId: newOrg, cookie: "c2")

        let updated = try #require(store.profiles.first { $0.id == p.id })
        #expect(updated.name == "New")
        #expect(updated.organizationId == newOrg)
        #expect(store.cookie(for: updated) == "c2")
    }

    @Test func updateUnknownIdIsNoOp() throws {
        let secrets = InMemorySecrets()
        let (store, defaults) = makeStore(secrets: secrets)
        let existing = try store.addProfile(name: "A", organizationId: UUID().uuidString, cookie: "c1")
        let registryBefore = defaults.data(forKey: Constants.Profiles.registryKey)
        let secretsBefore = secrets.store

        try store.updateProfile(id: "does-not-exist", name: "X", organizationId: UUID().uuidString, cookie: "c2")

        #expect(store.profiles == [existing])
        #expect(defaults.data(forKey: Constants.Profiles.registryKey) == registryBefore)
        #expect(secrets.store == secretsBefore)
    }

    @Test func updateRejectsOrgUsedByAnotherProfile() throws {
        let (store, _) = makeStore()
        let orgB = UUID().uuidString
        let a = try store.addProfile(name: "A", organizationId: UUID().uuidString, cookie: "c1")
        _ = try store.addProfile(name: "B", organizationId: orgB, cookie: "c2")

        #expect(throws: ProfileStoreError.duplicateOrganization) {
            try store.updateProfile(id: a.id, name: "A", organizationId: orgB, cookie: "c1")
        }
    }

    @Test func updateAllowsKeepingOwnOrg() throws {
        let (store, _) = makeStore()
        let orgId = UUID().uuidString
        let p = try store.addProfile(name: "A", organizationId: orgId, cookie: "c1")

        try store.updateProfile(id: p.id, name: "A renamed", organizationId: orgId, cookie: "c2")

        #expect(store.profiles.first { $0.id == p.id }?.name == "A renamed")
        #expect(store.cookie(for: p) == "c2")
    }

    @Test func staleActiveIdReconcilesToFirstProfile() throws {
        let defaults = makeTestDefaults("stale")
        let profile = Profile(name: "Only", organizationId: UUID().uuidString)
        defaults.set(try JSONEncoder().encode([profile]), forKey: Constants.Profiles.registryKey)
        defaults.set("ghost-id", forKey: Constants.Profiles.activeIdKey)

        let (store, _) = makeStore(defaults: defaults)

        #expect(store.activeProfile == profile)
    }
}
