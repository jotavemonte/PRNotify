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
        completion: @escaping (Result<[PullRequest], GitHubError>) -> Void
    ) {
        if let token = resolvedToken() {
            fetchViaAPI(query: settings.searchQuery, token: token,
                        maxCount: settings.maxPRsToShow, completion: completion)
        } else {
            fetchViaCLI(query: settings.searchQuery,
                        maxCount: settings.maxPRsToShow, completion: completion)
        }
    }

    // Fetches open PRs authored by the user
    func fetchAuthoredPRs(
        username: String,
        completion: @escaping (Result<[PullRequest], GitHubError>) -> Void
    ) {
        let query = "is:open is:pr author:\(username) archived:false"
        if let token = resolvedToken() {
            fetchViaAPI(query: query, token: token, maxCount: 100, completion: completion)
        } else {
            fetchViaCLI(query: query, maxCount: 100, completion: completion)
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

    // MARK: - REST API

    private func fetchViaAPI(
        query: String, token: String, maxCount: Int,
        completion: @escaping (Result<[PullRequest], GitHubError>) -> Void
    ) {
        var comps = URLComponents(string: "https://api.github.com/search/issues")!
        comps.queryItems = [
            URLQueryItem(name: "q",        value: query),
            URLQueryItem(name: "sort",     value: "created"),
            URLQueryItem(name: "order",    value: "asc"),
            URLQueryItem(name: "per_page", value: "\(min(maxCount, 100))"),
            URLQueryItem(name: "page",     value: "1"),
        ]

        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)",              forHTTPHeaderField: "Authorization")
        req.setValue("application/vnd.github+json",  forHTTPHeaderField: "Accept")
        req.setValue("2022-11-28",                   forHTTPHeaderField: "X-GitHub-Api-Version")
        req.timeoutInterval = 15

        URLSession.shared.dataTask(with: req) { data, _, error in
            if let error = error { completion(.failure(.network(error))); return }
            guard let data = data else { completion(.failure(.network(URLError(.badServerResponse)))); return }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let resp = try decoder.decode(GitHubSearchResponse.self, from: data)
                completion(.success(Array(resp.items.prefix(maxCount))))
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
        query: String, maxCount: Int,
        completion: @escaping (Result<[PullRequest], GitHubError>) -> Void
    ) {
        runCLI([
            "search", "prs",
            "--search", query,
            "--json", "number,title,url,createdAt,repository,author",
            "--limit", "\(maxCount)",
            "--order", "asc",
            "--sort", "created",
        ]) { result in
            switch result {
            case .failure(let e): completion(.failure(e))
            case .success(let output):
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let items = try decoder.decode([CLIPullRequest].self, from: Data(output.utf8))
                    completion(.success(items.map { $0.asPullRequest() }))
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
