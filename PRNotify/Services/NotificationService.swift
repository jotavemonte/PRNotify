import UserNotifications
import AppKit

final class NotificationService: NSObject, UNUserNotificationCenterDelegate {

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notifyNewPRs(_ prs: [PullRequest]) {
        guard !prs.isEmpty else { return }
        let content = UNMutableNotificationContent()
        content.sound = .default

        if prs.count == 1, let pr = prs.first {
            content.title = "New PR Review Requested"
            content.body  = "[\(pr.repositoryName)] #\(pr.number): \(pr.title)"
            content.userInfo = ["prURL": pr.htmlURL]
        } else {
            content.title = "\(prs.count) New PR Reviews Requested"
            content.body  = prs.prefix(3).map { "• [\($0.repositoryName)] #\($0.number)" }.joined(separator: "\n")
        }

        let req = UNNotificationRequest(
            identifier: "prnotify-\(Date().timeIntervalSince1970)",
            content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    func notifyApproval(pr: PullRequest, by login: String) {
        fire(id: "approve-\(pr.id)-\(login)",
             title: "PR Approved ✓",
             body: "@\(login) approved [\(pr.repositoryName)] #\(pr.number): \(pr.title)",
             prURL: pr.htmlURL)
    }

    func notifyChangesRequested(pr: PullRequest, by login: String) {
        fire(id: "changes-\(pr.id)-\(login)",
             title: "Changes Requested",
             body: "@\(login) requested changes on [\(pr.repositoryName)] #\(pr.number): \(pr.title)",
             prURL: pr.htmlURL)
    }

    func notifyNewComment(pr: PullRequest) {
        fire(id: "comment-\(pr.id)-\(Date().timeIntervalSince1970)",
             title: "New Comment",
             body: "New comment on [\(pr.repositoryName)] #\(pr.number): \(pr.title)",
             prURL: pr.htmlURL)
    }

    private func fire(id: String, title: String, body: String, prURL: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default
        content.userInfo = ["prURL": prURL]
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil))
    }

    // Open PR URL when notification is clicked
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler done: @escaping () -> Void) {
        if let urlStr = response.notification.request.content.userInfo["prURL"] as? String,
           let url = URL(string: urlStr) {
            NSWorkspace.shared.open(url)
        }
        done()
    }

    // Show banner even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler done: @escaping (UNNotificationPresentationOptions) -> Void) {
        done([.banner, .sound])
    }
}
