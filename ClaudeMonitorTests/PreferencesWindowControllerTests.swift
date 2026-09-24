import AppKit
import Foundation
import Testing
@testable import ClaudeMonitor

/// Records whether/how `PreferencesWindowController.retentionDecreaseConfirmationOverride` was
/// consulted, so a test can assert not just the final persisted value but that a decrease
/// confirmation was (or was NOT) reached at all — and, when it was, the exact `deletingCount`
/// it was told — without driving a real `NSAlert`. `@MainActor` because the controller that
/// calls it, and every test that reads it back, are themselves `@MainActor`.
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

/// Covers `RetentionDisplay`, the pure (non-AppKit) logic extracted from
/// `PreferencesWindowController` so it's testable without constructing any `NSStepper`/
/// `NSTextField`/window: the clamping `retentionStepperChanged`/`retentionFieldChanged` apply to
/// their raw control value. Also covers `RetentionPartialInputFormatter`'s keystroke-level
/// validation, and the `isRetentionAlertPresented` / `loadSavedValues` interaction directly,
/// against a real (but headless, off-screen) `PreferencesWindowController` — see the
/// "loadSavedValues" tests below.
///
/// What this suite does NOT cover, because it requires driving actual Cocoa modals, which the
/// project's tests never do: presenting/dismissing the confirmation sheet itself (`NSAlert`),
/// and the rest of `applyRetentionChange`/`confirmRetentionDecrease`'s AppKit wiring.
/// `RetentionChangeDecisionTests` separately covers the count-then-maybe-confirm decision logic.
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

    /// Regression test for the confirmed defect: `showWindow` calls `loadSavedValues`
    /// unconditionally on every invocation, including a second "Preferences…" while the window
    /// is already open with a decrease-confirmation sheet on screen. `loadSavedValues` used to
    /// unconditionally clear `isRetentionAlertPresented`, which reopened the exact concurrent-flow
    /// hole the flag exists to close (see `applyRetentionChange`'s `guard !isRetentionAlertPresented`).
    /// This constructs a real (off-screen, never-shown) controller — cheap because `NSWindow`
    /// construction alone doesn't touch the screen — and drives `loadSavedValues` directly rather
    /// than through `showWindow`/an actual `NSAlert` sheet.
    @Test func loadSavedValuesDoesNotClearAPresentedAlertFlag() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        controller.isRetentionAlertPresented = true
        controller.loadSavedValues()

        #expect(controller.isRetentionAlertPresented == true)
    }

    /// Complements the above: when no alert is pending, `loadSavedValues` must actually resync
    /// the displayed retention value from persisted state
    /// (`Constants.History.retentionYears(defaults:)`) — not merely leave a flag that has no path
    /// to becoming `true` sitting at `false`. A prior version of this test only asserted the
    /// latter, which would have passed even if the resync logic it purports to guard were
    /// entirely broken. `displayedRetentionYears` exposes the field's current value for exactly
    /// this.
    ///
    /// Uses an isolated `UserDefaults(suiteName:)` instance, injected via
    /// `PreferencesWindowController.init(defaults:)`, rather than `UserDefaults.standard` — the
    /// same process-global-state hazard `TestHistoryRoot` exists to avoid for the filesystem: a
    /// `defer`-based restore of `.standard` fails to protect anything if the test traps, the
    /// process is killed mid-run, or another test interleaves, and the real running app reads
    /// that exact same domain.
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

    /// If this fails, every keystroke test below (and the pure-formatter tests above) is
    /// vacuous: they'd be exercising a formatter that isn't actually attached to the field the
    /// user types into.
    @Test func retentionFieldFormatterIsTheRealPartialInputFormatter() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)

        #expect(controller.installedRetentionFormatter is RetentionPartialInputFormatter)
    }

    /// Regression guard for a real reported defect: with `valueWraps` left at its default
    /// (`true`), decrementing at the minimum wrapped around to the maximum. Asserts against
    /// `Constants.History.minRetentionYears`/`maxRetentionYears` rather than literal `1`/`99` so
    /// this doesn't silently drift out of sync if those bounds ever change.
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

    /// Simulates typing "999" one keystroke at a time through the field's *installed*
    /// formatter, matching the user's literal complaint: the third keystroke — the one that
    /// would make the field show "999" — must be the one refused, not merely "some string
    /// containing 999 fails somewhere."
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

    /// Same prefix-walk for a non-digit keystroke: "1" accepted, "1a" (the keystroke that adds
    /// the letter) refused.
    @Test func installedFormatterRefusesNonDigitKeystroke() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let formatter = controller.installedRetentionFormatter

        #expect(formatter?.isPartialStringValid("1", newEditingString: nil, errorDescription: nil) == true)
        #expect(formatter?.isPartialStringValid("1a", newEditingString: nil, errorDescription: nil) == false)
    }

    /// Non-ASCII DECIMAL digits must now be ACCEPTED, and this test previously asserted the
    /// opposite. Its original rationale was sound at the time — the commit path read
    /// `NSTextField.integerValue`, which parses ASCII only, so accepting `\u{0665}` really would
    /// have let the field display a value that could not be committed. That constraint is gone:
    /// `RetentionDisplay.parsedYears` now reads the field's text under the same rules this
    /// formatter accepts, so the pair agrees for every decimal numbering system. Rejecting them
    /// made the field appear to accept no input at all on an Arabic-Indic or Devanagari keyboard.
    @Test func installedFormatterAcceptsNonASCIIDecimalDigitsAndTheyCommit() {
        let fixture = UsageHistoryTestFixture()
        let (defaults, suiteName) = Self.makeIsolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let controller = Self.makeController(history: fixture.history, defaults: defaults)
        let formatter = controller.installedRetentionFormatter

        // Arabic-Indic five, and fullwidth five.
        #expect(formatter?.isPartialStringValid("\u{0665}", newEditingString: nil, errorDescription: nil) == true)
        #expect(formatter?.isPartialStringValid("\u{FF15}", newEditingString: nil, errorDescription: nil) == true)

        // Accepting a keystroke is only correct if the same text also commits to the value the
        // user meant — the half-fix (relax the guard, keep the ASCII-only read) would store 1.
        #expect(RetentionDisplay.parsedYears(fromFieldText: "\u{0665}") == 5)
        #expect(RetentionDisplay.parsedYears(fromFieldText: "\u{FF15}") == 5)

        // Non-decimal numerics stay refused: a vulgar fraction and a Roman numeral.
        #expect(formatter?.isPartialStringValid("\u{00BD}", newEditingString: nil, errorDescription: nil) == false)
        #expect(formatter?.isPartialStringValid("\u{2163}", newEditingString: nil, errorDescription: nil) == false)
    }

    // MARK: - End-to-end commit: what actually gets persisted

    /// The heart of the user's complaint: entering "99" must both display 99 AND persist 99 to
    /// the injected `UserDefaults` suite — not merely repaint the field optimistically while the
    /// async commit silently fails or never lands. Seeded at 2 so 2 -> 99 is an increase
    /// (`.applyImmediately`), never the decrease/confirmation path.
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

    /// From the one seed that cannot route through a decrease (retention already at the
    /// minimum, so 0's clamped target equals `currentRetentionYears` and the transition is
    /// `.noChange`), entering "0" must still not leave the field showing "0": it repaints to
    /// the minimum synchronously (`setRetentionDisplay`, which runs before the no-change guard)
    /// even though nothing is persisted here (there is nothing new to persist). The
    /// from-above-minimum case — where 0 actually is a decrease and must survive real
    /// confirmation before persisting — is covered by `enteringZeroWithConfirmationAccepted
    /// PersistsMinimum` (and its "00"/empty-string siblings) below, using the injected
    /// confirmation seam.
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

    /// Driving the stepper above the maximum (as a user holding the increment arrow would)
    /// persists and displays exactly `maxRetentionYears`, never an out-of-range value. Seeded
    /// below the max so this is an increase, never the decrease/confirmation path.
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

    /// From a seed above the minimum, entering "0" clamps to `minRetentionYears`, which IS a
    /// decrease and must route through `confirmRetentionDecrease`. This is the case
    /// `enteringZeroAtMinimumStaysAtMinimumNotZero` above could not reach. No archives are
    /// seeded, so `deletingCount` is 0 and `RetentionChangeDecision.evaluate` takes
    /// `.applyImmediately` even though it's a decrease (nothing would be deleted) — this test
    /// therefore exercises the "decrease, but nothing to confirm" sub-case; the "decrease that
    /// truly needs confirmation" sub-case is covered separately below by the wiring tests, which
    /// seed real archives and consult the recorder.
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

    /// Entering "0" (and separately "00") from a seed above the minimum, with a real archive old
    /// enough that the confirmation seam answers "no", must leave the persisted AND displayed
    /// value at the ORIGINAL seed — not at the minimum, and not blank. Reads `revertRetentionFields`
    /// first: it repaints via `setRetentionDisplay(currentRetentionYears)`, so "restored" means
    /// the field shows the value that was persisted before the attempted decrease, exactly what
    /// this asserts.
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

    /// The heart of the user's zero-must-become-one requirement, from a seed well above the
    /// minimum: entering "0" is a genuine decrease (with an old-enough archive present, so it
    /// truly needs confirmation), and once the confirmation seam answers "yes" it must both
    /// display AND persist `minRetentionYears` — never `0`.
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

    /// Same as above for "00" — the two-digit form the partial-input formatter also accepts —
    /// which must clamp and persist identically to "0", not merely display-clamp while leaving
    /// something else persisted.
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

    /// Same as above for the empty string, from a seed above the minimum.
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

    /// Writes an empty archive file at `directory/<start>_<end>.dat`. `collectArchiveFiles`
    /// (`UsageHistory+Archive.swift`) parses only the filename's end-date component to decide
    /// what counts toward retention — it never decodes the file's contents for counting — so an
    /// empty file is sufficient and matches the pattern already used by
    /// `UsageHistoryRetentionTests`.
    private static func writeArchiveFile(in directory: URL, end: Date) throws {
        let formatter = archiveDateFormatterForTests()
        let start = end.addingTimeInterval(-18000)
        let url = directory.appendingPathComponent(
            "\(formatter.string(from: start))_\(formatter.string(from: end)).\(Constants.History.windowInstanceFileExtension)")
        try Data().write(to: url)
    }

    /// User's own example: 99 -> 90 with only a few months of history on disk must apply
    /// silently, with no confirmation dialog at all — a decrease alone must never be sufficient
    /// to trigger it.
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

        // Sanity check the fixture's own premise before relying on it in the wiring assertion
        // below, so a typo in the archive filename surfaces as an explicit failure here rather
        // than a silent zero later.
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

    /// User's own example: 2 -> 1 with more than a year of history on disk must show the
    /// dialog, and the count it's told must be exactly the number of archives genuinely older
    /// than the new (1-year) cutoff — not merely "greater than zero". A recent survivor archive
    /// (younger than the cutoff) proves the count isn't simply "every archive that exists".
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

        let doomed1 = cutoffOneYear.addingTimeInterval(-3600 * 24 * 400)   // ~13 months old: older than the 1-year cutoff
        let doomed2 = cutoffOneYear.addingTimeInterval(-3600 * 24 * 800)   // ~26 months old: older than the 1-year cutoff
        let survivor = calendar.date(byAdding: .month, value: -3, to: now)! // 3 months old: newer than the 1-year cutoff
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

    /// Catches the specific wiring mistake of computing the archived-window count against
    /// `currentRetentionYears` instead of the proposed new value: seeds two archives dated
    /// between the new (2-year) cutoff and the current (5-year) cutoff — i.e. older than the
    /// new cutoff but NOT older than the current one. Correct wiring
    /// (`archivedWindowCount(retentionYears: newValue, ...)`) counts both and requests
    /// confirmation with `deletingCount == 2`. A bug that passed `currentValue` instead would
    /// compute 0 archives old enough (none exceed a 5-year-old cutoff) and silently skip
    /// confirmation entirely via `.applyImmediately` — which the `wasConsulted` assertion below
    /// would catch as a failure.
    @Test func confirmationCountIsComputedForNewValueNotCurrentValue() async throws {
        let fixture = UsageHistoryTestFixture()
        let testOrgId = UUID().uuidString
        fixture.history.switchOrganization(testOrgId)
        let identityDir = archiveTestDirectory(baseDirectory: fixture.baseDirectory, orgId: testOrgId)
        try FileManager.default.createDirectory(at: identityDir, withIntermediateDirectories: true)
        let now = Date()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let newCutoff = calendar.date(byAdding: .year, value: -2, to: now)!   // proposed new value: 2 years
        let currentCutoff = calendar.date(byAdding: .year, value: -5, to: now)! // current value: 5 years

        // Both archives are older than newCutoff (2 years) but younger than currentCutoff
        // (5 years) — roughly 3 years old.
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

    /// An increase must never consult the confirmation seam, even with plenty of old,
    /// deletable-looking archives on disk — increases can never delete anything, so
    /// `RetentionChangeDecision.requiresArchivedWindowCount` must never even compute a count for
    /// this direction, let alone confirm.
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
            usageHistory: history,
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

    /// A fresh, uniquely-named `UserDefaults` suite per call — never `UserDefaults.standard`,
    /// which is process-global state also read by the real running app. The suite name is
    /// returned alongside the instance (rather than derived back out of it — `UserDefaults`
    /// exposes no API to recover its own suite name) so the caller can tear the domain down
    /// unconditionally in a `defer`. Unique per call, not just per test, so tests can never
    /// collide even if Swift Testing parallelizes or repeats them.
    private static func makeIsolatedDefaults() -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = TestPreferencesRoot.makeSuiteName("PreferencesWindowControllerTests")
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }
}
