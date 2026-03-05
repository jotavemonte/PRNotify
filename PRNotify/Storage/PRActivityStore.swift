import Foundation

// Tracks the last seen state of authored PRs to detect new activity
final class PRActivityStore {
    private let key = "prActivitySnapshots"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    struct Snapshot: Codable {
        let prID: Int
        let commentCount: Int
        let approvalLogins: [String]   // logins who approved
        let changesLogins: [String]    // logins who requested changes
    }

    func load() -> [Int: Snapshot] {
        guard let data = defaults.data(forKey: key),
              let list = try? JSONDecoder().decode([Snapshot].self, from: data)
        else { return [:] }
        return Dictionary(uniqueKeysWithValues: list.map { ($0.prID, $0) })
    }

    func save(_ snapshots: [Int: Snapshot]) {
        if let data = try? JSONEncoder().encode(Array(snapshots.values)) {
            defaults.set(data, forKey: key)
        }
    }
}
