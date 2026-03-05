import Foundation

func runPullRequestTests() {
    suite("PullRequest") {

        // Encode → Decode round-trip
        let roundTripCases: [(Int, Int, String, String)] = [
            (1,  101, "Fix crash",       "owner/repo"),
            (2,  202, "Add dark mode",   "org/mobile"),
            (99, 999, "Unicode 🚀 title","a/b"),
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        for (id, number, title, repo) in roundTripCases {
            let pr = makePR(id: id, number: number, title: title, repo: repo)
            if let data = try? encoder.encode(pr),
               let decoded = try? decoder.decode(PullRequest.self, from: data) {
                check("round-trip id \(id) — id",    decoded.id == pr.id)
                check("round-trip id \(id) — number",decoded.number == pr.number)
                check("round-trip id \(id) — title", decoded.title == pr.title)
                check("round-trip id \(id) — repo",  decoded.repositoryName == pr.repositoryName)
                check("round-trip id \(id) — author",decoded.author == pr.author)
            } else {
                check("round-trip id \(id) encode/decode succeeded", false)
            }
        }

        // Sorting
        let now = Date()
        let prs = [
            makePR(id: 1, createdAt: now.addingTimeInterval(-200)),
            makePR(id: 2, createdAt: now.addingTimeInterval(-100)),
            makePR(id: 3, createdAt: now),
        ]
        let sortCases: [(Settings.SortOrder, [Int])] = [
            (.createdAsc,  [1, 2, 3]),
            (.createdDesc, [3, 2, 1]),
        ]
        for (order, expectedIDs) in sortCases {
            let sorted = prs.sorted(by: order).map { $0.id }
            check("sort \(order) order", sorted == expectedIDs)
        }

        // PRStatus computed properties
        // isReadyToMerge = mergeableState == "clean" only
        // hasIssues = CI failing OR changesRequested OR mergeableState == "dirty"
        let statusCases: [(PRStatus.CIStatus, PRStatus.ReviewDecision, String, Bool, Bool)] = [
            (.passing, .approved,         "clean",   true,  false),
            (.failing, .approved,         "clean",   true,  true),
            (.passing, .changesRequested, "clean",   true,  true),
            (.passing, .approved,         "dirty",   false, true),
            (.pending, .reviewRequired,   "blocked", false, false),
        ]
        for (ci, review, mergeable, expectedReady, expectedIssues) in statusCases {
            let status = PRStatus(ciStatus: ci, reviewDecision: review, mergeableState: mergeable)
            check("isReadyToMerge ci=\(ci) review=\(review) merge=\(mergeable)",
                  status.isReadyToMerge == expectedReady)
            check("hasIssues ci=\(ci) review=\(review) merge=\(mergeable)",
                  status.hasIssues == expectedIssues)
        }
    }
}

func makePR(id: Int, number: Int = 1, title: String = "Test PR",
            repo: String = "owner/repo", createdAt: Date = Date(),
            author: String = "dev") -> PullRequest {
    PullRequest(id: id, number: number, title: title,
                htmlURL: "https://github.com/\(repo)/pull/\(number)",
                repositoryName: repo, createdAt: createdAt, author: author)
}
