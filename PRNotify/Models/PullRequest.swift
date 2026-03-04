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

struct GitHubSearchResponse: Decodable {
    let items: [PullRequest]
}

// MARK: - gh CLI response models
struct CLIPullRequest: Decodable {
    let number: Int
    let title: String
    let url: String
    let createdAt: Date
    let repository: CLIRepository
    let author: CLIAuthor

    func asPullRequest() -> PullRequest {
        let stableID = abs("\(repository.nameWithOwner)#\(number)".hashValue)
        return PullRequest(
            id: stableID,
            number: number,
            title: title,
            htmlURL: url,
            repositoryName: repository.nameWithOwner,
            createdAt: createdAt,
            author: author.login
        )
    }

    struct CLIRepository: Decodable { let nameWithOwner: String }
    struct CLIAuthor: Decodable { let login: String }
    struct CLIStatusCheck: Decodable { let state: String }

    let reviewDecision: String?
    let statusCheckRollup: [CLIStatusCheck]?
    let mergeStateStatus: String?

    func asPRStatus() -> PRStatus {
        let ci: PRStatus.CIStatus
        if let checks = statusCheckRollup, !checks.isEmpty {
            let states = checks.map { $0.state.uppercased() }
            if states.contains(where: { $0 == "FAILURE" || $0 == "ERROR" }) {
                ci = .failing
            } else if states.contains(where: { $0 == "PENDING" || $0 == "EXPECTED" }) {
                ci = .pending
            } else {
                ci = .passing
            }
        } else {
            ci = .unknown
        }

        let review: PRStatus.ReviewDecision
        switch reviewDecision?.uppercased() {
        case "APPROVED":           review = .approved
        case "CHANGES_REQUESTED":  review = .changesRequested
        case "REVIEW_REQUIRED":    review = .reviewRequired
        default:                   review = .unknown
        }

        return PRStatus(
            ciStatus: ci,
            reviewDecision: review,
            mergeableState: mergeStateStatus?.lowercased() ?? "unknown"
        )
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
