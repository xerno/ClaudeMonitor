import Foundation
import Testing
@testable import ClaudeMonitor

@Suite(.serialized) @MainActor struct UsageHistoryRetentionTests {
    private static let fixedNow: Date = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 12))!
    }()

    // MARK: - Calendar-based cutoff

    @Test func retentionCutoffUsesCalendarYearsNotFixedSeconds() {
        // 2024-03-01 minus one year spans Feb 29: a 365-day approximation lands a day off.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2024, month: 3, day: 1, hour: 12))!
        let expectedCutoff = calendar.date(from: DateComponents(year: 2023, month: 3, day: 1, hour: 12))!

        let cutoff = UsageHistory.retentionCutoff(years: 1, now: now)
        #expect(cutoff == expectedCutoff)
    }

    @Test func archiveJustInsideRetentionSurvivesJustOutsideIsDeleted() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)
        let fm = FileManager.default
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try fm.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let formatter = archiveDateFormatterForTests()

        let now = Self.fixedNow
        let years = 2
        let cutoff = UsageHistory.retentionCutoff(years: years, now: now)!

        let insideEnd = cutoff.addingTimeInterval(3600)
        let insideStart = insideEnd.addingTimeInterval(-18000)
        let insideURL = identityDir.appendingPathComponent("\(formatter.string(from: insideStart))_\(formatter.string(from: insideEnd)).\(Constants.History.windowInstanceFileExtension)")
        try Data().write(to: insideURL)

        let outsideEnd = cutoff.addingTimeInterval(-3600)
        let outsideStart = outsideEnd.addingTimeInterval(-18000)
        let outsideURL = identityDir.appendingPathComponent("\(formatter.string(from: outsideStart))_\(formatter.string(from: outsideEnd)).\(Constants.History.windowInstanceFileExtension)")
        try Data().write(to: outsideURL)

        await history.pruneArchives(retentionYears: years, now: now)

        #expect(fm.fileExists(atPath: insideURL.path), "Archive just inside retention must survive")
        #expect(!fm.fileExists(atPath: outsideURL.path), "Archive just outside retention must be deleted")
    }

    @Test func archiveExactlyAtCutoffSurvivesOneSecondOlderIsDeleted() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)
        let fm = FileManager.default
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try fm.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let formatter = archiveDateFormatterForTests()

        let now = Self.fixedNow
        let years = 2
        let cutoff = UsageHistory.retentionCutoff(years: years, now: now)!

        func writeArchive(end: Date) throws -> URL {
            let start = end.addingTimeInterval(-18000)
            let url = identityDir.appendingPathComponent("\(formatter.string(from: start))_\(formatter.string(from: end)).\(Constants.History.windowInstanceFileExtension)")
            try Data().write(to: url)
            return url
        }

        let exactlyAtCutoff = try writeArchive(end: cutoff)
        let oneSecondOlder = try writeArchive(end: cutoff.addingTimeInterval(-1))

        await history.pruneArchives(retentionYears: years, now: now)

        #expect(fm.fileExists(atPath: exactlyAtCutoff.path), "An archive ending exactly at the cutoff instant must survive")
        #expect(!fm.fileExists(atPath: oneSecondOlder.path), "An archive one second older than the cutoff must be deleted")
    }

    // MARK: - Defensive clamping on read

    @Test func retentionYearsClampsCorruptOrAbsentValuesToDefault() {
        let suiteName = TestPreferencesRoot.makeSuiteName("UsageHistoryRetentionTests.clamp")
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.removeObject(forKey: Constants.Preferences.historyRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == Constants.History.defaultRetentionYears)

        for badValue in [0, -1, 100] {
            defaults.set(badValue, forKey: Constants.Preferences.historyRetentionYears)
            #expect(Constants.History.retentionYears(defaults: defaults) == Constants.History.defaultRetentionYears,
                    "Stored value \(badValue) must resolve to the default")
        }

        defaults.set(1, forKey: Constants.Preferences.historyRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == 1)
        defaults.set(99, forKey: Constants.Preferences.historyRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == 99)
    }

    @Test func clampRetentionYearsRestrictsToBounds() {
        #expect(Constants.History.clampRetentionYears(0) == Constants.History.minRetentionYears)
        #expect(Constants.History.clampRetentionYears(-50) == Constants.History.minRetentionYears)
        #expect(Constants.History.clampRetentionYears(1) == 1)
        #expect(Constants.History.clampRetentionYears(99) == 99)
        #expect(Constants.History.clampRetentionYears(100) == Constants.History.maxRetentionYears)
        #expect(Constants.History.clampRetentionYears(1000) == Constants.History.maxRetentionYears)
    }

    // MARK: - Would-delete count computed without deleting

    @Test func archivedWindowCountMatchesWhatWouldBeDeletedAndDeletesNothing() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)
        let fm = FileManager.default
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try fm.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let formatter = archiveDateFormatterForTests()

        let now = Self.fixedNow
        let oldRetentionYears = 5
        let newRetentionYears = 1
        let oldCutoff = UsageHistory.retentionCutoff(years: oldRetentionYears, now: now)!
        let newCutoff = UsageHistory.retentionCutoff(years: newRetentionYears, now: now)!
        #expect(oldCutoff < newCutoff)

        func writeArchive(end: Date) throws -> URL {
            let start = end.addingTimeInterval(-18000)
            let url = identityDir.appendingPathComponent("\(formatter.string(from: start))_\(formatter.string(from: end)).\(Constants.History.windowInstanceFileExtension)")
            try Data().write(to: url)
            return url
        }

        let doomed1End = newCutoff.addingTimeInterval(-3600)
        let doomed2End = newCutoff.addingTimeInterval(-7200)
        let survivorEnd = newCutoff.addingTimeInterval(3600)
        let doomed1 = try writeArchive(end: doomed1End)
        let doomed2 = try writeArchive(end: doomed2End)
        let survivor = try writeArchive(end: survivorEnd)

        #expect(doomed1End > oldCutoff && doomed2End > oldCutoff)
        #expect(survivorEnd > newCutoff)

        let count = await history.archivedWindowCount(retentionYears: newRetentionYears, now: now)
        #expect(count == 2, "Exactly the two archives older than the new cutoff should be counted")

        #expect(fm.fileExists(atPath: doomed1.path))
        #expect(fm.fileExists(atPath: doomed2.path))
        #expect(fm.fileExists(atPath: survivor.path))

        await history.pruneArchives(retentionYears: newRetentionYears, now: now)
        #expect(!fm.fileExists(atPath: doomed1.path))
        #expect(!fm.fileExists(atPath: doomed2.path))
        #expect(fm.fileExists(atPath: survivor.path))
    }

    // MARK: - Windows that vanish from the API

    @Test func windowAbsentBeyondThresholdIsArchived() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let now = Self.fixedNow
        let duration: TimeInterval = 18000 // five_hour
        let entry = makeEntry(key: "five_hour", utilization: 40, resetsAt: now.addingTimeInterval(duration))
        history.record(entries: [entry], at: now)

        await history.archiveMissingWindows(currentIdentities: [], at: now)
        #expect(history.storage[entry.storageIdentity] != nil, "A single missing poll must not archive")

        let later = now.addingTimeInterval(duration + 1)
        await history.archiveMissingWindows(currentIdentities: [], at: later)
        #expect(history.storage[entry.storageIdentity] == nil, "Should be archived once unambiguously gone")

        let archiveDir = history.archiveDirectory.appendingPathComponent(entry.storageIdentity)
        let files = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(!files.isEmpty, "Missing window must be archived, not merely dropped")
    }

    @Test func windowMissingForOnlyASingleRefreshIsNotArchived() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        history.switchOrganization(UUID().uuidString)
        let now = Self.fixedNow
        let duration: TimeInterval = 18000
        let entry = makeEntry(key: "five_hour", utilization: 40, resetsAt: now.addingTimeInterval(duration))
        history.record(entries: [entry], at: now)

        await history.archiveMissingWindows(currentIdentities: [], at: now.addingTimeInterval(60))
        await history.archiveMissingWindows(currentIdentities: [entry.storageIdentity], at: now.addingTimeInterval(120))

        #expect(history.storage[entry.storageIdentity] != nil, "Window must not be archived once it reappears")

        await history.archiveMissingWindows(currentIdentities: [], at: now.addingTimeInterval(180))
        await history.archiveMissingWindows(currentIdentities: [], at: now.addingTimeInterval(180 + duration - 1))
        #expect(history.storage[entry.storageIdentity] != nil, "Must not archive before a full duration has elapsed since it went missing again")
    }

    /// Goes through `refresh`: the `.fresh`-only gate lives in `AccountMonitor.refresh`, not `UsageHistory`.
    @Test func archiveMissingWindowsOnlyRunsAfterSuccessfulFetchesNotFailedOnes() async throws {
        let fixture = UsageHistoryTestFixture()
        let history = fixture.history
        let testOrgId = UUID().uuidString
        history.switchOrganization(testOrgId)
        let now = Self.fixedNow
        let duration: TimeInterval = 18000 // five_hour
        let entry = makeEntry(key: "five_hour", utilization: 40, resetsAt: now.addingTimeInterval(duration))
        history.record(entries: [entry], at: now)

        let mockUsage = MockUsageService()
        mockUsage.result = .failure(ServiceError.unexpectedStatus(500))
        let (coordinator, _) = makeCoordinator(fixture: fixture, usage: mockUsage, testOrgId: testOrgId)
        let archiveDir = history.archiveDirectory.appendingPathComponent(entry.storageIdentity)

        await coordinator.refresh(now: now.addingTimeInterval(duration + 1))
        #expect(history.storage[entry.storageIdentity] != nil, "A failed fetch must not archive a missing window")
        let filesAfterFailure = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(filesAfterFailure.isEmpty, "A failed fetch must not archive anything")

        mockUsage.result = .success(UsageResponse(entries: []))
        let firstMissingSuccess = now.addingTimeInterval(duration + 2)
        await coordinator.refresh(now: firstMissingSuccess)
        #expect(history.storage[entry.storageIdentity] != nil, "A single successful poll missing the window must not archive immediately")

        await coordinator.refresh(now: firstMissingSuccess.addingTimeInterval(duration + 1))
        #expect(history.storage[entry.storageIdentity] == nil, "A window absent across successful fetches for a full duration must be archived")
        let filesAfterSuccess = (try? FileManager.default.contentsOfDirectory(at: archiveDir, includingPropertiesForKeys: nil)) ?? []
        #expect(!filesAfterSuccess.isEmpty, "Missing window must be archived once confirmed gone across successful fetches")
    }
}
