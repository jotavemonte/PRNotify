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
        case htmlURL = "html_url"
        case createdAt = "created_at"
        case user, repository_url, pull_request
    }

    // GitHub Search API nests user.login and derives repo from repository_url
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id       = try c.decode(Int.self, forKey: .id)
        number   = try c.decode(Int.self, forKey: .number)
        title    = try c.decode(String.self, forKey: .title)
        htmlURL  = try c.decode(String.self, forKey: .htmlURL)
        createdAt = try c.decode(Date.self, forKey: .createdAt)

        // user -> { login: "..." }
        let userContainer = try c.nestedContainer(keyedBy: UserCodingKeys.self, forKey: .user)
        author = try userContainer.decode(String.self, forKey: .login)

        // repository_url: "https://api.github.com/repos/owner/repo"
        let repoURL = try c.decode(String.self, forKey: .repository_url)
        repositoryName = repoURL.components(separatedBy: "/repos/").last ?? repoURL
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id,             forKey: .id)
        try c.encode(number,         forKey: .number)
        try c.encode(title,          forKey: .title)
        try c.encode(htmlURL,        forKey: .htmlURL)
        try c.encode(createdAt,      forKey: .createdAt)
        try c.encode(["login": author], forKey: .user)
        try c.encode("https://api.github.com/repos/\(repositoryName)", forKey: .repository_url)
    }

    private enum UserCodingKeys: String, CodingKey { case login }

    // Manual memberwise init for CLI path
    init(id: Int, number: Int, title: String, htmlURL: String,
         repositoryName: String, createdAt: Date, author: String) {
        self.id = id; self.number = number; self.title = title
        self.htmlURL = htmlURL; self.repositoryName = repositoryName
        self.createdAt = createdAt; self.author = author
    }
}

struct GitHubSearchResponse: Decodable {
    let items: [PullRequest]
}

// MARK: - gh CLI response models
// `gh search prs` returns a different JSON shape
struct CLIPullRequest: Decodable {
    let number: Int
    let title: String
    let url: String
    let createdAt: Date
    let repository: CLIRepository
    let author: CLIAuthor

    func asPullRequest() -> PullRequest {
        // gh search doesn't provide a numeric id — use number+repo as hash
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
}
