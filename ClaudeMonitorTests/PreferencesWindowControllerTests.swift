import AppKit
import Foundation
import Testing
@testable import ClaudeMonitor

/// Stands in for the `NSAlert` decrease confirmation.
@MainActor
final class RetentionConfirmationRecorder {
    private(set) var wasConsulted = false
    private(set) var lastNewValue: Int?
    private(set) var lastDeletingCount: Int?
    private let answer: Bool

    init(answer: Bool) {
        self.answer = answer
    }

    func confirm(newValue: Int, deletingCount: Int) async -> Bool {
        wasConsulted = true
        lastNewValue = newValue
        lastDeletingCount = deletingCount
        return answer
    }
}

@MainActor
@Suite struct PreferencesWindowControllerTests {
    // MARK: - clampedYears

    @Test func clampedYearsPassesThroughValueInRange() {
        #expect(RetentionDisplay.clampedYears(5) == 5)
    }

    @Test func clampedYearsClampsBelowMinimum() {
        let clamped = RetentionDisplay.clampedYears(Constants.History.minRetentionYears - 1)
        #expect(clamped == Constants.History.minRetentionYears)
    }

    @Test func clampedYearsClampsAboveMaximum() {
        let clamped = RetentionDisplay.clampedYears(Constants.History.maxRetentionYears + 1)
        #expect(clamped == Constants.History.maxRetentionYears)
    }

    @Test func clampedYearsAtBoundariesIsUnchanged() {
        #expect(RetentionDisplay.clampedYears(Constants.History.minRetentionYears) == Constants.History.minRetentionYears)
        #expect(RetentionDisplay.clampedYears(Constants.History.maxRetentionYears) == Constants.History.maxRetentionYears)
    }

    // MARK: - RetentionPartialInputFormatter

