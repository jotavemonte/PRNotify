import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var spinnerTimer: Timer?
    private var spinnerFrame = 0
    private let spinnerFrames = ["◐", "◓", "◑", "◒"]
    private var currentPRs: [PullRequest] = []
    private var authoredPRs: [PullRequest] = []
    private var knownPRIDs: Set<Int> = []        // empty = first run (no notifications)
    private var prStatusMap: [Int: PRStatus] = [:]
    private var slaNotifiedIDs: Set<Int> = []    // PRs already notified for SLA breach
    private var isFirstPoll = true               // skip all notifications on first poll

    private let github        = GitHubService()
    private let notifications = NotificationService()
    private let recentStore   = RecentPRsStore()
    private let activityStore = PRActivityStore()
    private var settingsWC:   SettingsWindowController?

    // MARK: - Launch

    func applicationDidFinishLaunching(_ note: Notification) {
        NSApp.setActivationPolicy(.accessory)  // hide Dock icon

        notifications.requestAuthorization()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.menu = buildMenu()
        startSpinner()

        // Register as login item (macOS 13+)
        if #available(macOS 13.0, *) {
            try? SMAppService.mainApp.register()
        }

        let settings = Settings.load()
        if settings.githubUsername.isEmpty {
            github.resolveUsername { [weak self] result in
                if case .success(let name) = result {
                    var s = Settings.load(); s.githubUsername = name; s.save()
                }
                DispatchQueue.main.async { self?.startPolling() }
            }
        } else {
            startPolling()
        }
    }

    // MARK: - Polling

    private func startPolling() {
        poll()
        let interval = TimeInterval(Settings.load().pollIntervalSeconds)
        pollTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        let settings = Settings.load()
        guard !settings.githubUsername.isEmpty else {
            updateIcon(count: 0)
            return
        }

        github.fetchReviewRequested(settings: settings) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let (prs, statuses)):  self?.handleFreshPRs(prs, statuses: statuses)
                case .failure(let err):
                    NSLog("[PRNotify] fetch error: %@", "\(err)")
                    self?.updateIcon(count: nil)
                }
            }
        }

        pollAuthoredPRActivity(username: settings.githubUsername)
    }

    private func pollAuthoredPRActivity(username: String) {
        let settings = Settings.load()
        github.fetchAuthoredPRs(username: username, sort: settings.authoredPRsSort) { [weak self] result in
            guard let self, case .success(let (prs, statuses, activityMap, latestCommentMap)) = result else { return }
            DispatchQueue.main.async {
                self.authoredPRs = prs
                self.prStatusMap.merge(statuses) { _, new in new }
                self.statusItem.menu = self.buildMenu()
            }

            let snapshots = self.activityStore.load()
            let isFirstRun = snapshots.isEmpty
            let openIDs = Set(prs.map { $0.id })
            var updated = snapshots.filter { openIDs.contains($0.key) }  // prune closed PRs

            for pr in prs {
                guard let activity = activityMap[pr.id] else { continue }
                let prev = snapshots[pr.id]
                if !isFirstRun, let prev {
                    let s = Settings.load()
                    if s.notifyComments && activity.commentCount > prev.commentCount {
                        if let comment = latestCommentMap[pr.id] {
                            self.notifications.notifyNewComment(pr: pr, by: comment.authorLogin, preview: comment.body)
                        } else {
                            self.notifications.notifyNewComment(pr: pr, by: "someone", preview: "New comment on \(pr.title)")
                        }
                    }
                    if s.notifyApprovals {
                        for login in activity.approvalLogins where !prev.approvalLogins.contains(login) {
                            self.notifications.notifyApproval(pr: pr, by: login)
                        }
                    }
                    if s.notifyChanges {
                        for login in activity.changesLogins where !prev.changesLogins.contains(login) {
                            self.notifications.notifyChangesRequested(pr: pr, by: login)
                        }
                    }
                }
                updated[pr.id] = PRActivityStore.Snapshot(
                    prID: pr.id,
                    commentCount: activity.commentCount,
                    approvalLogins: activity.approvalLogins,
                    changesLogins: activity.changesLogins
                )
            }

            self.activityStore.save(updated)
        }
    }

    private func handleFreshPRs(_ fresh: [PullRequest], statuses: [Int: PRStatus]) {
        let freshIDs = Set(fresh.map { $0.id })
        let settings = Settings.load()

        if !isFirstPoll {
            // Notify new PRs
            if settings.notifyNewPRs {
                let newPRs = fresh.filter { !knownPRIDs.contains($0.id) }
                if !newPRs.isEmpty { notifications.notifyNewPRs(newPRs) }
            }

            // Notify SLA breaches: only PRs that crossed the threshold since last poll
            // (were not already breached on first poll, and not previously notified)
            if settings.notifySLA {
                let slaThreshold = TimeInterval(settings.reviewSLADays * 86400)
                for pr in fresh {
                    guard !slaNotifiedIDs.contains(pr.id),
                          Date().timeIntervalSince(pr.createdAt) >= slaThreshold else { continue }
                    slaNotifiedIDs.insert(pr.id)
                    notifications.notifySLABreached(pr: pr)
                }
            }
        } else {
            // First poll: seed slaNotifiedIDs with already-breached PRs so we never notify them
            let slaThreshold = TimeInterval(settings.reviewSLADays * 86400)
            for pr in fresh where Date().timeIntervalSince(pr.createdAt) >= slaThreshold {
                slaNotifiedIDs.insert(pr.id)
            }
            isFirstPoll = false
        }

        knownPRIDs = freshIDs
        currentPRs = fresh
        prStatusMap.merge(statuses) { _, new in new }
        updateIcon(count: fresh.count)
        statusItem.menu = buildMenu()
    }

    // MARK: - Icon

    private func updateIcon(count: Int?) {
        stopSpinner()
        guard let btn = statusItem.button else { return }
        btn.attributedTitle = NSAttributedString(string: "")
        btn.image = branchIcon
        btn.title = count.map { $0 == 0 ? "" : " \($0)" } ?? ""
    }

    private func startSpinner() {
        guard let btn = statusItem.button else { return }
        spinnerFrame = 0
        setSpinnerFrame(btn)
        spinnerTimer = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self, let btn = self.statusItem.button else { return }
            self.spinnerFrame = (self.spinnerFrame + 1) % self.spinnerFrames.count
            self.setSpinnerFrame(btn)
        }
    }

    private func setSpinnerFrame(_ btn: NSStatusBarButton) {
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.menuBarFont(ofSize: 0),
            .foregroundColor: NSColor.labelColor
        ]
        btn.attributedTitle = NSAttributedString(string: spinnerFrames[spinnerFrame], attributes: attrs)
        btn.image = nil
    }

    private func stopSpinner() {
        spinnerTimer?.invalidate()
        spinnerTimer = nil
    }

    private var branchIcon: NSImage {
        // Load SVG from app bundle; fall back to SF Symbol if missing
        if let url = Bundle.main.url(forResource: "menubar-icon", withExtension: "svg"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true  // lets macOS invert for dark/light menu bar
            img.size = NSSize(width: 18, height: 18)
            return img
        }
        return NSImage(systemSymbolName: "arrow.branch", accessibilityDescription: nil)!
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        MenuBuilder.build(
            prs:         currentPRs,
            authoredPRs: authoredPRs,
            recentPRs:   recentStore.load(),
            settings:    Settings.load(),
            statusMap:   prStatusMap,
            onOpenPR:    { [weak self] pr in self?.openPR(pr) },
            onSettings:  { [weak self] in self?.openSettings() },
            onQuit:      { NSApp.terminate(nil) }
        )
    }

    private func openPR(_ pr: PullRequest) {
        recentStore.record(pr)
        NSWorkspace.shared.open(URL(string: pr.htmlURL)!)
        statusItem.menu = buildMenu()
    }

    private func openSettings() {
        if settingsWC == nil {
            settingsWC = SettingsWindowController()
            settingsWC?.onSave = { [weak self] in
                self?.pollTimer?.invalidate()
                self?.isFirstPoll = true
                self?.knownPRIDs = []
                self?.slaNotifiedIDs = []
                self?.startSpinner()
                self?.startPolling()
            }
        }
        NSApp.setActivationPolicy(.regular)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
