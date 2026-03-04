import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var pollTimer: Timer?
    private var currentPRs: [PullRequest] = []
    private var authoredPRs: [PullRequest] = []
    private var knownPRIDs: Set<Int> = []        // empty = first run (no notifications)
    private var prStatusMap: [Int: PRStatus] = [:]

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
        updateIcon(count: nil)  // loading state
        statusItem.menu = buildMenu()

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
                case .failure(let err):              NSLog("[PRNotify] fetch error: %@", "\(err)")
                }
            }
        }

        pollAuthoredPRActivity(username: settings.githubUsername)
    }

    private func pollAuthoredPRActivity(username: String) {
        let settings = Settings.load()
        github.fetchAuthoredPRs(username: username, sort: settings.authoredPRsSort) { [weak self] result in
            guard let self, case .success(let (prs, statuses)) = result else { return }
            DispatchQueue.main.async {
                self.authoredPRs = prs
                self.prStatusMap.merge(statuses) { _, new in new }
                self.statusItem.menu = self.buildMenu()
            }

            let snapshots = self.activityStore.load()
            let isFirstRun = snapshots.isEmpty
            let openIDs = Set(prs.map { $0.id })

            // Use a serial queue to safely accumulate updates from concurrent PR fetches
            let queue = DispatchQueue(label: "com.prnotify.activity")
            var updated = snapshots.filter { openIDs.contains($0.key) }  // prune closed PRs
            let group = DispatchGroup()

            for pr in prs {
                group.enter()
                self.github.fetchPRActivity(repoName: pr.repositoryName, number: pr.number) { [weak self] result in
                    defer { group.leave() }
                    guard let self, case .success(let activity) = result else { return }

                    queue.sync {
                        let prev = snapshots[pr.id]
                        if !isFirstRun, let prev {
                            if activity.commentCount > prev.commentCount {
                                self.notifications.notifyNewComment(pr: pr)
                            }
                            for login in activity.approvalLogins where !prev.approvalLogins.contains(login) {
                                self.notifications.notifyApproval(pr: pr, by: login)
                            }
                            for login in activity.changesLogins where !prev.changesLogins.contains(login) {
                                self.notifications.notifyChangesRequested(pr: pr, by: login)
                            }
                        }
                        updated[pr.id] = PRActivityStore.Snapshot(
                            prID: pr.id,
                            commentCount: activity.commentCount,
                            approvalLogins: activity.approvalLogins,
                            changesLogins: activity.changesLogins
                        )
                    }
                }
            }

            group.notify(queue: queue) { [weak self] in
                self?.activityStore.save(updated)
            }
        }
    }

    private func handleFreshPRs(_ fresh: [PullRequest], statuses: [Int: PRStatus]) {
        let freshIDs = Set(fresh.map { $0.id })

        // Only notify on subsequent polls (skip first-run baseline)
        if !knownPRIDs.isEmpty {
            let newPRs = fresh.filter { !knownPRIDs.contains($0.id) }
            if !newPRs.isEmpty { notifications.notifyNewPRs(newPRs) }
        }

        knownPRIDs = freshIDs
        currentPRs = fresh
        prStatusMap.merge(statuses) { _, new in new }
        updateIcon(count: fresh.count)
        statusItem.menu = buildMenu()
    }

    // MARK: - Icon

    private func updateIcon(count: Int?) {
        guard let btn = statusItem.button else { return }
        btn.image = branchIcon
        btn.title = count.map { $0 == 0 ? "" : " \($0)" } ?? ""
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
                self?.startPolling()
                self?.statusItem.menu = self?.buildMenu()
            }
        }
        NSApp.setActivationPolicy(.regular)
        settingsWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
