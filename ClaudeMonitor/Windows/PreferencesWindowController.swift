import AppKit
import ServiceManagement

/// Pure (non-AppKit) logic behind the retention stepper/field, extracted from
/// `PreferencesWindowController` specifically so it's directly testable without constructing any
/// `NSStepper`/`NSTextField`/window. `clampedYears` is what both `retentionStepperChanged` and
/// `retentionFieldChanged` funnel their raw control value through.
enum RetentionDisplay {
    static func clampedYears(_ rawValue: Int) -> Int {
        Constants.History.clampRetentionYears(rawValue)
    }

    /// True only for a single-scalar Unicode DECIMAL digit — ASCII `0-9`, Arabic-Indic `٠-٩`,
    /// Devanagari `०-९`, and every other decimal numbering system.
    ///
    /// Deliberately keyed on the `decimalNumber` general category rather than `isNumber`, which
    /// is also true of Roman numerals (`Ⅳ`) and vulgar fractions (`½`) — neither is a digit a
    /// positional parser can read, and accepting them would let the field display something
    /// `parsedYears` could not interpret.
    static func isDecimalDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first
        else { return false }
        return scalar.properties.generalCategory == .decimalNumber
    }

    /// Parses the retention field's text, accepting ANY decimal numbering system.
    ///
    /// `NSTextField.integerValue` parses ASCII digits only. Reading the field through it meant a
    /// user on an Arabic-Indic or Devanagari numeric keyboard who typed `٩٩` produced 0, which
    /// `clampedYears` then turned into 1 — silently storing a value they never typed. Returns
    /// `nil` for empty or non-digit text so the caller decides the fallback rather than having a
    /// 0 invented for it.
    static func parsedYears(fromFieldText text: String) -> Int? {
        guard !text.isEmpty else { return nil }
        var value = 0
        for character in text {
            guard isDecimalDigit(character), let digit = character.wholeNumberValue else { return nil }
            value = value * 10 + digit
        }
        return value
    }
}

