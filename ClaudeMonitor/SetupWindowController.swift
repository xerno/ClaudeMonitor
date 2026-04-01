import AppKit

final class SetupWindowController: NSWindowController, NSWindowDelegate {
    private let credentialForm = CredentialFormView()
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 660, height: 480),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Claude Monitor – Setup"
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

        let title = NSTextField(labelWithString: "Welcome to Claude Monitor")
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.translatesAutoresizingMaskIntoConstraints = false

        let startButton = NSButton(title: "Get Started", target: self, action: #selector(didTapStart))
        startButton.bezelStyle = .rounded
        startButton.keyEquivalent = "\r"
        startButton.translatesAutoresizingMaskIntoConstraints = false

        let skipButton = NSButton(title: "Skip", target: self, action: #selector(didTapSkip))
        skipButton.bezelStyle = .rounded
        skipButton.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(title)
        contentView.addSubview(credentialForm)
        contentView.addSubview(startButton)
        contentView.addSubview(skipButton)

        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            title.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 20),

            credentialForm.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 20),
            credentialForm.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            credentialForm.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 14),

            skipButton.trailingAnchor.constraint(equalTo: startButton.leadingAnchor, constant: -8),
            skipButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),

            startButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -20),
            startButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -16),
        ])
    }

    @objc private func didTapStart() {
        guard let window else { return }
        guard credentialForm.validateAndSave(in: window) else { return }
        close()
        onComplete()
    }

    @objc private func didTapSkip() {
        close()
    }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        WindowManager.bringToFront(window)
    }

    func windowWillClose(_ notification: Notification) {
        WindowManager.revertActivationPolicyIfNeeded(excluding: window)
    }
}
