import AppKit
import ServiceManagement

@MainActor
final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let credentialForm = CredentialFormView()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: String(localized: "prefs.launch_at_login", bundle: .module), target: nil, action: nil)
    private let resetSoundCheckbox = NSButton(checkboxWithTitle: String(localized: "prefs.reset_sound", bundle: .module), target: nil, action: nil)
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
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

        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false
        resetSoundCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: String(localized: "prefs.button.save", bundle: .module), target: self, action: #selector(didTapSave))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(credentialForm)
        contentView.addSubview(launchAtLoginCheckbox)
        contentView.addSubview(resetSoundCheckbox)
        contentView.addSubview(saveButton)

        NSLayoutConstraint.activate([
            credentialForm.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            credentialForm.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            credentialForm.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),

            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: credentialForm.bottomAnchor, constant: 14),

            resetSoundCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            resetSoundCheckbox.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 10),

            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            saveButton.topAnchor.constraint(equalTo: resetSoundCheckbox.bottomAnchor, constant: 14),
            saveButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
        ])

        loadSavedValues()
    }

    private func loadSavedValues() {
        credentialForm.loadSavedValues()
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
        resetSoundCheckbox.state = UserDefaults.standard.bool(forKey: Constants.Preferences.resetSoundEnabled) ? .on : .off
    }

    @objc private func didTapSave() {
        guard let window else { return }
        guard credentialForm.validateAndSave(in: window) else { return }

        do {
            if launchAtLoginCheckbox.state == .on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Login item registration can fail silently — not critical
        }

        UserDefaults.standard.set(resetSoundCheckbox.state == .on, forKey: Constants.Preferences.resetSoundEnabled)

        close()
        onSave()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        WindowManager.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.revertActivationPolicyIfNeeded(excluding: window)
    }
}