    @Test func partialInputAcceptsEmptyAndValidDigitStrings() {
        let formatter = RetentionPartialInputFormatter()
        for candidate in ["", "0", "5", "99", "07"] {
            #expect(formatter.isPartialStringValid(candidate, newEditingString: nil, errorDescription: nil),
                    "expected candidate to be accepted")
        }
    }

    @Test func partialInputRejectsNonDigitOrOverlongStrings() {
        let formatter = RetentionPartialInputFormatter()
        for candidate in ["a", "1a", "1.5", "-1", "100", "5 ", "\u{00BD}", "\u{2163}"] {
            #expect(!formatter.isPartialStringValid(candidate, newEditingString: nil, errorDescription: nil),
                    "expected candidate to be rejected")
        }
    }

    // MARK: - loadSavedValues / isRetentionAlertPresented

    /// `showWindow` reloads on every show, even with a confirmation sheet up; clearing the flag
    /// would let a second retention change start.
    @Test func loadSavedValuesDoesNotClearAPresentedAlertFlag() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        controller.isRetentionAlertPresented = true
        controller.loadSavedValues()

        #expect(controller.isRetentionAlertPresented == true)
    }

    @Test func loadSavedValuesResyncsDisplayedRetentionWhenNoAlertIsPending() {
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = Constants.Preferences.historyRetentionYears

        defaults.set(3, forKey: key)
        let fixture = UsageHistoryTestFixture()
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        #expect(controller.displayedRetentionYears == 3)

        defaults.set(7, forKey: key)
        controller.loadSavedValues()
        #expect(controller.displayedRetentionYears == 7,
                "loadSavedValues must resync the displayed retention value from persisted state when no alert is pending.")
    }

    // MARK: - Wiring

    /// Without this, the pure-formatter tests would cover a formatter the field doesn't use.
    @Test func retentionFieldFormatterIsTheRealPartialInputFormatter() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        #expect(controller.installedRetentionFormatter is RetentionPartialInputFormatter)
    }

    /// `NSStepper.valueWraps` defaults to true, which wraps a decrement at the minimum to the maximum.
    @Test func retentionStepperConfigurationMatchesConstantsAndDoesNotWrap() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        let config = controller.retentionStepperConfiguration
        #expect(config.minValue == Double(Constants.History.minRetentionYears))
        #expect(config.maxValue == Double(Constants.History.maxRetentionYears))
        #expect(config.valueWraps == false)
    }

    // MARK: - Keystroke refusal (through the installed formatter)

    @Test func installedFormatterRefusesThirdDigitOfTypingNineNineNine() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let formatter = controller.installedRetentionFormatter

        #expect(formatter?.isPartialStringValid("9", newEditingString: nil, errorDescription: nil) == true)
        #expect(formatter?.isPartialStringValid("99", newEditingString: nil, errorDescription: nil) == true)
        #expect(formatter?.isPartialStringValid("999", newEditingString: nil, errorDescription: nil) == false)
    }

    @Test func installedFormatterRefusesNonDigitKeystroke() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let formatter = controller.installedRetentionFormatter

        #expect(formatter?.isPartialStringValid("1", newEditingString: nil, errorDescription: nil) == true)
        #expect(formatter?.isPartialStringValid("1a", newEditingString: nil, errorDescription: nil) == false)
    }

    @Test func installedFormatterAcceptsNonASCIIDecimalDigitsAndTheyCommit() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let formatter = controller.installedRetentionFormatter

        // Arabic-Indic 5, fullwidth 5.
        #expect(formatter?.isPartialStringValid("\u{0665}", newEditingString: nil, errorDescription: nil) == true)
        #expect(formatter?.isPartialStringValid("\u{FF15}", newEditingString: nil, errorDescription: nil) == true)

        // Accepting must also commit: an ASCII-only read would store 1.
        #expect(RetentionDisplay.parsedYears(fromFieldText: "\u{0665}") == 5)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "\u{FF15}") == 5)

        // Vulgar fraction, Roman numeral: numeric but not decimal.
        #expect(formatter?.isPartialStringValid("\u{00BD}", newEditingString: nil, errorDescription: nil) == false)
        #expect(formatter?.isPartialStringValid("\u{2163}", newEditingString: nil, errorDescription: nil) == false)
    }

    // MARK: - End-to-end commit: what actually gets persisted

    /// An increase, so it never reaches confirmation.
    @Test func enteringNinetyNinePersistsAndDisplaysNinetyNine() async {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        controller.simulateRetentionFieldEntry("99")
        await controller.awaitPendingRetentionChange()

        #expect(controller.displayedRetentionYears == 99)
        #expect(Constants.History.retentionYears(defaults: defaults) == 99)
    }

    /// 0 clamps to the current value (a no-op), yet the field must still repaint:
    /// `setRetentionDisplay` runs before the no-change guard.
    @Test func enteringZeroAtMinimumStaysAtMinimumNotZero() async {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Constants.History.minRetentionYears, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        controller.simulateRetentionFieldEntry("0")
        await controller.awaitPendingRetentionChange()

        #expect(controller.displayedRetentionYears == Constants.History.minRetentionYears)
    }

    /// An increase, so it never reaches confirmation.
    @Test func stepperDrivenAboveMaximumPersistsAndDisplaysMaximum() async {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        controller.simulateRetentionStepperEntry(Constants.History.maxRetentionYears + 50)
        await controller.awaitPendingRetentionChange()

        #expect(controller.displayedRetentionYears == Constants.History.maxRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == Constants.History.maxRetentionYears)
    }

    // MARK: - Decrease confirmation: injected seam, no real NSAlert

    @Test func enteringZeroFromAboveMinimumWithNoArchivesAppliesImmediately() async {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(5, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: false)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("0")
        await controller.awaitPendingRetentionChange()

        #expect(controller.displayedRetentionYears == Constants.History.minRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == Constants.History.minRetentionYears,
                "with nothing to delete, a decrease must still commit without user confirmation")
    }

    @Test func enteringZeroWithConfirmationDeclinedRevertsToOriginalValue() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let oldEnd = calendar.date(byAdding: .year, value: -3, to: now)!
        try Self.writeArchiveFile(in: identityDir, end: oldEnd)

        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(5, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: false)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("0")
        await controller.awaitPendingRetentionChange()

        #expect(recorder.wasConsulted == true, "a 3-year-old archive is old enough to be deleted, so confirmation must be requested")
        #expect(controller.displayedRetentionYears == 5, "declining the confirmation must revert the field to the original value")
        #expect(Constants.History.retentionYears(defaults: defaults) == 5, "declining the confirmation must not persist the decrease")
    }

    @Test func enteringZeroWithConfirmationAcceptedPersistsMinimum() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let oldEnd = calendar.date(byAdding: .year, value: -3, to: now)!
        try Self.writeArchiveFile(in: identityDir, end: oldEnd)

        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(5, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: true)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("0")
        await controller.awaitPendingRetentionChange()

        #expect(recorder.wasConsulted == true, "a 3-year-old archive is old enough to be deleted, so confirmation must be requested")
        #expect(controller.displayedRetentionYears == Constants.History.minRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == Constants.History.minRetentionYears)
    }

    @Test func enteringDoubleZeroWithConfirmationAcceptedPersistsMinimum() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let oldEnd = calendar.date(byAdding: .year, value: -3, to: now)!
        try Self.writeArchiveFile(in: identityDir, end: oldEnd)

        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(5, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: true)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("00")
        await controller.awaitPendingRetentionChange()

        #expect(recorder.wasConsulted == true, "a 3-year-old archive is old enough to be deleted, so confirmation must be requested")
        #expect(controller.displayedRetentionYears == Constants.History.minRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == Constants.History.minRetentionYears)
    }

    @Test func enteringEmptyStringWithConfirmationAcceptedPersistsMinimum() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let oldEnd = calendar.date(byAdding: .year, value: -3, to: now)!
        try Self.writeArchiveFile(in: identityDir, end: oldEnd)

        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(5, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: true)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("")
        await controller.awaitPendingRetentionChange()

        #expect(recorder.wasConsulted == true, "a 3-year-old archive is old enough to be deleted, so confirmation must be requested")
        #expect(controller.displayedRetentionYears == Constants.History.minRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == Constants.History.minRetentionYears)
    }

    // MARK: - Confirmation wiring: real archives on disk, no mocking

    /// An empty file suffices: `collectArchiveFiles` reads only the end date from the filename.
    private static func writeArchiveFile(in directory: URL, end: Date) throws {
        let formatter = archiveDateFormatterForTests()
        let start = end.addingTimeInterval(-18000)
        let url = directory.appendingPathComponent(
            "\(formatter.string(from: start))_\(formatter.string(from: end)).\(Constants.History.windowInstanceFileExtension)")
        try Data().write(to: url)
    }

    @Test func decreaseWithNothingOldEnoughToDeleteAppliesSilently() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let recentEnd = calendar.date(byAdding: .month, value: -3, to: now)!
        try Self.writeArchiveFile(in: identityDir, end: recentEnd)

        let sanityCount = await fixture.history.archivedWindowCount(retentionYears: 90, now: now)
        #expect(sanityCount == 0, "a 3-month-old archive must not be counted under a 90-year retention cutoff")

        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Constants.History.maxRetentionYears, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: false)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("90")
        await controller.awaitPendingRetentionChange()

        #expect(recorder.wasConsulted == false, "no archive is old enough to delete, so confirmation must never be requested")
        #expect(controller.displayedRetentionYears == 90)
        #expect(Constants.History.retentionYears(defaults: defaults) == 90)
    }

    /// The survivor archive (younger than the cutoff) proves the count isn't simply every archive.
    @Test func decreaseThatWouldDeleteRequiresConfirmationWithExactCount() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let cutoffOneYear = calendar.date(byAdding: .year, value: -1, to: now)!

        let doomed1 = cutoffOneYear.addingTimeInterval(-3600 * 24 * 400)
        let doomed2 = cutoffOneYear.addingTimeInterval(-3600 * 24 * 800)
        let survivor = calendar.date(byAdding: .month, value: -3, to: now)!
        try Self.writeArchiveFile(in: identityDir, end: doomed1)
        try Self.writeArchiveFile(in: identityDir, end: doomed2)
        try Self.writeArchiveFile(in: identityDir, end: survivor)

        let sanityCount = await fixture.history.archivedWindowCount(retentionYears: 1, now: now)
        #expect(sanityCount == 2, "exactly the two archives older than the 1-year cutoff must be counted")

        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(2, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: true)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("1")
        await controller.awaitPendingRetentionChange()

        #expect(recorder.wasConsulted == true, "two archives are old enough to delete, so confirmation must be requested")
        #expect(recorder.lastDeletingCount == 2, "confirmation must report exactly the count that would actually be deleted, not merely a nonzero count")
        #expect(controller.displayedRetentionYears == 1)
        #expect(Constants.History.retentionYears(defaults: defaults) == 1)
    }

    /// Catches counting against the current retention instead of the proposed one: both archives
    /// are past the new (2-year) cutoff but inside the current (5-year) one.
    @Test func confirmationCountIsComputedForNewValueNotCurrentValue() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let newCutoff = calendar.date(byAdding: .year, value: -2, to: now)!
        let currentCutoff = calendar.date(byAdding: .year, value: -5, to: now)!

        let entry1 = newCutoff.addingTimeInterval(-3600 * 24 * 30)
        let entry2 = newCutoff.addingTimeInterval(-3600 * 24 * 60)
        try Self.writeArchiveFile(in: identityDir, end: entry1)
        try Self.writeArchiveFile(in: identityDir, end: entry2)

        let sanityCountUnderNew = await fixture.history.archivedWindowCount(retentionYears: 2, now: now)
        #expect(sanityCountUnderNew == 2, "both archives must be older than the 2-year (new-value) cutoff")
        let sanityCountUnderCurrent = await fixture.history.archivedWindowCount(retentionYears: 5, now: now)
        #expect(sanityCountUnderCurrent == 0, "neither archive is old enough to be counted under the 5-year (current-value) cutoff")
        #expect(currentCutoff < newCutoff, "a longer retention's cutoff must be chronologically before a shorter retention's")

        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(5, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: true)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("2")
        await controller.awaitPendingRetentionChange()

        #expect(recorder.wasConsulted == true,
                "the count must be computed against the new value's (2-year) cutoff, under which archives exist to delete")
        #expect(recorder.lastDeletingCount == 2,
                "the reported count must match the new value's cutoff, not the current value's")
        #expect(controller.displayedRetentionYears == 2)
        #expect(Constants.History.retentionYears(defaults: defaults) == 2)
    }

    @Test func increaseNeverConsultsConfirmationEvenWithOldArchives() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        for yearsAgo in [6, 7, 8] {
            let end = calendar.date(byAdding: .year, value: -yearsAgo, to: now)!
            try Self.writeArchiveFile(in: identityDir, end: end)
        }

        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(1, forKey: Constants.Preferences.historyRetentionYears)
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let recorder = RetentionConfirmationRecorder(answer: false)
        controller.retentionDecreaseConfirmationOverride = { newValue, count in
            await recorder.confirm(newValue: newValue, deletingCount: count)
        }

        controller.simulateRetentionFieldEntry("99")
        await controller.awaitPendingRetentionChange()

        #expect(recorder.wasConsulted == false, "an increase must never trigger confirmation regardless of what archives exist")
        #expect(controller.displayedRetentionYears == Constants.History.maxRetentionYears)
        #expect(Constants.History.retentionYears(defaults: defaults) == Constants.History.maxRetentionYears)
    }

    @Test func generalToggleAppliesImmediately() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, _) = Self.makeIsolatedDefaults()
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        controller.simulateShowGraphToggle(false)
        controller.simulateCompactServicesToggle(false)
        #expect(Constants.Preferences.isUsageGraphEnabled(in: defaults) == false)
        #expect(Constants.Preferences.isServicesCompact(in: defaults) == false)

        controller.simulateShowGraphToggle(true)
        controller.simulateCompactServicesToggle(true)
        #expect(Constants.Preferences.isUsageGraphEnabled(in: defaults) == true)
        #expect(Constants.Preferences.isServicesCompact(in: defaults) == true)
    }

    @Test func displayToggleNotifiesMenu() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, _) = Self.makeIsolatedDefaults()
        var notificationCount = 0
        let controller = Self.makeController(history: fixture.history, defaults: defaults) {
            notificationCount += 1
        }

        controller.simulateShowGraphToggle(false)
        controller.simulateCompactServicesToggle(false)

        #expect(notificationCount == 2)
    }

    @Test func unsetSettingsShowAsOn() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, _) = Self.makeIsolatedDefaults()
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        #expect(controller.displayedShowGraph == true)
        #expect(controller.displayedCompactServices == true)
    }

    @Test func showWindowWhileVisibleKeepsEdits() throws {
        let fixture = UsageHistoryTestFixture()
        let (defaults, _) = Self.makeIsolatedDefaults()
        let store = makeTestProfileStore(secrets: InMemorySecrets(), label: "prefs")
        let profile = try store.addProfile(name: "Work", organizationId: UUID().uuidString, cookie: "cookie")
        let controller = Self.makeController(history: fixture.history, defaults: defaults, profileStore: store)
        let form = try #require(controller.accountForm(forProfileId: profile.id))

        form.simulateEntry(name: "Edited", organizationId: profile.organizationId, cookie: "cookie")
        controller.prepareForDisplay(isWindowVisible: true)

        #expect(controller.accountForm(forProfileId: profile.id) === form)
        #expect(form.displayedName == "Edited")

        controller.prepareForDisplay(isWindowVisible: false)

        #expect(controller.accountForm(forProfileId: profile.id)?.displayedName == "Work")
    }

    @Test func addTabHiddenAtMaxCount() throws {
        let fixture = UsageHistoryTestFixture()
        let (defaults, _) = Self.makeIsolatedDefaults()
        let store = makeTestProfileStore(secrets: InMemorySecrets(), label: "prefs")
        let profiles = try (0..<Constants.Profiles.maxCount).map { index in
            try store.addProfile(name: "Account \(index)", organizationId: UUID().uuidString, cookie: "cookie")
        }
        let controller = Self.makeController(history: fixture.history, defaults: defaults, profileStore: store)

        #expect(controller.isAddAccountTabShown == false)

        let removed = try #require(profiles.first)
        controller.removeAccount(id: removed.id)

        #expect(controller.isAddAccountTabShown == true)
    }

    @Test func removingAccountKeepsOtherTabsEdits() throws {
        let fixture = UsageHistoryTestFixture()
        let (defaults, _) = Self.makeIsolatedDefaults()
        let store = makeTestProfileStore(secrets: InMemorySecrets(), label: "prefs")
        let kept = try store.addProfile(name: "Kept", organizationId: UUID().uuidString, cookie: "cookie")
        let removed = try store.addProfile(name: "Removed", organizationId: UUID().uuidString, cookie: "cookie")
        let controller = Self.makeController(history: fixture.history, defaults: defaults, profileStore: store)
        let keptForm = try #require(controller.accountForm(forProfileId: kept.id))

        keptForm.simulateEntry(name: "Edited", organizationId: kept.organizationId, cookie: "cookie")
        controller.removeAccount(id: removed.id)

        #expect(store.profiles.map(\.id) == [kept.id])
        #expect(controller.accountTabIdentifiers == [kept.id])
        #expect(controller.accountForm(forProfileId: kept.id) === keptForm)
        #expect(keptForm.displayedName == "Edited")
    }

    @Test func setupUpsertsExistingOrgWhenActiveCookieUnreadable() throws {
        let secrets = InMemorySecrets()
        let store = makeTestProfileStore(secrets: secrets, label: "setup")
        let orgId = UUID().uuidString
        let profile = try store.addProfile(name: "Work", organizationId: orgId, cookie: "stale")
        store.setActive(id: profile.id)
        secrets.remove(Constants.Profiles.cookieKey(profileId: profile.id))
        let form = CredentialFormView(profileStore: store, mode: .setup)

        form.simulateEntry(name: "Work", organizationId: orgId, cookie: "fresh")
        let savedId = form.validateAndSave(in: Self.makeOffscreenWindow())

        #expect(savedId == profile.id)
        #expect(store.profiles.count == 1)
        #expect(store.activeId == profile.id)
        #expect(store.activeCookie == "fresh")
    }

    @Test func setupActivatesNewProfileWhenActiveCookieUnreadable() throws {
        let secrets = InMemorySecrets()
        let store = makeTestProfileStore(secrets: secrets, label: "setup")
        let existing = try store.addProfile(name: "Old", organizationId: UUID().uuidString, cookie: "stale")
        store.setActive(id: existing.id)
        secrets.remove(Constants.Profiles.cookieKey(profileId: existing.id))
        let form = CredentialFormView(profileStore: store, mode: .setup)

        form.simulateEntry(name: "New", organizationId: UUID().uuidString, cookie: "fresh")
        let savedId = try #require(form.validateAndSave(in: Self.makeOffscreenWindow()))

        #expect(savedId != existing.id)
        #expect(store.profiles.count == 2)
        #expect(store.activeId == savedId)
        #expect(store.activeCookie == "fresh")
    }

    private static func makeController(
        history: UsageHistory,
        defaults: UserDefaults,
        profileStore: ProfileStore? = nil,
        onDisplaySettingsChanged: @escaping () -> Void = {}
    ) -> PreferencesWindowController {
        PreferencesWindowController(
            usageHistories: { [history] },
            profileStore: profileStore ?? makeTestProfileStore(secrets: InMemorySecrets()),
            defaults: defaults,
            onDisplaySettingsChanged: onDisplaySettingsChanged,
            onSave: {}
        )
    }

    private static func makeOffscreenWindow() -> NSWindow {
        NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
    }

    // MARK: - Isolated UserDefaults helper

    /// Never `UserDefaults.standard`: the running app reads that domain. The suite name is returned
    /// because `UserDefaults` cannot report its own.
    private static func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = TestPreferencesRoot.makeSuiteName("PreferencesWindowControllerTests")
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
