import Foundation

// Tracks the last seen state of authored PRs to detect new activity
final class PRActivityStore {
    private let key = "prActivitySnapshots"

    struct Snapshot: Codable {
        let prID: Int
        let updatedAt: Date
        let commentCount: Int
        let approvalLogins: [String]   // logins who approved
        let changesLogins: [String]    // logins who requested changes
    }

    func load() -> [Int: Snapshot] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([Snapshot].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.prID, $0) })
    }

    func save(_ snapshots: [Int: Snapshot]) {
        if let data = try? JSONEncoder().encode(Array(snapshots.values)) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
