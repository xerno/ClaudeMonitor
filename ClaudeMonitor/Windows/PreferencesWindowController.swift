import AppKit
import ServiceManagement

enum RetentionDisplay {
    static func clampedYears(_ rawValue: Int) -> Int {
        Constants.History.clampRetentionYears(rawValue)
    }

    /// `decimalNumber` category, not `isNumber`: Roman numerals (`Ⅳ`) and vulgar fractions (`½`) pass
    /// `isNumber` but `parsedYears` cannot read them.
    static func isDecimalDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first
        else { return false }
        return scalar.properties.generalCategory == .decimalNumber
    }

    /// Any decimal numbering system: `NSTextField.integerValue` parses ASCII digits only, so `٩٩`
    /// would read as 0 and clamp to a value the user never typed.
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

/// Deliberately no min/max: AppKit's commit-time check would reject `""` and `"0"` (reachable
/// while typing) and revert the field before `RetentionDisplay.clampedYears` can run.
/// `@unchecked Sendable` must be restated on the subclass; sound because it adds no stored state.
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
    private let blockedCountdownCheckbox = NSButton(checkboxWithTitle: String(localized: "prefs.show_blocked_countdown", bundle: .module), target: nil, action: nil)
    private let retentionLabel = NSTextField(labelWithString: String(localized: "prefs.retention.label", bundle: .module))
    private let retentionField = NSTextField()
    private let retentionStepper = NSStepper()
    private let usageHistories: @MainActor () -> [UsageHistory]
    private let onSave: () -> Void
    private let onDisplaySettingsChanged: () -> Void
    private let defaults: UserDefaults
    // Persisted value; not mutated while a confirmation is pending, so cancel can repaint from it.
    private var currentRetentionYears: Int
    private var pendingRetentionTask: Task<Void, Never>?
    // True while a decrease confirmation is pending; further input is ignored so a second sheet
    // can't stack against a stale `currentRetentionYears`.
    var isRetentionAlertPresented = false
    private var activeRetentionAlert: NSAlert?

    // Test seam: answers the decrease confirmation in place of a real `NSAlert`; nil in production.
    var retentionDecreaseConfirmationOverride: ((_ newValue: Int, _ deletingCount: Int) async -> Bool)?

    var displayedRetentionYears: Int { RetentionDisplay.parsedYears(fromFieldText: retentionField.stringValue) ?? 0 }

    var installedRetentionFormatter: Formatter? { retentionField.formatter }

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

    /// `defaults` is injectable so tests never touch `UserDefaults.standard`.
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
        blockedCountdownCheckbox.target = self
        blockedCountdownCheckbox.action = #selector(blockedCountdownToggled)

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
        for control in [launchAtLoginCheckbox, resetSoundCheckbox, showGraphCheckbox, compactServicesCheckbox, blockedCountdownCheckbox, retentionLabel, retentionField, retentionStepper] {
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

            blockedCountdownCheckbox.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.generalHorizontalInset),
            blockedCountdownCheckbox.topAnchor.constraint(equalTo: compactServicesCheckbox.bottomAnchor, constant: Self.checkboxSpacing),

            retentionLabel.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Self.generalHorizontalInset),
            retentionLabel.centerYAnchor.constraint(equalTo: retentionField.centerYAnchor),

            retentionField.leadingAnchor.constraint(equalTo: retentionLabel.trailingAnchor, constant: 8),
            retentionField.topAnchor.constraint(equalTo: blockedCountdownCheckbox.bottomAnchor, constant: Self.retentionTopSpacing),
            retentionField.widthAnchor.constraint(equalToConstant: 46),

            retentionStepper.leadingAnchor.constraint(equalTo: retentionField.trailingAnchor, constant: 4),
            retentionStepper.centerYAnchor.constraint(equalTo: retentionField.centerYAnchor),
        ])
        return container
    }

    func loadSavedValues() {
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        resetSoundCheckbox.state = defaults.bool(forKey: Constants.Preferences.resetSoundEnabled) ? .on : .off
        showGraphCheckbox.state = Constants.Preferences.isUsageGraphEnabled(in: defaults) ? .on : .off
        compactServicesCheckbox.state = Constants.Preferences.isServicesCompact(in: defaults) ? .on : .off
        blockedCountdownCheckbox.state = Constants.Preferences.isBlockedCountdownShown(in: defaults) ? .on : .off

        // Skip while a confirmation sheet is live: `showWindow` can re-enter here with the sheet
        // still attached, and only the sheet's handler may resolve `currentRetentionYears`.
        guard !isRetentionAlertPresented else { return }
        currentRetentionYears = Constants.History.retentionYears(defaults: defaults)
        setRetentionDisplay(currentRetentionYears)
    }

    private func setRetentionDisplay(_ years: Int) {
        retentionField.integerValue = years
        retentionStepper.integerValue = years
    }

    // MARK: - Retention

    @objc private func retentionStepperChanged() {
        applyRetentionChange(to: RetentionDisplay.clampedYears(retentionStepper.integerValue))
    }

    @objc private func retentionFieldChanged() {
        // Text, not `integerValue` (ASCII digits only). Empty or non-digit text becomes 0 so it
        // clamps to the minimum.
        let typed = RetentionDisplay.parsedYears(fromFieldText: retentionField.stringValue) ?? 0
        applyRetentionChange(to: RetentionDisplay.clampedYears(typed))
    }

    /// The field's action fires only on Return; commit on focus loss too.
    func controlTextDidEndEditing(_ notification: Notification) {
        retentionFieldChanged()
    }

    func simulateRetentionFieldEntry(_ text: String) {
        retentionField.stringValue = text
        controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: retentionField))
    }

    func simulateRetentionStepperEntry(_ value: Int) {
        retentionStepper.integerValue = value
        retentionStepperChanged()
    }

    func awaitPendingRetentionChange() async {
        await pendingRetentionTask?.value
    }

    func control(_ control: NSControl, didFailToFormatString string: String, errorDescription error: String?) -> Bool {
        revertRetentionFields()
        return false
    }

    private func applyRetentionChange(to newValue: Int) {
        guard !isRetentionAlertPresented else {
            revertRetentionFields()
            return
        }

        setRetentionDisplay(newValue)
        guard newValue != currentRetentionYears else { return }

        pendingRetentionTask?.cancel()

        // One `now` for both the count and the prune, so the confirmed number is what gets deleted.
        let now = Date()
        let currentValue = currentRetentionYears
        let histories = usageHistories()
        pendingRetentionTask = Task { [weak self] in
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

    /// `async` only for the test-seam branch: awaited inline it stays on `pendingRetentionTask`,
    /// which `windowWillClose` cancels. The `NSAlert` branch returns once the sheet is presented.
    private func confirmRetentionDecrease(to newValue: Int, deletingCount count: Int, now: Date) async {
        isRetentionAlertPresented = true

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

        // Each count is pluralized on its own (Slavic grammar differs between "2 years" and
        // "5 windows"), then both phrases are substituted into the sentence template.
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
            // Best effort: failure is not critical
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

    @objc private func blockedCountdownToggled() {
        defaults.set(blockedCountdownCheckbox.state == .on, forKey: Constants.Preferences.showBlockedCountdown)
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
        // The controller outlives close (`isReleasedWhenClosed = false`), so re-sync from persisted
        // state on every show to drop stale optimistic repaints.
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
        // The window outlives close: stop a pending count or alert from acting on it later.
        pendingRetentionTask?.cancel()
        pendingRetentionTask = nil
        // End a live sheet now, or its handler could fire after a reopen and commit or prune against
        // resynced state. `endSheet` runs the handler synchronously with a non-first-button response,
        // i.e. the Cancel path.
        if let alert = activeRetentionAlert, let window {
            window.endSheet(alert.window)
        }
        // Reset even when no handler ran, or a stuck flag blocks retention changes for the session.
        isRetentionAlertPresented = false
        activeRetentionAlert = nil
        for form in accountForms.values {
            form.clearCookie()
        }
        addForm.clearCookie()
        WindowManager.revertActivationPolicyIfNeeded(excluding: window)
    }
}
