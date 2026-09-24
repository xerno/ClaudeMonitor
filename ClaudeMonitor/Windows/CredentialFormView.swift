import AppKit

@MainActor
final class CredentialFormView: NSView {
    enum Mode {
        case edit(profileId: String)
        case add
        case setup
    }

    private let nameField = NSTextField()
    private let orgIdField = NSTextField()
    private let cookieTextView = NSTextView()
    private let cookieScrollView = NSScrollView()

    private let profileStore: ProfileStore
    private let mode: Mode

    init(profileStore: ProfileStore, mode: Mode) {
        self.profileStore = profileStore
        self.mode = mode
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    var displayedName: String { nameField.stringValue }

    func simulateEntry(name: String, organizationId: String, cookie: String) {
        nameField.stringValue = name
        orgIdField.stringValue = organizationId
        cookieTextView.string = cookie
    }

    private var editedProfile: Profile? {
        guard case .edit(let profileId) = mode else { return nil }
        return profileStore.profiles.first { $0.id == profileId }
    }

    func loadSavedValues() {
        if let profile = editedProfile {
            nameField.stringValue = profile.name
            orgIdField.stringValue = profile.organizationId
            cookieTextView.string = profileStore.cookie(for: profile) ?? ""
        } else {
            nameField.stringValue = ""
            orgIdField.stringValue = ""
            cookieTextView.string = ""
        }
    }

    func clearCookie() {
        cookieTextView.string = ""
    }

    @discardableResult
    func validateAndSave(in window: NSWindow) -> String? {
        guard let fields = validatedFields(in: window) else { return nil }
        return persist(fields, in: window)
    }

    private typealias Fields = (name: String, orgId: String, cookie: String)

    private func validatedFields(in window: NSWindow) -> Fields? {
        let name = nameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cookie = cookieTextView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        let orgId = orgIdField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, !cookie.isEmpty, !orgId.isEmpty else {
            showAlert(
                in: window,
                title: String(localized: "credentials.alert.missing.title", bundle: .module),
                message: String(localized: "credentials.alert.missing.message", bundle: .module),
                style: .warning
            )
            return nil
        }
        guard UUID(uuidString: orgId) != nil else {
            showAlert(
                in: window,
                title: String(localized: "credentials.alert.invalid_org.title", bundle: .module),
                message: String(localized: "credentials.alert.invalid_org.message", bundle: .module),
                style: .warning
            )
            return nil
        }
        return (name, orgId, cookie)
    }

    private func persist(_ fields: Fields, in window: NSWindow) -> String? {
        do {
            if let profile = profileToUpdate(organizationId: fields.orgId) {
                try profileStore.updateProfile(
                    id: profile.id, name: fields.name,
                    organizationId: fields.orgId, cookie: fields.cookie
                )
                if case .setup = mode {
                    activateIfActiveCookieUnreadable(profileId: profile.id)
                }
                return profile.id
            }
            let created = try profileStore.addProfile(
                name: fields.name, organizationId: fields.orgId, cookie: fields.cookie
            )
            activateIfActiveCookieUnreadable(profileId: created.id)
            return created.id
        } catch ProfileStoreError.duplicateOrganization {
            showAlert(
                in: window,
                title: String(localized: "credentials.alert.duplicate_org.title", bundle: .module),
                message: String(localized: "credentials.alert.duplicate_org.message", bundle: .module),
                style: .warning
            )
            return nil
        } catch ProfileStoreError.limitReached {
            showAlert(
                in: window,
                title: String(localized: "credentials.alert.limit_reached.title", bundle: .module),
                message: String(localized: "credentials.alert.limit_reached.message", bundle: .module),
                style: .warning
            )
            return nil
        } catch {
            showAlert(
                in: window,
                title: String(localized: "credentials.alert.save_failed.title", bundle: .module),
                message: String(localized: "credentials.alert.save_failed.message", bundle: .module),
                style: .critical
            )
            return nil
        }
    }

    private func profileToUpdate(organizationId: String) -> Profile? {
        switch mode {
        case .edit:
            return editedProfile
        case .add:
            return nil
        case .setup:
            let organization = UUID(uuidString: organizationId)
            return profileStore.profiles.first { UUID(uuidString: $0.organizationId) == organization }
        }
    }

    private func activateIfActiveCookieUnreadable(profileId: String) {
        guard profileStore.activeCookie?.isEmpty ?? true else { return }
        profileStore.setActive(id: profileId)
    }

    private func showAlert(in window: NSWindow, title: String, message: String, style: NSAlert.Style) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = style
        alert.addButton(withTitle: String(localized: "credentials.alert.ok", bundle: .module))
        alert.beginSheetModal(for: window)
    }

    private func setupSubviews() {
        let nameLabel = NSTextField(labelWithString: String(localized: "credentials.field.name", bundle: .module))
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        nameField.placeholderString = String(localized: "credentials.field.name_placeholder", bundle: .module)
        nameField.translatesAutoresizingMaskIntoConstraints = false

        let orgInstructions = CredentialGuide.makeView(CredentialGuide.orgInstructions(), height: 105)

        let orgIdLabel = NSTextField(labelWithString: String(localized: "credentials.field.org_id", bundle: .module))
        orgIdLabel.translatesAutoresizingMaskIntoConstraints = false

        orgIdField.placeholderString = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
        orgIdField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        orgIdField.translatesAutoresizingMaskIntoConstraints = false

        let cookieInstructions = CredentialGuide.makeView(CredentialGuide.cookieInstructions(), height: 16)

        let cookieLabel = NSTextField(labelWithString: String(localized: "credentials.field.cookie", bundle: .module))
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
        cookieTextView.isAutomaticSpellingCorrectionEnabled = false
        cookieTextView.isAutomaticLinkDetectionEnabled = false
        cookieTextView.isAutomaticDataDetectionEnabled = false
        cookieTextView.isAutomaticTextCompletionEnabled = false
        cookieTextView.isContinuousSpellCheckingEnabled = false
        cookieTextView.isGrammarCheckingEnabled = false
        cookieTextView.textContainer?.widthTracksTextView = true
        cookieTextView.autoresizingMask = [.width]
        cookieScrollView.documentView = cookieTextView

        for view in [
            nameLabel, nameField, orgInstructions, orgIdLabel, orgIdField,
            cookieInstructions, cookieLabel, cookieScrollView,
        ] as [NSView] {
            addSubview(view)
        }

        activateConstraints(
            nameLabel: nameLabel, orgInstructions: orgInstructions, orgIdLabel: orgIdLabel,
            cookieInstructions: cookieInstructions, cookieLabel: cookieLabel
        )
    }

    private func activateConstraints(
        nameLabel: NSView, orgInstructions: NSView, orgIdLabel: NSView,
        cookieInstructions: NSView, cookieLabel: NSView
    ) {
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.topAnchor.constraint(equalTo: topAnchor),

            nameField.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameField.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameField.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 4),

            orgInstructions.leadingAnchor.constraint(equalTo: leadingAnchor),
            orgInstructions.trailingAnchor.constraint(equalTo: trailingAnchor),
            orgInstructions.topAnchor.constraint(equalTo: nameField.bottomAnchor, constant: 16),

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
