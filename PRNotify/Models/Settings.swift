import Foundation

struct Settings {
    enum ReviewFilter: Int {
        case userReviewRequested = 0   // user-review-requested:<username>
        case reviewRequested     = 1   // review-requested:<username>
        case teamReviewRequested = 2   // team-review-requested:<org>/<team>
    }

    enum SortOrder: Int {
        case createdAsc  = 0  // oldest first (default for review queue)
        case createdDesc = 1  // newest first
    }

    enum Keys {
        static let githubToken         = "githubToken"
        static let githubUsername      = "githubUsername"
        static let maxPRsToShow        = "maxPRsToShow"
        static let maxRecentPRsToShow  = "maxRecentPRsToShow"
        static let reviewFilter        = "reviewFilter"
        static let teamSlug            = "teamSlug"
        static let pollIntervalSeconds = "pollIntervalSeconds"
        static let reviewQueueSort     = "reviewQueueSort"
        static let authoredPRsSort     = "authoredPRsSort"
        static let reviewSLADays       = "reviewSLADays"
    }

    var githubToken: String?
    var githubUsername: String
    var maxPRsToShow: Int
    var maxRecentPRsToShow: Int
    var reviewFilter: ReviewFilter
    var teamSlug: String
    var pollIntervalSeconds: Int
    var reviewQueueSort: SortOrder
    var authoredPRsSort: SortOrder
    var reviewSLADays: Int

    static func load() -> Settings {
        let d = UserDefaults.standard
        let filterRaw = d.object(forKey: Keys.reviewFilter) == nil
            ? ReviewFilter.userReviewRequested
            : (ReviewFilter(rawValue: d.integer(forKey: Keys.reviewFilter)) ?? .userReviewRequested)
        return Settings(
            githubToken:          d.string(forKey: Keys.githubToken),
            githubUsername:       d.string(forKey: Keys.githubUsername) ?? "",
            maxPRsToShow:         d.integer(forKey: Keys.maxPRsToShow).nonZeroOr(20),
            maxRecentPRsToShow:   d.integer(forKey: Keys.maxRecentPRsToShow).nonZeroOr(10),
            reviewFilter:         filterRaw,
            teamSlug:             d.string(forKey: Keys.teamSlug) ?? "",
            pollIntervalSeconds:  d.integer(forKey: Keys.pollIntervalSeconds).nonZeroOr(120),
            reviewQueueSort:      SortOrder(rawValue: d.integer(forKey: Keys.reviewQueueSort)) ?? .createdAsc,
            authoredPRsSort:      SortOrder(rawValue: d.integer(forKey: Keys.authoredPRsSort)) ?? .createdDesc,
            reviewSLADays:        d.integer(forKey: Keys.reviewSLADays).nonZeroOr(2)
        )
    }

    func save() {
        let d = UserDefaults.standard
        if let token = githubToken, !token.isEmpty {
            d.set(token, forKey: Keys.githubToken)
        } else {
            d.removeObject(forKey: Keys.githubToken)
        }
        d.set(githubUsername,        forKey: Keys.githubUsername)
        d.set(maxPRsToShow,          forKey: Keys.maxPRsToShow)
        d.set(maxRecentPRsToShow,    forKey: Keys.maxRecentPRsToShow)
        d.set(reviewFilter.rawValue,    forKey: Keys.reviewFilter)
        d.set(teamSlug,                 forKey: Keys.teamSlug)
        d.set(pollIntervalSeconds,      forKey: Keys.pollIntervalSeconds)
        d.set(reviewQueueSort.rawValue, forKey: Keys.reviewQueueSort)
        d.set(authoredPRsSort.rawValue, forKey: Keys.authoredPRsSort)
        d.set(reviewSLADays,            forKey: Keys.reviewSLADays)
    }

    var reviewFilterClause: String {
        switch reviewFilter {
        case .userReviewRequested: return "user-review-requested:\(githubUsername)"
        case .reviewRequested:     return "review-requested:\(githubUsername)"
        case .teamReviewRequested: return "team-review-requested:\(teamSlug)"
        }
    }

    var searchQuery: String {
        "is:open is:pr \(reviewFilterClause) archived:false draft:false"
    }

    var webURL: URL? {
        let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://github.com/pulls?q=\(encoded)")
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
