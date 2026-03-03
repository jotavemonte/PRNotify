import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    var onSave: (() -> Void)?

    private var tokenField:       NSSecureTextField!
    private var usernameField:    NSTextField!
    private var maxPRsField:      NSTextField!
    private var maxRecentField:   NSTextField!
    private var reviewPopup:      NSPopUpButton!
    private var intervalField:    NSTextField!
    private var statusLabel:      NSTextField!

    convenience init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        w.title = "PRNotify Settings"
        w.center()
        self.init(window: w)
        w.delegate = self
        buildUI()
        loadValues()
    }

    // MARK: - Build UI

    private func buildUI() {
        guard let cv = window?.contentView else { return }
        var y: CGFloat = 296
        let lx: CGFloat = 20, lw: CGFloat = 190, fw: CGFloat = 200, fx: CGFloat = 218

        func row(label: String, field: NSView) {
            let lbl = NSTextField(labelWithString: label)
            lbl.alignment = .right
            lbl.frame = NSRect(x: lx, y: y, width: lw, height: 22)
            field.frame = NSRect(x: fx, y: y, width: fw, height: 22)
            cv.addSubview(lbl); cv.addSubview(field)
            y -= 34
        }

        tokenField = NSSecureTextField(); row(label: "GitHub Token:", field: tokenField)
        tokenField.placeholderString = "ghp_… (or set $GITHUB_TOKEN)"

        usernameField = NSTextField(); row(label: "GitHub Username:", field: usernameField)
        usernameField.placeholderString = "your-github-login"

        let inferBtn = NSButton(title: "Auto-detect", target: self, action: #selector(inferUsername))
        inferBtn.frame = NSRect(x: fx, y: y, width: 110, height: 22)
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: fx + 118, y: y, width: fw - 118, height: 22)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        cv.addSubview(inferBtn); cv.addSubview(statusLabel)
        y -= 34

        maxPRsField = NSTextField(); row(label: "Max PRs to show:", field: maxPRsField)
        maxRecentField = NSTextField(); row(label: "Max recent PRs:", field: maxRecentField)

        reviewPopup = NSPopUpButton()
        reviewPopup.addItems(withTitles: [
            "user-review-requested (directly you)",
            "review-requested (you or your teams)"
        ])
        row(label: "Review filter:", field: reviewPopup)

        intervalField = NSTextField(); row(label: "Poll interval (seconds):", field: intervalField)

        // Buttons
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        save.frame = NSRect(x: fx + fw - 80, y: 12, width: 80, height: 32)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: fx + fw - 166, y: 12, width: 80, height: 32)
        cv.addSubview(save); cv.addSubview(cancel)
    }

    // MARK: - Data

    private func loadValues() {
        let s = Settings.load()
        tokenField.stringValue     = s.githubToken ?? ""
        usernameField.stringValue  = s.githubUsername
        maxPRsField.stringValue    = "\(s.maxPRsToShow)"
        maxRecentField.stringValue = "\(s.maxRecentPRsToShow)"
        reviewPopup.selectItem(at: s.useUserReviewRequested ? 0 : 1)
        intervalField.stringValue  = "\(s.pollIntervalSeconds)"
    }

    @objc private func save() {
        var s = Settings.load()
        let tok = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.githubToken             = tok.isEmpty ? nil : tok
        s.githubUsername          = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        s.maxPRsToShow            = Int(maxPRsField.stringValue) ?? 20
        s.maxRecentPRsToShow      = Int(maxRecentField.stringValue) ?? 10
        s.useUserReviewRequested  = reviewPopup.indexOfSelectedItem == 0
        s.pollIntervalSeconds     = Int(intervalField.stringValue) ?? 120
        s.save()
        onSave?()
        window?.close()
    }

    @objc private func cancel() { window?.close() }

    @objc private func inferUsername() {
        statusLabel.stringValue = "Detecting…"
        GitHubService().resolveUsername { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let username):
                    self?.usernameField.stringValue = username
                    self?.statusLabel.stringValue = "✓"
                case .failure:
                    self?.statusLabel.stringValue = "Not found"
                    let alert = NSAlert()
                    alert.messageText = "Could not detect username"
                    alert.informativeText = "Set GITHUB_TOKEN above or run `gh auth login` in Terminal."
                    alert.beginSheetModal(for: self!.window!)
                }
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
