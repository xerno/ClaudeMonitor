import AppKit

final class CredentialFormView: NSView {
    let orgIdField = NSTextField()
    let cookieTextView = NSTextView()
    private let cookieScrollView = NSScrollView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func loadSavedValues() {
        cookieTextView.string = KeychainService.load(key: Constants.Keychain.cookieString) ?? ""
        orgIdField.stringValue = KeychainService.load(key: Constants.Keychain.organizationId) ?? ""
    }

    func validateAndSave(in window: NSWindow) -> Bool {
        let cookie = cookieTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let orgId = orgIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cookie.isEmpty, !orgId.isEmpty else {
            showAlert(
                in: window,
                title: "Missing credentials",
                message: "Both Organization ID and Cookie header value are required.",
                style: .warning
            )
            return false
        }

        guard UUID(uuidString: orgId) != nil else {
            showAlert(
                in: window,
                title: "Invalid Organization ID",
                message: "Organization ID must be a valid UUID (e.g. xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx).",
                style: .warning
            )
            return false
        }

        let cookieSaved = KeychainService.save(key: Constants.Keychain.cookieString, value: cookie)
        let orgIdSaved = KeychainService.save(key: Constants.Keychain.organizationId, value: orgId)

        guard cookieSaved, orgIdSaved else {
            showAlert(
                in: window,
                title: "Failed to save credentials",
                message: "Credential storage failed. Try restarting the app.",
                style: .critical
            )
            return false
        }

        return true
    }

    private func showAlert(in window: NSWindow, title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window)
    }

    private func setupSubviews() {
        let orgInstructions = CredentialGuide.makeView(CredentialGuide.orgInstructions(), height: 105)

        let orgIdLabel = NSTextField(labelWithString: "Organization ID:")
        orgIdLabel.translatesAutoresizingMaskIntoConstraints = false

        orgIdField.placeholderString = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        orgIdField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        orgIdField.translatesAutoresizingMaskIntoConstraints = false

        let cookieInstructions = CredentialGuide.makeView(CredentialGuide.cookieInstructions(), height: 16)

        let cookieLabel = NSTextField(labelWithString: "Cookie header value:")
        cookieLabel.translatesAutoresizingMaskIntoConstraints = false

        cookieScrollView.hasVerticalScroller = true
        cookieScrollView.borderType = .bezelBorder
        cookieScrollView.translatesAutoresizingMaskIntoConstraints = false
        cookieTextView.isEditable = true
        cookieTextView.isSelectable = true
        cookieTextView.isRichText = false
        cookieTextView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        cookieTextView.isAutomaticQuoteSubstitutionEnabled = false
        cookieTextView.isAutomaticDashSubstitutionEnabled = false
        cookieTextView.isAutomaticTextReplacementEnabled = false
        cookieTextView.textContainer?.widthTracksTextView = true
        cookieTextView.autoresizingMask = [.width]
        cookieScrollView.documentView = cookieTextView

        for view in [orgInstructions, orgIdLabel, orgIdField, cookieInstructions, cookieLabel, cookieScrollView] as [NSView] {
            addSubview(view)
        }

        activateConstraints(orgInstructions: orgInstructions, orgIdLabel: orgIdLabel, cookieInstructions: cookieInstructions, cookieLabel: cookieLabel)
    }

    private func activateConstraints(orgInstructions: NSView, orgIdLabel: NSView, cookieInstructions: NSView, cookieLabel: NSView) {
        NSLayoutConstraint.activate([
            orgInstructions.leadingAnchor.constraint(equalTo: leadingAnchor),
            orgInstructions.trailingAnchor.constraint(equalTo: trailingAnchor),
            orgInstructions.topAnchor.constraint(equalTo: topAnchor),

            orgIdLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            orgIdLabel.topAnchor.constraint(equalTo: orgInstructions.bottomAnchor, constant: 10),

            orgIdField.leadingAnchor.constraint(equalTo: leadingAnchor),
            orgIdField.trailingAnchor.constraint(equalTo: trailingAnchor),
            orgIdField.topAnchor.constraint(equalTo: orgIdLabel.bottomAnchor, constant: 4),

            cookieInstructions.leadingAnchor.constraint(equalTo: leadingAnchor),
            cookieInstructions.trailingAnchor.constraint(equalTo: trailingAnchor),
            cookieInstructions.topAnchor.constraint(equalTo: orgIdField.bottomAnchor, constant: 16),

            cookieLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            cookieLabel.topAnchor.constraint(equalTo: cookieInstructions.bottomAnchor, constant: 10),

            cookieScrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            cookieScrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            cookieScrollView.topAnchor.constraint(equalTo: cookieLabel.bottomAnchor, constant: 4),
            cookieScrollView.heightAnchor.constraint(greaterThanOrEqualToConstant: 60),
            cookieScrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }
}
