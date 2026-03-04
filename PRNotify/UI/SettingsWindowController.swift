import AppKit

final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    var onSave: (() -> Void)?

    private var tokenField:        NSSecureTextField!
    private var usernameField:     NSTextField!
    private var maxPRsField:       NSTextField!
    private var maxRecentField:    NSTextField!
    private var reviewPopup:       NSPopUpButton!
    private var teamField:         NSTextField!
    private var teamLabel:         NSTextField!
    private var reviewSortPopup:   NSPopUpButton!
    private var authoredSortPopup: NSPopUpButton!
    private var slaField:          NSTextField!
    private var intervalField:     NSTextField!
    private var statusLabel:       NSTextField!

    private var notifyNewPRsCheck:   NSButton!
    private var notifyCommentsCheck: NSButton!
    private var notifyApprovalsCheck: NSButton!
    private var notifyChangesCheck:  NSButton!
    private var notifySLACheck:      NSButton!

    convenience init() {
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 644),
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
        var y: CGFloat = 600
        let lx: CGFloat = 20, lw: CGFloat = 190, fw: CGFloat = 200, fx: CGFloat = 218

        func row(label: String, field: NSView) -> NSTextField {
            let lbl = NSTextField(labelWithString: label)
            lbl.alignment = .right
            lbl.frame = NSRect(x: lx, y: y, width: lw, height: 22)
            field.frame = NSRect(x: fx, y: y, width: fw, height: 22)
            cv.addSubview(lbl); cv.addSubview(field)
            y -= 34
            return lbl
        }

        tokenField = NSSecureTextField()
        tokenField.placeholderString = "ghp_… (or set $GITHUB_TOKEN)"
        _ = row(label: "GitHub Token:", field: tokenField)

        usernameField = NSTextField()
        usernameField.placeholderString = "your-github-login"
        _ = row(label: "GitHub Username:", field: usernameField)

        let inferBtn = NSButton(title: "Auto-detect", target: self, action: #selector(inferUsername))
        inferBtn.frame = NSRect(x: fx, y: y, width: 110, height: 22)
        statusLabel = NSTextField(labelWithString: "")
        statusLabel.frame = NSRect(x: fx + 118, y: y, width: fw - 118, height: 22)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        cv.addSubview(inferBtn); cv.addSubview(statusLabel)
        y -= 34

        maxPRsField = NSTextField()
        _ = row(label: "Max PRs to show:", field: maxPRsField)

        maxRecentField = NSTextField()
        _ = row(label: "Max recent PRs:", field: maxRecentField)

        reviewPopup = NSPopUpButton()
        reviewPopup.addItems(withTitles: [
            "user-review-requested (directly you)",
            "review-requested (you or your teams)",
            "team-review-requested (specific team)"
        ])
        reviewPopup.target = self
        reviewPopup.action = #selector(reviewFilterChanged)
        _ = row(label: "Review filter:", field: reviewPopup)

        // Team slug field — only enabled when team filter is selected
        teamField = NSTextField()
        teamField.placeholderString = "org/team-slug"
        teamLabel = row(label: "Team:", field: teamField)

        reviewSortPopup = NSPopUpButton()
        reviewSortPopup.addItems(withTitles: sortTitles)
        _ = row(label: "Review queue order:", field: reviewSortPopup)

        authoredSortPopup = NSPopUpButton()
        authoredSortPopup.addItems(withTitles: sortTitles)
        _ = row(label: "My PRs order:", field: authoredSortPopup)

        slaField = NSTextField()
        _ = row(label: "Review SLA (days):", field: slaField)

        intervalField = NSTextField()
        _ = row(label: "Poll interval (seconds):", field: intervalField)

        // Notifications section
        y -= 8
        let sectionLine = NSBox()
        sectionLine.boxType = .separator
        sectionLine.frame = NSRect(x: lx, y: y, width: lx + lw + fw, height: 1)
        cv.addSubview(sectionLine)
        y -= 20

        let sectionLabel = NSTextField(labelWithString: "Notifications")
        sectionLabel.font = .boldSystemFont(ofSize: 13)
        sectionLabel.frame = NSRect(x: fx, y: y, width: fw, height: 20)
        cv.addSubview(sectionLabel)
        y -= 30

        func checkbox(title: String) -> NSButton {
            let btn = NSButton(checkboxWithTitle: title, target: nil, action: nil)
            btn.frame = NSRect(x: lx, y: y, width: lw + fw, height: 22)
            cv.addSubview(btn)
            y -= 28
            return btn
        }

        notifyNewPRsCheck    = checkbox(title: "New PR review requested")
        notifyCommentsCheck  = checkbox(title: "New comment on my PR")
        notifyApprovalsCheck = checkbox(title: "PR approved")
        notifyChangesCheck   = checkbox(title: "Changes requested")
        notifySLACheck       = checkbox(title: "Review SLA breached")

        // Buttons
        let save = NSButton(title: "Save", target: self, action: #selector(save))
        save.bezelStyle = .rounded; save.keyEquivalent = "\r"
        save.frame = NSRect(x: fx + fw - 80, y: 12, width: 80, height: 32)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancel))
        cancel.bezelStyle = .rounded; cancel.keyEquivalent = "\u{1b}"
        cancel.frame = NSRect(x: fx + fw - 166, y: 12, width: 80, height: 32)
        cv.addSubview(save); cv.addSubview(cancel)
    }

    private let sortTitles = ["Oldest first", "Newest first"]

    // MARK: - Data

    private func loadValues() {
        let s = Settings.load()
        tokenField.stringValue      = s.githubToken ?? ""
        usernameField.stringValue   = s.githubUsername
        maxPRsField.stringValue     = "\(s.maxPRsToShow)"
        maxRecentField.stringValue  = "\(s.maxRecentPRsToShow)"
        reviewPopup.selectItem(at: s.reviewFilter.rawValue)
        teamField.stringValue          = s.teamSlug
        reviewSortPopup.selectItem(at: s.reviewQueueSort.rawValue)
        authoredSortPopup.selectItem(at: s.authoredPRsSort.rawValue)
        slaField.stringValue           = "\(s.reviewSLADays)"
        intervalField.stringValue      = "\(s.pollIntervalSeconds)"
        notifyNewPRsCheck.state    = s.notifyNewPRs    ? .on : .off
        notifyCommentsCheck.state  = s.notifyComments  ? .on : .off
        notifyApprovalsCheck.state = s.notifyApprovals ? .on : .off
        notifyChangesCheck.state   = s.notifyChanges   ? .on : .off
        notifySLACheck.state       = s.notifySLA       ? .on : .off
        updateTeamFieldState()
    }

    @objc private func reviewFilterChanged() {
        updateTeamFieldState()
    }

    private func updateTeamFieldState() {
        let isTeam = reviewPopup.indexOfSelectedItem == Settings.ReviewFilter.teamReviewRequested.rawValue
        teamField.isEnabled = isTeam
        teamLabel.textColor = isTeam ? .labelColor : .disabledControlTextColor
        if !isTeam { teamField.textColor = .disabledControlTextColor }
        else { teamField.textColor = .labelColor }
    }

    @objc private func save() {
        var s = Settings.load()
        let tok = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        s.githubToken          = tok.isEmpty ? nil : tok
        s.githubUsername       = usernameField.stringValue.trimmingCharacters(in: .whitespaces)
        s.maxPRsToShow         = Int(maxPRsField.stringValue) ?? 20
        s.maxRecentPRsToShow   = Int(maxRecentField.stringValue) ?? 10
        s.reviewFilter         = Settings.ReviewFilter(rawValue: reviewPopup.indexOfSelectedItem) ?? .userReviewRequested
        s.teamSlug             = teamField.stringValue.trimmingCharacters(in: .whitespaces)
        s.reviewQueueSort      = Settings.SortOrder(rawValue: reviewSortPopup.indexOfSelectedItem) ?? .createdAsc
        s.authoredPRsSort      = Settings.SortOrder(rawValue: authoredSortPopup.indexOfSelectedItem) ?? .createdDesc
        s.reviewSLADays        = Int(slaField.stringValue) ?? 2
        s.pollIntervalSeconds  = Int(intervalField.stringValue) ?? 120
        s.notifyNewPRs         = notifyNewPRsCheck.state    == .on
        s.notifyComments       = notifyCommentsCheck.state  == .on
        s.notifyApprovals      = notifyApprovalsCheck.state == .on
        s.notifyChanges        = notifyChangesCheck.state   == .on
        s.notifySLA            = notifySLACheck.state       == .on
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
