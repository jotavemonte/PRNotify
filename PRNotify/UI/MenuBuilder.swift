import AppKit

// NSMenuItem actions require @objc methods on a real object.
// This singleton trampoline bridges closures to Obj-C selector dispatch.
final class MenuActionHandler: NSObject {
    static let shared = MenuActionHandler()
    var prHandlers: [Int: (PullRequest) -> Void] = [:]
    var settingsHandler: (() -> Void)?
    var quitHandler: (() -> Void)?

    func register(pr: PullRequest, handler: @escaping (PullRequest) -> Void) {
        prHandlers[pr.id] = handler
    }

    @objc func openPR(_ sender: NSMenuItem) {
        guard let pr = sender.representedObject as? PullRequest else { return }
        prHandlers[pr.id]?(pr)
    }

    @objc func openURL(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open(url)
    }

    @objc func openSettings(_ sender: Any) { settingsHandler?() }
    @objc func quit(_ sender: Any)         { quitHandler?() }
}

enum MenuBuilder {

    static func build(
        prs: [PullRequest],
        authoredPRs: [PullRequest],
        recentPRs: [PullRequest],
        settings: Settings,
        onOpenPR: @escaping (PullRequest) -> Void,
        onSettings: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) -> NSMenu {
        let handler = MenuActionHandler.shared
        handler.prHandlers = [:]
        handler.settingsHandler = onSettings
        handler.quitHandler = onQuit

        let menu = NSMenu()

        // Header
        menu.addItem(disabled(prs.isEmpty
            ? "No PRs awaiting review"
            : "\(prs.count) PR\(prs.count == 1 ? "" : "s") awaiting review"))
        menu.addItem(.separator())

        // PR list — sorted per settings
        for pr in prs.sorted(by: settings.reviewQueueSort).prefix(settings.maxPRsToShow) {
            handler.register(pr: pr, handler: onOpenPR)
            let item = NSMenuItem(
                title: "[\(pr.repositoryName)] #\(pr.number) \(pr.title)".capped(65),
                action: #selector(MenuActionHandler.openPR(_:)),
                keyEquivalent: "")
            item.target = handler
            item.representedObject = pr
            item.toolTip = "[\(pr.repositoryName)] #\(pr.number): \(pr.title)\nby @\(pr.author)"
            menu.addItem(item)
        }

        // "See More" link
        if let webURL = settings.webURL {
            let more = NSMenuItem(
                title: "See More on GitHub…",
                action: #selector(MenuActionHandler.openURL(_:)),
                keyEquivalent: "")
            more.target = handler
            more.representedObject = webURL
            menu.addItem(more)
        }

        menu.addItem(.separator())

        // Recent PRs (review queue only) — newest first
        let recent = Array(recentPRs.prefix(settings.maxRecentPRsToShow))
        if !recent.isEmpty {
            menu.addItem(disabled("Recently Visited"))
            for pr in recent {
                handler.register(pr: pr, handler: onOpenPR)
                let item = NSMenuItem(
                    title: "[\(pr.repositoryName)] #\(pr.number) \(pr.title)".capped(65),
                    action: #selector(MenuActionHandler.openPR(_:)),
                    keyEquivalent: "")
                item.target = handler
                item.representedObject = pr
                item.toolTip = "[\(pr.repositoryName)] #\(pr.number): \(pr.title)\nby @\(pr.author)"
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Authored PRs — my open PRs, sorted per settings
        if authoredPRs.isEmpty {
            menu.addItem(disabled("No open PRs"))
        } else {
            menu.addItem(disabled("My Open PRs"))
            for pr in authoredPRs.sorted(by: settings.authoredPRsSort) {
                handler.register(pr: pr, handler: onOpenPR)
                let item = NSMenuItem(
                    title: "[\(pr.repositoryName)] #\(pr.number) \(pr.title)".capped(65),
                    action: #selector(MenuActionHandler.openPR(_:)),
                    keyEquivalent: "")
                item.target = handler
                item.representedObject = pr
                item.toolTip = "[\(pr.repositoryName)] #\(pr.number): \(pr.title)"
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(MenuActionHandler.openSettings(_:)),
            keyEquivalent: ",")
        settingsItem.target = handler
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(
            title: "Quit PRNotify",
            action: #selector(MenuActionHandler.quit(_:)),
            keyEquivalent: "q")
        quitItem.target = handler
        menu.addItem(quitItem)

        return menu
    }

    private static func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}

private extension String {
    func capped(_ max: Int) -> String {
        count > max ? String(prefix(max - 1)) + "…" : self
    }
}
