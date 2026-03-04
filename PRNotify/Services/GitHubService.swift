import Foundation

enum GitHubError: Error {
    case noCredentials
    case network(Error)
    case decoding(Error)
    case graphQL(String)
    case usernameUnresolved
}

final class GitHubService {

    // MARK: - Public

    func fetchReviewRequested(
        settings: Settings,
        completion: @escaping (Result<([PullRequest], [Int: PRStatus]), GitHubError>) -> Void
    ) {
        guard let token = resolvedToken() else { completion(.failure(.noCredentials)); return }
        fetchViaGraphQL(query: settings.searchQuery, token: token,
                        maxCount: settings.maxPRsToShow, sort: settings.reviewQueueSort,
                        includeActivity: false) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let (prs, statuses, _, _)): completion(.success((prs, statuses)))
            }
        }
    }

    // Fetches open PRs authored by the user, including activity + latest comment data in one GraphQL call
    func fetchAuthoredPRs(
        username: String, sort: Settings.SortOrder,
        completion: @escaping (Result<([PullRequest], [Int: PRStatus], [Int: PRActivity], [Int: PRComment]), GitHubError>) -> Void
    ) {
        guard let token = resolvedToken() else { completion(.failure(.noCredentials)); return }
        let query = "is:open is:pr author:\(username) archived:false"
        fetchViaGraphQL(query: query, token: token, maxCount: 100, sort: sort, includeActivity: true) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let (prs, statuses, activities, latestComments)):
                completion(.success((prs, statuses, activities, latestComments)))
            }
        }
    }

    struct PRActivity {
        let commentCount: Int
        let approvalLogins: [String]
        let changesLogins: [String]
    }

    struct PRComment {
        let authorLogin: String
        let body: String
    }

    func resolveUsername(completion: @escaping (Result<String, GitHubError>) -> Void) {
        guard let token = resolvedToken() else { completion(.failure(.noCredentials)); return }
        fetchUsernameViaAPI(token: token, completion: completion)
    }

    // MARK: - Token

    private func resolvedToken() -> String? {
        if let saved = UserDefaults.standard.string(forKey: Settings.Keys.githubToken) {
            let trimmed = saved.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return ProcessInfo.processInfo.environment["GITHUB_TOKEN"]
    }

    // MARK: - GraphQL

    private struct GraphQLSearchResponse: Decodable {
        let data: GraphQLData?
        let errors: [GraphQLError]?

        struct GraphQLData: Decodable {
            let search: GraphQLSearch
        }
        struct GraphQLSearch: Decodable {
            let nodes: [GraphQLPR]
        }
        struct GraphQLError: Decodable {
            let message: String
        }
    }

    private struct GraphQLPR: Decodable {
        let number: Int?
        let title: String?
        let url: String?
        let createdAt: String?
        let author: GraphQLAuthor?
        let repository: GraphQLRepository?
        let reviewDecision: String?
        let mergeStateStatus: String?
        let statusCheckRollup: GraphQLStatusRollup?
        // Activity fields (only present when includeActivity: true)
        let reviews: GraphQLReviewConnection?
        let comments: GraphQLCommentConnection?
        let reviewThreads: GraphQLReviewThreadConnection?

        struct GraphQLAuthor: Decodable { let login: String? }
        struct GraphQLRepository: Decodable { let nameWithOwner: String? }
        struct GraphQLStatusRollup: Decodable {
            let contexts: GraphQLStatusContexts?
            struct GraphQLStatusContexts: Decodable {
                let nodes: [GraphQLStatusNode]?
                struct GraphQLStatusNode: Decodable { let state: String? }
            }
        }
        struct GraphQLReviewConnection: Decodable {
            let nodes: [GraphQLReview]?
            struct GraphQLReview: Decodable {
                let state: String?
                let author: GraphQLAuthor?
                let bodyText: String?
                let submittedAt: String?
            }
        }
        struct GraphQLCommentConnection: Decodable {
            let totalCount: Int?
            let nodes: [GraphQLComment]?
            struct GraphQLComment: Decodable {
                let author: GraphQLAuthor?
                let body: String?
                let updatedAt: String?
            }
        }
        struct GraphQLReviewThreadConnection: Decodable {
            let totalCount: Int?
        }

        func asPullRequest() -> PullRequest? {
            guard let number, let title, let url, let createdAt,
                  let login = author?.login,
                  let repo = repository?.nameWithOwner else { return nil }

            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let date = isoFormatter.date(from: createdAt) ?? ISO8601DateFormatter().date(from: createdAt) ?? Date()

            let stableID = abs("\(repo)#\(number)".hashValue)
            return PullRequest(
                id: stableID,
                number: number,
                title: title,
                htmlURL: url,
                repositoryName: repo,
                createdAt: date,
                author: login
            )
        }

        func asPRStatus() -> PRStatus {
            let ci: PRStatus.CIStatus
            let nodes = statusCheckRollup?.contexts?.nodes ?? []
            if nodes.isEmpty {
                ci = .unknown
            } else {
                let states = nodes.compactMap { $0.state?.uppercased() }
                if states.contains(where: { $0 == "FAILURE" || $0 == "ERROR" }) {
                    ci = .failing
                } else if states.contains(where: { $0 == "PENDING" || $0 == "EXPECTED" }) {
                    ci = .pending
                } else {
                    ci = .passing
                }
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

        func asActivity() -> PRActivity? {
            guard reviews != nil || comments != nil else { return nil }
            // Deduplicate reviews: latest state per reviewer
            var latestByUser: [String: String] = [:]
            for review in reviews?.nodes ?? [] {
                if let login = review.author?.login, let state = review.state {
                    latestByUser[login] = state
                }
            }
            let approvals = latestByUser.filter { $0.value == "APPROVED" }.map { $0.key }
            let changes   = latestByUser.filter { $0.value == "CHANGES_REQUESTED" }.map { $0.key }
            let commentCount = (comments?.totalCount ?? 0) + (reviewThreads?.totalCount ?? 0)
            return PRActivity(commentCount: commentCount, approvalLogins: approvals, changesLogins: changes)
        }

        func latestComment() -> PRComment? {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            var candidates: [(date: Date, login: String, body: String)] = []
            for c in comments?.nodes ?? [] {
                guard let login = c.author?.login, let body = c.body, !body.isEmpty,
                      let ds = c.updatedAt,
                      let date = iso.date(from: ds) ?? ISO8601DateFormatter().date(from: ds) else { continue }
                candidates.append((date, login, body))
            }
            for r in reviews?.nodes ?? [] {
                guard let login = r.author?.login, let body = r.bodyText, !body.isEmpty,
                      let ds = r.submittedAt,
                      let date = iso.date(from: ds) ?? ISO8601DateFormatter().date(from: ds) else { continue }
                candidates.append((date, login, body))
            }
            guard let best = candidates.max(by: { $0.date < $1.date }) else { return nil }
            return PRComment(authorLogin: best.login, body: best.body)
        }
    }

    private func fetchViaGraphQL(
        query: String, token: String, maxCount: Int, sort: Settings.SortOrder,
        includeActivity: Bool,
        completion: @escaping (Result<([PullRequest], [Int: PRStatus], [Int: PRActivity], [Int: PRComment]), GitHubError>) -> Void
    ) {
        let activityFields = includeActivity ? """
                reviews(last: 100) {
                  nodes { state author { login } bodyText submittedAt }
                }
                comments(last: 100) { totalCount
                  nodes { author { login } body updatedAt }
                }
                reviewThreads { totalCount }
        """ : ""

        let graphqlQuery = """
        query($searchQuery: String!, $limit: Int!) {
          search(query: $searchQuery, type: ISSUE, first: $limit) {
            nodes {
              ... on PullRequest {
                number
                title
                url
                createdAt
                author { login }
                repository { nameWithOwner }
                reviewDecision
                mergeStateStatus
                statusCheckRollup {
                  contexts(last: 20) {
                    nodes {
                      ... on CheckRun { state: conclusion }
                      ... on StatusContext { state }
                    }
                  }
                }
        \(activityFields)
              }
            }
          }
        }
        """

        let body: [String: Any] = [
            "query": graphqlQuery,
            "variables": ["searchQuery": query, "limit": min(maxCount, 100)]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else {
            completion(.failure(.graphQL("Failed to serialize GraphQL request")))
            return
        }

        var req = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = bodyData

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion(.failure(.network(error))); return }
            guard let data = data else { completion(.failure(.network(URLError(.badServerResponse)))); return }

            do {
                let decoder = JSONDecoder()
                let resp = try decoder.decode(GraphQLSearchResponse.self, from: data)

                if let errors = resp.errors, !errors.isEmpty {
                    let msg = errors.map { $0.message }.joined(separator: "; ")
                    NSLog("[PRNotify] GraphQL errors: %@", msg)
                    completion(.failure(.graphQL(msg)))
                    return
                }

                let nodes = resp.data?.search.nodes ?? []
                var prs: [PullRequest] = []
                var statusMap: [Int: PRStatus] = [:]
                var activityMap: [Int: PRActivity] = [:]
                var latestCommentMap: [Int: PRComment] = [:]
                for node in nodes {
                    guard let pr = node.asPullRequest() else { continue }
                    prs.append(pr)
                    statusMap[pr.id] = node.asPRStatus()
                    if let activity = node.asActivity() {
                        activityMap[pr.id] = activity
                    }
                    if let comment = node.latestComment() {
                        latestCommentMap[pr.id] = comment
                    }
                }

                prs = Array(prs.sorted(by: sort).prefix(maxCount))
                completion(.success((prs, statusMap, activityMap, latestCommentMap)))
            } catch {
                completion(.failure(.decoding(error)))
            }
        }.resume()
    }

    private func fetchUsernameViaAPI(
        token: String,
        completion: @escaping (Result<String, GitHubError>) -> Void
    ) {
        var req = URLRequest(url: URL(string: "https://api.github.com/user")!)
        req.setValue("Bearer \(token)",             forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion(.failure(.network(error))); return }
            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let login = json["login"] as? String
            else { completion(.failure(.usernameUnresolved)); return }
            completion(.success(login))
        }.resume()
    }

}
