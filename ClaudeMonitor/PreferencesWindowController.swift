import AppKit
import ServiceManagement

final class PreferencesWindowController: NSWindowController, NSWindowDelegate {
    private let credentialForm = CredentialFormView()
    private let launchAtLoginCheckbox = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let onSave: () -> Void

    init(onSave: @escaping () -> Void) {
        self.onSave = onSave
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Monitor – Preferences"
        window.center()
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        buildUI()
        loadSavedValues()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    private func buildUI() {
        guard let contentView = window?.contentView else { return }

        launchAtLoginCheckbox.translatesAutoresizingMaskIntoConstraints = false

        let saveButton = NSButton(title: "Save", target: self, action: #selector(didTapSave))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(credentialForm)
        contentView.addSubview(launchAtLoginCheckbox)
        contentView.addSubview(saveButton)

        NSLayoutConstraint.activate([
            credentialForm.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            credentialForm.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            credentialForm.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),

            launchAtLoginCheckbox.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            launchAtLoginCheckbox.topAnchor.constraint(equalTo: credentialForm.bottomAnchor, constant: 14),

            saveButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            saveButton.topAnchor.constraint(equalTo: launchAtLoginCheckbox.bottomAnchor, constant: 14),
            saveButton.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    private func loadSavedValues() {
        credentialForm.loadSavedValues()
        launchAtLoginCheckbox.state = SMAppService.mainApp.status == .enabled ? .on : .off
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

        close()
        onSave()
    }

    override func showWindow(_ sender: Any?) {
        loadSavedValues()
        super.showWindow(sender)
        WindowManager.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.revertActivationPolicyIfNeeded(excluding: window)
    }
}
