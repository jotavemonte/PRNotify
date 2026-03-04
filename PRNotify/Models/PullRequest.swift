import Foundation

struct PullRequest: Codable, Equatable, Identifiable {
    let id: Int
    let number: Int
    let title: String
    let htmlURL: String
    let repositoryName: String
    let createdAt: Date
    let author: String

    enum CodingKeys: String, CodingKey {
        case id, number, title
        case htmlURL    = "html_url"
        case createdAt  = "created_at"
        case user, repository_url, pull_request
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(Int.self,    forKey: .id)
        number    = try c.decode(Int.self,    forKey: .number)
        title     = try c.decode(String.self, forKey: .title)
        htmlURL   = try c.decode(String.self, forKey: .htmlURL)
        createdAt = try c.decode(Date.self,   forKey: .createdAt)

        let userContainer = try c.nestedContainer(keyedBy: UserCodingKeys.self, forKey: .user)
        author = try userContainer.decode(String.self, forKey: .login)

        let repoURL = try c.decode(String.self, forKey: .repository_url)
        repositoryName = repoURL.components(separatedBy: "/repos/").last ?? repoURL
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,                forKey: .id)
        try c.encode(number,            forKey: .number)
        try c.encode(title,             forKey: .title)
        try c.encode(htmlURL,           forKey: .htmlURL)
        try c.encode(createdAt,         forKey: .createdAt)
        try c.encode(["login": author], forKey: .user)
        try c.encode("https://api.github.com/repos/\(repositoryName)", forKey: .repository_url)
    }

    private enum UserCodingKeys: String, CodingKey { case login }

    init(id: Int, number: Int, title: String, htmlURL: String,
         repositoryName: String, createdAt: Date, author: String) {
        self.id = id; self.number = number; self.title = title
        self.htmlURL = htmlURL; self.repositoryName = repositoryName
        self.createdAt = createdAt; self.author = author
    }
}

extension Array where Element == PullRequest {
    func sorted(by order: Settings.SortOrder) -> [PullRequest] {
        switch order {
        case .createdAsc:  return sorted { $0.createdAt < $1.createdAt }
        case .createdDesc: return sorted { $0.createdAt > $1.createdAt }
        }
    }
}

// MARK: - PR Status

struct PRStatus {
    enum CIStatus { case passing, failing, pending, unknown }
    enum ReviewDecision { case approved, changesRequested, reviewRequired, unknown }

    let ciStatus: CIStatus
    let reviewDecision: ReviewDecision
    let mergeableState: String  // "clean", "dirty", "blocked", "behind", "unstable", "unknown"

    var isReadyToMerge: Bool { mergeableState == "clean" }
    var hasIssues: Bool {
        ciStatus == .failing || reviewDecision == .changesRequested || mergeableState == "dirty"
    }
}
