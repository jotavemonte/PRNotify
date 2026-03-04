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
                            completion: completion)
        } else {
            fetchViaCLI(query: settings.searchQuery,
                        maxCount: settings.maxPRsToShow, sort: settings.reviewQueueSort,
                        completion: completion)
        }
    }

    // Fetches open PRs authored by the user
    func fetchAuthoredPRs(
        username: String, sort: Settings.SortOrder,
        completion: @escaping (Result<([PullRequest], [Int: PRStatus]), GitHubError>) -> Void
    ) {
        let query = "is:open is:pr author:\(username) archived:false"
        if let token = resolvedToken() {
            fetchViaGraphQL(query: query, token: token, maxCount: 100, sort: sort, completion: completion)
        } else {
            fetchViaCLI(query: query, maxCount: 100, sort: sort, completion: completion)
        }
    }

    struct PRActivity {
        let commentCount: Int
        let approvalLogins: [String]
        let changesLogins: [String]
    }

    // Fetches current review + comment state for a single PR via REST API
    // Falls back to CLI. repoName = "owner/repo", number = PR number
    func fetchPRActivity(
        repoName: String, number: Int,
        completion: @escaping (Result<PRActivity, GitHubError>) -> Void
    ) {
        if let token = resolvedToken() {
            fetchActivityViaAPI(repoName: repoName, number: number, token: token, completion: completion)
        } else {
            fetchActivityViaCLI(repoName: repoName, number: number, completion: completion)
        }
    }

    private func fetchActivityViaAPI(
        repoName: String, number: Int, token: String,
        completion: @escaping (Result<PRActivity, GitHubError>) -> Void
    ) {
        let group = DispatchGroup()
        var reviews: [[String: Any]] = []
        var commentCount = 0
        var fetchError: GitHubError?

        // Fetch reviews
        group.enter()
        var reviewReq = URLRequest(url: URL(string: "https://api.github.com/repos/\(repoName)/pulls/\(number)/reviews")!)
        reviewReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        reviewReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        reviewReq.timeoutInterval = 10
        URLSession.shared.dataTask(with: reviewReq) { data, _, error in
            defer { group.leave() }
            if let error = error { fetchError = .network(error); return }
            if let data = data,
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                reviews = list
            }
        }.resume()

        // Fetch comment count via PR details
        group.enter()
        var prReq = URLRequest(url: URL(string: "https://api.github.com/repos/\(repoName)/pulls/\(number)")!)
        prReq.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        prReq.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        prReq.timeoutInterval = 10
        URLSession.shared.dataTask(with: prReq) { data, _, error in
            defer { group.leave() }
            if let error = error { fetchError = .network(error); return }
            if let data = data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // comments + review_comments combined
                let c1 = json["comments"] as? Int ?? 0
                let c2 = json["review_comments"] as? Int ?? 0
                commentCount = c1 + c2
            }
        }.resume()

        group.notify(queue: .global()) {
            if let err = fetchError { completion(.failure(err)); return }
            // Deduplicate by reviewer: take the latest review state per user
            var latestByUser: [String: String] = [:]
            for review in reviews {
                if let login = (review["user"] as? [String: Any])?["login"] as? String,
                   let state = review["state"] as? String {
                    latestByUser[login] = state
                }
            }
            let approvals = latestByUser.filter { $0.value == "APPROVED" }.map { $0.key }
            let changes   = latestByUser.filter { $0.value == "CHANGES_REQUESTED" }.map { $0.key }
            completion(.success(PRActivity(commentCount: commentCount, approvalLogins: approvals, changesLogins: changes)))
        }
    }

    private func fetchActivityViaCLI(
        repoName: String, number: Int,
        completion: @escaping (Result<PRActivity, GitHubError>) -> Void
    ) {
        let group = DispatchGroup()
        var reviews: [[String: Any]] = []
        var commentCount = 0
        var fetchError: GitHubError?

        group.enter()
        runCLI(["api", "repos/\(repoName)/pulls/\(number)/reviews"]) { result in
            defer { group.leave() }
            if case .success(let raw) = result,
               let data = raw.data(using: .utf8),
               let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                reviews = list
            } else if case .failure(let e) = result {
                fetchError = e
            }
        }

        group.enter()
        runCLI(["api", "repos/\(repoName)/pulls/\(number)"]) { result in
            defer { group.leave() }
            if case .success(let raw) = result,
               let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                commentCount = (json["comments"] as? Int ?? 0) + (json["review_comments"] as? Int ?? 0)
            } else if case .failure(let e) = result {
                fetchError = e
            }
        }

        group.notify(queue: .global()) {
            if let err = fetchError { completion(.failure(err)); return }
            var latestByUser: [String: String] = [:]
            for review in reviews {
                if let login = (review["user"] as? [String: Any])?["login"] as? String,
                   let state = review["state"] as? String {
                    latestByUser[login] = state
                }
            }
            let approvals = latestByUser.filter { $0.value == "APPROVED" }.map { $0.key }
            let changes   = latestByUser.filter { $0.value == "CHANGES_REQUESTED" }.map { $0.key }
            completion(.success(PRActivity(commentCount: commentCount, approvalLogins: approvals, changesLogins: changes)))
        }
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

        struct GraphQLAuthor: Decodable { let login: String? }
        struct GraphQLRepository: Decodable { let nameWithOwner: String? }
        struct GraphQLStatusRollup: Decodable {
            let contexts: GraphQLStatusContexts?
            struct GraphQLStatusContexts: Decodable {
                let nodes: [GraphQLStatusNode]?
                struct GraphQLStatusNode: Decodable { let state: String? }
            }
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
    }

    private func fetchViaGraphQL(
        query: String, token: String, maxCount: Int, sort: Settings.SortOrder,
        completion: @escaping (Result<([PullRequest], [Int: PRStatus]), GitHubError>) -> Void
    ) {
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
                for node in nodes {
                    guard let pr = node.asPullRequest() else { continue }
                    prs.append(pr)
                    statusMap[pr.id] = node.asPRStatus()
                }

                prs = Array(prs.sorted(by: sort).prefix(maxCount))
                completion(.success((prs, statusMap)))
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
