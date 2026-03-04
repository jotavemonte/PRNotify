import Foundation

final class RecentPRsStore {
    private let key = "recentPRs"
    private let hardCap = 50

    func load() -> [PullRequest] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let entries = try? JSONDecoder().decode([Entry].self, from: data)
        else { return [] }
        return entries.sorted { $0.visitedAt > $1.visitedAt }.map { $0.pr }
    }

    func clear() {
        UserDefaults.standard.removeObject(forKey: key)
    }

    func record(_ pr: PullRequest) {
        var entries = loadEntries()
        entries.removeAll { $0.pr.id == pr.id }
        entries.insert(Entry(pr: pr, visitedAt: Date()), at: 0)
        save(Array(entries.prefix(hardCap)))
    }

    private func loadEntries() -> [Entry] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        return (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
    }

    private func save(_ entries: [Entry]) {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private struct Entry: Codable {
        let pr: PullRequest
        let visitedAt: Date
    }
}
