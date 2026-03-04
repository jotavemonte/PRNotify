import Foundation

enum GitHubError: Error {
    case noCredentials
    case network(Error)
    case decoding(Error)
    case cli(String)
    case usernameUnresolved
}

final class GitHubService {

    // MARK: - Public

    func fetchReviewRequested(
        settings: Settings,
        completion: @escaping (Result<([PullRequest], [Int: PRStatus]), GitHubError>) -> Void
    ) {
        if let token = resolvedToken() {
            fetchViaGraphQL(query: settings.searchQuery, token: token,
                            maxCount: settings.maxPRsToShow, sort: settings.reviewQueueSort,
                            includeActivity: false) { result in
                switch result {
                case .failure(let e): completion(.failure(e))
                case .success(let (prs, statuses, _, _)): completion(.success((prs, statuses)))
                }
            }
        } else {
            fetchViaCLI(query: settings.searchQuery,
                        maxCount: settings.maxPRsToShow, sort: settings.reviewQueueSort,
                        completion: completion)
        }
    }

    // Fetches open PRs authored by the user, including activity + latest comment data in one GraphQL call
    func fetchAuthoredPRs(
        username: String, sort: Settings.SortOrder,
        completion: @escaping (Result<([PullRequest], [Int: PRStatus], [Int: PRActivity], [Int: PRComment]), GitHubError>) -> Void
    ) {
        let query = "is:open is:pr author:\(username) archived:false"
        if let token = resolvedToken() {
            fetchViaGraphQL(query: query, token: token, maxCount: 100, sort: sort, includeActivity: true) { result in
                switch result {
                case .failure(let e): completion(.failure(e))
                case .success(let (prs, statuses, activities, latestComments)):
                    completion(.success((prs, statuses, activities, latestComments)))
                }
            }
        } else {
            fetchViaCLI(query: query, maxCount: 100, sort: sort) { result in
                switch result {
                case .failure(let e): completion(.failure(e))
                case .success(let (prs, statuses)): completion(.success((prs, statuses, [:], [:])))
                }
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
        if let token = resolvedToken() {
            fetchUsernameViaAPI(token: token, completion: completion)
        } else {
            fetchUsernameViaCLI(completion: completion)
        }
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
            completion(.failure(.cli("Failed to serialize GraphQL request")))
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
                    completion(.failure(.cli(msg)))
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

    // MARK: - gh CLI

    private let ghPaths = ["/usr/local/bin/gh", "/opt/homebrew/bin/gh"]

    private var ghExecutable: String? {
        ghPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func fetchViaCLI(
        query: String, maxCount: Int, sort: Settings.SortOrder,
        completion: @escaping (Result<([PullRequest], [Int: PRStatus]), GitHubError>) -> Void
    ) {
        runCLI([
            "search", "prs",
            "--search", query,
            "--json", "number,title,url,createdAt,repository,author,reviewDecision,statusCheckRollup,mergeStateStatus",
            "--limit", "\(maxCount)",
            "--order", sort == .createdAsc ? "asc" : "desc",
            "--sort", "created",
        ]) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let output):
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let items = try decoder.decode([CLIPullRequest].self, from: Data(output.utf8))
                    var statusMap: [Int: PRStatus] = [:]
                    let prs = items.map { item -> PullRequest in
                        let pr = item.asPullRequest()
                        statusMap[pr.id] = item.asPRStatus()
                        return pr
                    }
                    completion(.success((prs, statusMap)))
                } catch {
                    completion(.failure(.decoding(error)))
                }
            }
        }
    }

    private func fetchUsernameViaCLI(
        completion: @escaping (Result<String, GitHubError>) -> Void
    ) {
        runCLI(["api", "user", "--jq", ".login"]) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let raw):
                let login = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !login.isEmpty else { completion(.failure(.usernameUnresolved)); return }
                completion(.success(login))
            }
        }
    }

    private func runCLI(_ args: [String], completion: @escaping (Result<String, GitHubError>) -> Void) {
        guard let gh = ghExecutable else { completion(.failure(.noCredentials)); return }

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: gh)
            task.arguments = args
            let out = Pipe(), err = Pipe()
            task.standardOutput = out
            task.standardError  = err

            do {
                try task.run()
                task.waitUntilExit()
                let output = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                if task.terminationStatus == 0 {
                    completion(.success(output))
                } else {
                    let errMsg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    completion(.failure(.cli(errMsg.trimmingCharacters(in: .whitespacesAndNewlines))))
                }
            } catch {
                completion(.failure(.cli(error.localizedDescription)))
            }
        }
    }
}
