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
        statusMap: [Int: PRStatus],
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

        // Review Queue — sorted per settings
        for pr in prs.sorted(by: settings.reviewQueueSort).prefix(settings.maxPRsToShow) {
            handler.register(pr: pr, handler: onOpenPR)
            let item = NSMenuItem(
                title: "[\(pr.repositoryName)] #\(pr.number) \(pr.title)".capped(65),
                action: #selector(MenuActionHandler.openPR(_:)),
                keyEquivalent: "")
            item.target = handler
            item.representedObject = pr
            item.image = statusIcon(for: pr, status: statusMap[pr.id],
                                    slaBreachDays: settings.reviewSLADays, showClock: true)
            item.toolTip = tooltip(for: pr, status: statusMap[pr.id],
                                   slaBreachDays: settings.reviewSLADays, isReviewQueue: true, showClock: true)
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

        // Recent PRs — newest first
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
                item.image = statusIcon(for: pr, status: statusMap[pr.id],
                                        slaBreachDays: settings.reviewSLADays, showClock: true) ?? emptyIcon
                item.toolTip = tooltip(for: pr, status: statusMap[pr.id],
                                       slaBreachDays: settings.reviewSLADays, isReviewQueue: false, showClock: true)
                menu.addItem(item)
            }
        }

        menu.addItem(.separator())

        // Authored PRs — my open PRs
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
                item.image = statusIcon(for: pr, status: statusMap[pr.id],
                                        slaBreachDays: settings.reviewSLADays, showClock: true)
                item.toolTip = tooltip(for: pr, status: statusMap[pr.id],
                                       slaBreachDays: settings.reviewSLADays, isReviewQueue: false, showClock: true)
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

    // MARK: - Status icon (SF Symbols)

    private static func statusIcon(
        for pr: PullRequest,
        status: PRStatus?,
        slaBreachDays: Int,
        showClock: Bool
    ) -> NSImage? {
        let ageInDays = Int(Date().timeIntervalSince(pr.createdAt) / 86400)

        if let status {
            if status.isReadyToMerge {
                return symbol("checkmark.circle", color: .systemGreen)
            } else if status.hasIssues {
                return symbol("xmark.circle", color: .systemRed)
            }
        }

        if showClock && ageInDays >= slaBreachDays {
            return symbol("clock.circle", color: .systemOrange)
        }

        return nil
    }

    private static let emptyIcon: NSImage = {
        let img = NSImage(size: NSSize(width: 12, height: 12))
        return img
    }()

    private static func symbol(_ name: String, color: NSColor) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    // MARK: - Tooltip

    private static func tooltip(
        for pr: PullRequest,
        status: PRStatus?,
        slaBreachDays: Int,
        isReviewQueue: Bool,
        showClock: Bool
    ) -> String {
        var lines: [String] = []

        var header = "[\(pr.repositoryName)] #\(pr.number): \(pr.title)"
        if isReviewQueue { header += "\nby @\(pr.author)" }
        lines.append(header)

        if let status {
            if status.isReadyToMerge {
                lines.append("✓ Ready to merge: CI passing, no changes requested")
            } else if status.hasIssues {
                var reasons: [String] = []
                if status.ciStatus == .failing { reasons.append("CI checks failing") }
                if status.reviewDecision == .changesRequested { reasons.append("Changes requested") }
                if status.mergeableState == "dirty" { reasons.append("Merge conflict") }
                lines.append("✗ Has issues: \(reasons.joined(separator: ", "))")
            } else if status.ciStatus == .pending {
                lines.append("⏳ CI checks pending")
            }
        }

        if showClock {
            let ageInDays = Int(Date().timeIntervalSince(pr.createdAt) / 86400)
            if ageInDays >= slaBreachDays {
                lines.append("⏰ Waiting \(ageInDays) day\(ageInDays == 1 ? "" : "s") for review")
            }
        }

        return lines.joined(separator: "\n")
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