/// Keystroke-level guard for the retention field: rejects any keystroke that would leave the
/// field showing something other than the empty string or 1-2 decimal digits in any numbering
/// system (see `RetentionDisplay.isDecimalDigit`). This is
/// deliberately separate from range validation — `minimum`/`maximum` bounds live nowhere on this
/// formatter (removed from it on purpose) and are instead enforced only at commit time, by
/// `RetentionDisplay.clampedYears`, via `retentionFieldChanged`/`retentionStepperChanged`. Keeping
/// bounds here too would make `""` and `"0"` (both required as reachable partial states while
/// typing) get rejected by AppKit's own commit-time formatter check, reverting the field instead
/// of letting the clamp funnel run.
/// `@unchecked Sendable` is restated because `NumberFormatter` declares it and Swift 6 requires a
/// subclass to say so explicitly. Sound here: this subclass adds no stored state at all — only an
/// override that reads its argument — so it inherits exactly the base class's thread-safety, and
/// AppKit only ever touches the installed formatter from the main actor.
final class RetentionPartialInputFormatter: NumberFormatter, @unchecked Sendable {
    override func isPartialStringValid(
        _ partialString: String,
        newEditingString newString: AutoreleasingUnsafeMutablePointer<NSString?>?,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        if partialString.isEmpty { return true }
        guard partialString.count <= 2 else { return false }
        return partialString.allSatisfy(RetentionDisplay.isDecimalDigit)
    }
}

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate, NSTextFieldDelegate {
    private static let generalTabIdentifier = "general"
    private static let addTabIdentifier = "add"
    private static let persistentTabIdentifiers: Set<String> = [generalTabIdentifier, addTabIdentifier]
    private static let contentInset: CGFloat = 12
    private static let generalHorizontalInset: CGFloat = 16
    private static let generalTopInset: CGFloat = 20
    private static let checkboxSpacing: CGFloat = 10
    private static let retentionTopSpacing: CGFloat = 16

    private let profileStore: ProfileStore
    private let tabView = NSTabView()
    private var accountForms: [String: CredentialFormView] = [:]
    private let addForm: CredentialFormView
    private let addTabItem = NSTabViewItem(identifier: PreferencesWindowController.addTabIdentifier)
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: String(localized: "prefs.launch_at_login", bundle: .module), target: nil, action: nil)
    private let resetSoundCheckbox = NSButton(checkboxWithTitle: String(localized: "prefs.reset_sound", bundle: .module), target: nil, action: nil)
    private let showGraphCheckbox = NSButton(checkboxWithTitle: String(localized: "prefs.show_graph", bundle: .module), target: nil, action: nil)
    private let compactServicesCheckbox = NSButton(checkboxWithTitle: String(localized: "prefs.compact_services", bundle: .module), target: nil, action: nil)
    private let retentionLabel = NSTextField(labelWithString: String(localized: "prefs.retention.label", bundle: .module))
    private let retentionField = NSTextField()
    private let retentionStepper = NSStepper()
    private let usageHistories: @MainActor () -> [UsageHistory]
    private let onSave: () -> Void
    private let onDisplaySettingsChanged: () -> Void
    // Injected rather than reaching for `.standard` internally — see `init`'s doc comment.
    private let defaults: UserDefaults
    // Mirrors what's currently persisted/applied. Never mutated while a decrease
    // confirmation is pending — that's what lets a cancel simply repaint the fields from it.
    private var currentRetentionYears: Int
    // The in-flight count-then-maybe-confirm flow for the latest retention change request, if
    // any. Cancelled and replaced whenever a new request arrives before it settles, so only the
    // most recent input ever reaches an alert.
    private var pendingRetentionTask: Task<Void, Never>?
    // True from the moment a decrease confirmation sheet is shown until it resolves. While true,
    // further stepper/field input is ignored (fields reverted) rather than stacking a second
    // sheet against a `currentRetentionYears` that hasn't been updated yet — see
    // `applyRetentionChange`. Internal rather than private solely so
    // `PreferencesWindowControllerTests` can drive the "does `loadSavedValues` leave a
    // presented alert's state alone" regression directly, without driving an actual `NSAlert`.
    var isRetentionAlertPresented = false
    // The confirmation sheet currently attached to `window`, if any — held so `windowWillClose`
    // can force it to end (Defect 3) rather than merely clearing `isRetentionAlertPresented`,
    // which a live sheet's own completion handler never observes. Ending the sheet here runs its
    // completion handler synchronously, on the main actor, before teardown proceeds any further —
    // by the time a closed window could ever be reopened (a later run-loop turn), the sheet is
    // already gone and its handler has already run exactly once. This makes "a sheet's completion
    // handler firing against a torn-down controller" impossible by construction rather than
    // requiring the handler to check a second "am I stale" flag.
    private var activeRetentionAlert: NSAlert?

    // Test seam: when set, `confirmRetentionDecrease` consults this closure instead of building
    // and presenting a real `NSAlert`, so a test can answer a decrease confirmation
    // deterministically without driving a Cocoa modal sheet. Takes `(newValue, deletingCount)`
    // and returns whether to proceed with the decrease (true) or cancel it (false), exactly
    // mirroring the alert's two buttons. `nil` (the default, and the only value any production
    // caller ever sets) leaves `confirmRetentionDecrease`'s real-`NSAlert` path completely
    // unchanged — the override is consulted first and, when absent, falls straight through.
    var retentionDecreaseConfirmationOverride: ((_ newValue: Int, _ deletingCount: Int) async -> Bool)?

    // Internal rather than private solely so `PreferencesWindowControllerTests` can observe
    // what `loadSavedValues` actually resyncs the displayed field to, without driving Cocoa
    // beyond the already-constructed `NSTextField`.
    var displayedRetentionYears: Int { RetentionDisplay.parsedYears(fromFieldText: retentionField.stringValue) ?? 0 }

    // Test seam: exposes the formatter actually installed on the private `retentionField`, so
    // tests can assert real AppKit wiring (that it's a `RetentionPartialInputFormatter`, and
    // drive its `isPartialStringValid` exactly as the field would) instead of assuming the
    // formatter built in `buildUI` ever reaches the control.
    var installedRetentionFormatter: Formatter? { retentionField.formatter }

    // Test seam: exposes the stepper's real configuration (`minValue`/`maxValue`/`valueWraps`)
    // so wiring can be asserted directly rather than assumed from `buildUI`'s source.
    var retentionStepperConfiguration: (minValue: Double, maxValue: Double, valueWraps: Bool) {
        (retentionStepper.minValue, retentionStepper.maxValue, retentionStepper.valueWraps)
    }

    var displayedShowGraph: Bool { showGraphCheckbox.state == .on }

    var displayedCompactServices: Bool { compactServicesCheckbox.state == .on }

    var isAddAccountTabShown: Bool { tabView.indexOfTabViewItem(addTabItem) != NSNotFound }

    var accountTabIdentifiers: [String] {
        tabView.tabViewItems.compactMap { $0.identifier as? String }.filter { !Self.persistentTabIdentifiers.contains($0) }
    }

    func accountForm(forProfileId profileId: String) -> CredentialFormView? {
        accountForms[profileId]
    }

    private static let retentionFormatter: NumberFormatter = {
        let formatter = RetentionPartialInputFormatter()
        formatter.allowsFloats = false
        formatter.maximumFractionDigits = 0
        return formatter
    }()

    /// `defaults` defaults to `.standard` for production callers (`MenuBarController`), but is
    /// an injectable parameter — never hardcoded internally — so tests can supply an isolated
    /// `UserDefaults(suiteName:)` instance instead of mutating the process-global
    /// `UserDefaults.standard`, which the real running app also reads. Same seam
    /// `Constants.History.retentionYears(defaults:)` already exposes; this just threads it
    /// through the one call site here that previously bypassed it via the defaulted overload.
    init(
        usageHistories: @escaping @MainActor () -> [UsageHistory],
        profileStore: ProfileStore,
        defaults: UserDefaults = .standard,
        onDisplaySettingsChanged: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        self.usageHistories = usageHistories
        self.profileStore = profileStore
        self.defaults = defaults
        self.onDisplaySettingsChanged = onDisplaySettingsChanged
        self.onSave = onSave
        self.addForm = CredentialFormView(profileStore: profileStore, mode: .add)
        self.currentRetentionYears = Constants.History.retentionYears(defaults: defaults)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 450),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "prefs.window.title", bundle: .module)
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        retentionField.formatter = Self.retentionFormatter
        retentionField.alignment = .right
        retentionField.delegate = self

        retentionStepper.minValue = Double(Constants.History.minRetentionYears)
        retentionStepper.maxValue = Double(Constants.History.maxRetentionYears)
        retentionStepper.increment = 1
        retentionStepper.valueWraps = false
        retentionStepper.target = self
        retentionStepper.action = #selector(retentionStepperChanged)

        launchAtLoginCheckbox.target = self
        launchAtLoginCheckbox.action = #selector(launchAtLoginToggled)
        resetSoundCheckbox.target = self
        resetSoundCheckbox.action = #selector(resetSoundToggled)
        showGraphCheckbox.target = self
        showGraphCheckbox.action = #selector(showGraphToggled)
        compactServicesCheckbox.target = self
        compactServicesCheckbox.action = #selector(compactServicesToggled)

        tabView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(tabView)
        NSLayoutConstraint.activate([
            tabView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Self.contentInset),
            tabView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Self.contentInset),
            tabView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Self.contentInset),
            tabView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Self.contentInset),
        ])

        let general = NSTabViewItem(identifier: Self.generalTabIdentifier)
        general.label = String(localized: "prefs.tab.general", bundle: .module)
        general.view = makeGeneralView()
        tabView.addTabViewItem(general)

        addTabItem.label = String(localized: "prefs.tab.add", bundle: .module)
        addTabItem.view = makeEditorView(
            form: addForm,
            primaryTitle: String(localized: "prefs.button.add_account", bundle: .module),
            secondary: nil
        )
        addForm.loadSavedValues()

        rebuildAccountTabs()
        loadSavedValues()
    }

    private func rebuildAccountTabs() {
        let selectedIdentifier = tabView.selectedTabViewItem?.identifier as? String
        for item in tabView.tabViewItems {
            guard let identifier = item.identifier as? String,
                  !Self.persistentTabIdentifiers.contains(identifier) else { continue }
            tabView.removeTabViewItem(item)
        }
        accountForms.removeAll()
        for profile in profileStore.profiles {
            insertAccountTab(for: profile)
        }
        syncAddTabVisibility()
        if let selectedIdentifier, tabView.indexOfTabViewItem(withIdentifier: selectedIdentifier) != NSNotFound {
            tabView.selectTabViewItem(withIdentifier: selectedIdentifier)
        }
    }

    private func insertAccountTab(for profile: Profile) {
        guard let index = profileStore.profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        let item = NSTabViewItem(identifier: profile.id)
        item.label = profile.name
        item.view = makeAccountView(profileId: profile.id)
        tabView.insertTabViewItem(item, at: index)
    }

    private func syncAddTabVisibility() {
        switch (profileStore.canAddProfile, isAddAccountTabShown) {
        case (true, false):
            tabView.addTabViewItem(addTabItem)
        case (false, true):
            tabView.removeTabViewItem(addTabItem)
        default:
            break
        }
    }

    private func makeAccountView(profileId: String) -> NSView {
        let form = CredentialFormView(profileStore: profileStore, mode: .edit(profileId: profileId))
        form.loadSavedValues()
        accountForms[profileId] = form
        let removeButton = NSButton(title: String(localized: "prefs.button.remove_account", bundle: .module), target: self, action: #selector(didTapRemove))
        removeButton.bezelStyle = .rounded
        return makeEditorView(form: form, primaryTitle: String(localized: "prefs.button.save", bundle: .module), secondary: removeButton)
    }

    private func makeEditorView(form: CredentialFormView, primaryTitle: String, secondary: NSButton?) -> NSView {
        let container = NSView()
        let primary = NSButton(title: primaryTitle, target: self, action: #selector(didTapSave))
        primary.bezelStyle = .rounded
        primary.keyEquivalent = "\r"
        primary.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(form)
        container.addSubview(primary)
        NSLayoutConstraint.activate([
            form.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.contentInset),
            form.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.contentInset),
            form.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.contentInset),

            primary.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -Self.contentInset),
            primary.topAnchor.constraint(equalTo: form.bottomAnchor, constant: Self.contentInset),
            primary.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor, constant: -Self.contentInset),
        ])
        if let secondary {
            secondary.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(secondary)
            NSLayoutConstraint.activate([
                secondary.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.contentInset),
                secondary.centerYAnchor.constraint(equalTo: primary.centerYAnchor),
            ])
        }
        return container
    }

    private func makeGeneralView() -> NSView {
        let container = NSView()
        for control in [launchAtLoginCheckbox, resetSoundCheckbox, showGraphCheckbox, compactServicesCheckbox, retentionLabel, retentionField, retentionStepper] {
            control.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(control)
        }

        NSLayoutConstraint.activate([
            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.generalHorizontalInset),
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: container.topAnchor, constant: Self.generalTopInset),

            resetSoundCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.generalHorizontalInset),
            resetSoundCheckbox.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: Self.checkboxSpacing),

            showGraphCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.generalHorizontalInset),
            showGraphCheckbox.topAnchor.constraint(equalTo: resetSoundCheckbox.bottomAnchor, constant: Self.checkboxSpacing),

            compactServicesCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.generalHorizontalInset),
            compactServicesCheckbox.topAnchor.constraint(equalTo: showGraphCheckbox.bottomAnchor, constant: Self.checkboxSpacing),

            retentionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.generalHorizontalInset),
            retentionLabel.centerYAnchor.constraint(equalTo: retentionField.centerYAnchor),

            retentionField.leadingAnchor.constraint(equalTo: retentionLabel.trailingAnchor, constant: 8),
            retentionField.topAnchor.constraint(equalTo: compactServicesCheckbox.bottomAnchor, constant: Self.retentionTopSpacing),
            retentionField.widthAnchor.constraint(equalToConstant: 46),

            retentionStepper.leadingAnchor.constraint(equalTo: retentionField.trailingAnchor, constant: 4),
            retentionStepper.centerYAnchor.constraint(equalTo: retentionField.centerYAnchor),
        ])
        return container
    }

    // Internal rather than private so `PreferencesWindowControllerTests` can call it directly —
    // see the doc comment on `isRetentionAlertPresented`.
    func loadSavedValues() {
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        resetSoundCheckbox.state = defaults.bool(forKey: Constants.Preferences.resetSoundEnabled) ? .on : .off
        showGraphCheckbox.state = Constants.Preferences.isUsageGraphEnabled(in: defaults) ? .on : .off
        compactServicesCheckbox.state = Constants.Preferences.isServicesCompact(in: defaults) ? .on : .off

        // While a decrease-confirmation sheet is on screen, its own completion handler is the
        // only thing allowed to resolve `currentRetentionYears`/the displayed fields — see
        // `confirmRetentionDecrease`. `loadSavedValues` runs on every `showWindow`, including a
        // second "Preferences…" invocation that finds the window already open with that sheet
        // still attached to it, so re-syncing here would repaint over an in-flight flow (and,
        // if it also cleared `isRetentionAlertPresented`, would let a second sheet stack on top
        // of the first — that was the actual bug). Skipping the resync entirely, rather than
        // just skipping the flag reset, keeps this path a true no-op while the sheet is live:
        // there is nothing here for it to race against.
        guard !isRetentionAlertPresented else { return }
        currentRetentionYears = Constants.History.retentionYears(defaults: defaults)
        setRetentionDisplay(currentRetentionYears)
    }

    /// Repaints the number field and stepper together. Every call site that shows a retention
    /// value must go through this rather than setting the field and stepper directly.
    private func setRetentionDisplay(_ years: Int) {
        retentionField.integerValue = years
        retentionStepper.integerValue = years
    }

    // MARK: - Retention

    @objc private func retentionStepperChanged() {
        applyRetentionChange(to: RetentionDisplay.clampedYears(retentionStepper.integerValue))
    }

    @objc private func retentionFieldChanged() {
        // Reads the field's TEXT rather than `integerValue`: the latter parses ASCII digits only,
        // so digits from any other decimal numbering system would commit as 0 and then clamp to
        // the minimum. `nil` (empty or non-digit text) deliberately becomes 0 so `clampedYears`
        // raises it to the minimum, which is the required behaviour for an emptied field.
        let typed = RetentionDisplay.parsedYears(fromFieldText: retentionField.stringValue) ?? 0
        applyRetentionChange(to: RetentionDisplay.clampedYears(typed))
    }

    /// Commits the field's value when it loses focus (the field's `.action` alone only fires
    /// on Return), so typing a value and clicking away behaves like the stepper.
    func controlTextDidEndEditing(_ notification: Notification) {
        retentionFieldChanged()
    }

    // Test seam: drives the retention field exactly as a user committing a typed value would —
    // sets the field's `stringValue` then runs the same `controlTextDidEndEditing` path AppKit
    // invokes on focus loss — rather than re-implementing the commit logic in the test or
    // reaching into the private `NSTextField` (which tests cannot do; the field is private).
    func simulateRetentionFieldEntry(_ text: String) {
        retentionField.stringValue = text
        controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: retentionField))
    }

    // Test seam: drives the stepper exactly as a user clicking it would — sets its
    // `integerValue` then invokes the real `retentionStepperChanged()` action, rather than
    // reaching into the private `NSStepper` (which tests cannot do) or duplicating the action's
    // logic.
    func simulateRetentionStepperEntry(_ value: Int) {
        retentionStepper.integerValue = value
        retentionStepperChanged()
    }

    // Test seam: awaits the in-flight `pendingRetentionTask` spawned by `applyRetentionChange`
    // so a test can observe the eventually-committed retention value deterministically, without
    // polling or sleeping for a fixed duration (the commit happens asynchronously, after an
    // await on `usageHistory.archivedWindowCount`).
    func awaitPendingRetentionChange() async {
        await pendingRetentionTask?.value
    }

    /// `NumberFormatter.getObjectValue` rejects non-numeric or out-of-range text on commit;
    /// this is AppKit's hook for that rejection. Reverting here (rather than leaving the
    /// unparseable text in place) keeps the field always showing the last valid value.
    func control(_ control: NSControl, didFailToFormatString string: String, errorDescription error: String?) -> Bool {
        revertRetentionFields()
        return false
    }

    private func applyRetentionChange(to newValue: Int) {
        guard !isRetentionAlertPresented else {
            // A confirmation sheet from an earlier request is still on screen; ignore further
            // input (reverting the optimistic repaint) rather than starting a second concurrent
            // flow against a `currentRetentionYears` the pending one hasn't resolved yet.
            revertRetentionFields()
            return
        }

        setRetentionDisplay(newValue)
        guard newValue != currentRetentionYears else { return }

        // A newer request always supersedes an older one that hasn't reached its alert yet.
        pendingRetentionTask?.cancel()

        // Captured once and threaded through both the count below and the eventual prune, so
        // the number promised in the confirmation alert is exactly what gets deleted — no
        // separate `now` for each call that could drift while the sheet is open.
        let now = Date()
        let currentValue = currentRetentionYears
        let histories = usageHistories()
        pendingRetentionTask = Task { [weak self] in
            // Only a decrease can delete anything, so the (async, disk-touching) count is only
            // ever fetched on that path — awaited directly here rather than handed across as a
            // closure, which keeps `RetentionChangeDecision.evaluate` a plain synchronous
            // function with nothing to send across an isolation boundary.
            let count: Int
            if RetentionChangeDecision.requiresArchivedWindowCount(currentValue: currentValue, newValue: newValue) {
                var total = 0
                for history in histories {
                    total += await history.archivedWindowCount(retentionYears: newValue, now: now)
                }
                count = total
            } else {
                count = 0
            }
            guard let self, !Task.isCancelled else { return }
            self.pendingRetentionTask = nil
            let outcome = RetentionChangeDecision.evaluate(
                currentValue: currentValue,
                newValue: newValue,
                archivedWindowCount: count
            )
            switch outcome {
            case .noChange:
                break
            case .applyImmediately(let value):
                self.commitRetention(value, now: now)
            case .needsConfirmation(let value, let count):
                await self.confirmRetentionDecrease(to: value, deletingCount: count, now: now)
            }
        }
    }

    /// `async` solely so the test-seam branch below can `await` the injected confirmation
    /// answer inline, on the same `pendingRetentionTask` the caller already awaits — rather than
    /// spawning a second, untracked `Task` that `windowWillClose`'s cancellation wouldn't reach.
    /// The real `NSAlert` branch is unchanged and still returns as soon as the sheet is
    /// presented (it doesn't await anything); only the override branch actually suspends here.
    private func confirmRetentionDecrease(to newValue: Int, deletingCount count: Int, now: Date) async {
        isRetentionAlertPresented = true

        // Test seam: see `retentionDecreaseConfirmationOverride`'s doc comment. When unset, this
        // branch is never taken and everything below is byte-for-byte the production path.
        if let override = retentionDecreaseConfirmationOverride {
            let proceed = await override(newValue, count)
            isRetentionAlertPresented = false
            activeRetentionAlert = nil
            if proceed {
                commitRetention(newValue, now: now)
            } else {
                revertRetentionFields()
            }
            return
        }

        let alert = NSAlert()
        alert.messageText = String(localized: "prefs.retention.confirm.title", bundle: .module)

        // Each count is pluralized independently (a Slavic language needs different grammar for
        // "2 years" than for "5 windows" in the same sentence), then the two already-pluralized
        // phrases are substituted as plain strings into the sentence template — see
        // Translations/_comments.json for the schema.
        let yearsPhraseTemplate = String(localized: "prefs.retention.confirm.years_phrase", bundle: .module)
        let yearsPhrase = String(format: yearsPhraseTemplate, locale: .current, newValue)
        let windowsPhraseTemplate = String(localized: "prefs.retention.confirm.windows_phrase", bundle: .module)
        let windowsPhrase = String(format: windowsPhraseTemplate, locale: .current, count)

        alert.informativeText = String(
            format: String(localized: "prefs.retention.confirm.message", bundle: .module),
            yearsPhrase, windowsPhrase
        )
        alert.addButton(withTitle: String(localized: "prefs.retention.confirm.delete_button", bundle: .module))
        alert.addButton(withTitle: String(localized: "prefs.retention.confirm.cancel_button", bundle: .module))

        let respond: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isRetentionAlertPresented = false
            self.activeRetentionAlert = nil
            if response == .alertFirstButtonReturn {
                self.commitRetention(newValue, now: now)
            } else {
                self.revertRetentionFields()
            }
        }
        activeRetentionAlert = alert
        if let window {
            alert.beginSheetModal(for: window, completionHandler: respond)
        } else {
            respond(alert.runModal())
        }
    }

    private func commitRetention(_ value: Int, now: Date) {
        currentRetentionYears = value
        setRetentionDisplay(value)
        defaults.set(value, forKey: Constants.Preferences.historyRetentionYears)
        let histories = usageHistories()
        Task {
            for history in histories {
                await history.pruneArchives(retentionYears: value, now: now)
            }
        }
    }

    private func revertRetentionFields() {
        setRetentionDisplay(currentRetentionYears)
    }

    @objc private func launchAtLoginToggled() {
        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Login item registration can fail silently — not critical
        }
    }

    @objc private func resetSoundToggled() {
        defaults.set(resetSoundCheckbox.state == .on, forKey: Constants.Preferences.resetSoundEnabled)
    }

    @objc private func showGraphToggled() {
        defaults.set(showGraphCheckbox.state == .on, forKey: Constants.Preferences.showUsageGraph)
        onDisplaySettingsChanged()
    }

    @objc private func compactServicesToggled() {
        defaults.set(compactServicesCheckbox.state == .on, forKey: Constants.Preferences.compactServices)
        onDisplaySettingsChanged()
    }

    func simulateShowGraphToggle(_ isOn: Bool) {
        showGraphCheckbox.state = isOn ? .on : .off
        showGraphToggled()
    }

    func simulateCompactServicesToggle(_ isOn: Bool) {
        compactServicesCheckbox.state = isOn ? .on : .off
        compactServicesToggled()
    }

    @objc private func didTapSave() {
        guard let window, let identifier = tabView.selectedTabViewItem?.identifier as? String else { return }
        if identifier == Self.addTabIdentifier {
            addAccount(in: window)
        } else if let form = accountForms[identifier], form.validateAndSave(in: window) != nil {
            close()
            onSave()
        }
    }

    private func addAccount(in window: NSWindow) {
        guard let newId = addForm.validateAndSave(in: window),
              let profile = profileStore.profiles.first(where: { $0.id == newId }) else { return }
        insertAccountTab(for: profile)
        syncAddTabVisibility()
        tabView.selectTabViewItem(withIdentifier: newId)
        addForm.loadSavedValues()
        onSave()
    }

    @objc private func didTapRemove() {
        guard let window,
              let id = tabView.selectedTabViewItem?.identifier as? String,
              let profile = profileStore.profiles.first(where: { $0.id == id }) else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "account.remove.confirm.title", bundle: .module)
        alert.informativeText = String(
            format: String(localized: "account.remove.confirm.message", bundle: .module), profile.name
        )
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "account.remove.confirm.remove", bundle: .module))
        alert.addButton(withTitle: String(localized: "account.remove.confirm.cancel", bundle: .module))
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.removeAccount(id: id)
        }
    }

    func removeAccount(id: String) {
        profileStore.removeProfile(id: id)
        if let item = tabView.tabViewItems.first(where: { ($0.identifier as? String) == id }) {
            tabView.removeTabViewItem(item)
        }
        accountForms[id] = nil
        syncAddTabVisibility()
        onSave()
    }

    override func showWindow(_ sender: Any?) {
        // This controller instance can be shown, closed (not deallocated — `isReleasedWhenClosed
        // = false`), and shown again; re-sync every control from persisted state each time so a
        // reopened window can never display a stale value left over from a prior optimistic
        // repaint or an in-flight change that never committed.
        prepareForDisplay(isWindowVisible: window?.isVisible ?? false)
        super.showWindow(sender)
        WindowManager.bringToFront(window)
    }

    func prepareForDisplay(isWindowVisible: Bool) {
        if !isWindowVisible {
            rebuildAccountTabs()
            addForm.loadSavedValues()
        }
        loadSavedValues()
    }

    func windowWillClose(_ notification: Notification) {
        // Prevents a confirmation alert (or the count computation preceding it) from firing
        // later against a closed-but-not-deallocated window.
        pendingRetentionTask?.cancel()
        pendingRetentionTask = nil
        // If a decrease-confirmation sheet is currently attached to this window, force it to end
        // NOW rather than leaving it live (Defect 3: `isReleasedWhenClosed = false` keeps this
        // controller and its window alive after close, so a sheet's completion handler could
        // otherwise still fire later — against a window that has since been reopened and
        // re-synced by `loadSavedValues` — and mutate `currentRetentionYears`, UserDefaults, the
        // display fields, and prune archives the user no longer intended). `endSheet` invokes
        // `respond` synchronously, on the main actor, before this method returns, with a response
        // code that is never `.alertFirstButtonReturn` — so it takes the same path as the user
        // clicking Cancel, never `commitRetention`. By the time any later run-loop turn could
        // reopen this window, the sheet is already gone and its handler has already run exactly
        // once — no second flag is needed to guard against a stale fire.
        if let alert = activeRetentionAlert, let window {
            window.endSheet(alert.window)
        }
        // The sheet's own completion handler is the only other place this is cleared, and
        // `loadSavedValues` deliberately never touches it (see there) — so a teardown path that
        // tears the window down without that handler running (e.g. a forced/programmatic close,
        // or an app-termination path) must not leave this `true` forever, or retention becomes
        // permanently unchangeable for the rest of the session. Resetting it here makes a stuck
        // flag impossible by construction: the window is gone, so there is no sheet left to
        // race against, regardless of why this method ran.
        isRetentionAlertPresented = false
        activeRetentionAlert = nil
        for form in accountForms.values {
            form.clearCookie()
        }
        addForm.clearCookie()
        WindowManager.revertActivationPolicyIfNeeded(excluding: window)
    }
}
