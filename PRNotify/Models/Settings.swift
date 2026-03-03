import Foundation

struct Settings {
    enum Keys {
        static let githubToken            = "githubToken"
        static let githubUsername         = "githubUsername"
        static let maxPRsToShow           = "maxPRsToShow"
        static let maxRecentPRsToShow     = "maxRecentPRsToShow"
        static let useUserReviewRequested = "useUserReviewRequested"
        static let pollIntervalSeconds    = "pollIntervalSeconds"
    }

    var githubToken: String?
    var githubUsername: String
    var maxPRsToShow: Int
    var maxRecentPRsToShow: Int
    var useUserReviewRequested: Bool
    var pollIntervalSeconds: Int

    static func load() -> Settings {
        let d = UserDefaults.standard
        return Settings(
            githubToken:            d.string(forKey: Keys.githubToken),
            githubUsername:         d.string(forKey: Keys.githubUsername) ?? "",
            maxPRsToShow:           d.integer(forKey: Keys.maxPRsToShow).nonZeroOr(20),
            maxRecentPRsToShow:     d.integer(forKey: Keys.maxRecentPRsToShow).nonZeroOr(10),
            useUserReviewRequested: d.object(forKey: Keys.useUserReviewRequested) == nil
                                    ? true
                                    : d.bool(forKey: Keys.useUserReviewRequested),
            pollIntervalSeconds:    d.integer(forKey: Keys.pollIntervalSeconds).nonZeroOr(120)
        )
    }

    func save() {
        let d = UserDefaults.standard
        if let token = githubToken, !token.isEmpty {
            d.set(token, forKey: Keys.githubToken)
        } else {
            d.removeObject(forKey: Keys.githubToken)
        }
        d.set(githubUsername,         forKey: Keys.githubUsername)
        d.set(maxPRsToShow,           forKey: Keys.maxPRsToShow)
        d.set(maxRecentPRsToShow,     forKey: Keys.maxRecentPRsToShow)
        d.set(useUserReviewRequested, forKey: Keys.useUserReviewRequested)
        d.set(pollIntervalSeconds,    forKey: Keys.pollIntervalSeconds)
    }

    var reviewFilter: String {
        let kind = useUserReviewRequested ? "user-review-requested" : "review-requested"
        return "\(kind):\(githubUsername)"
    }

    var searchQuery: String {
        "is:open is:pr \(reviewFilter) archived:false draft:false"
    }

    var webURL: URL? {
        let encoded = searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://github.com/pulls?q=\(encoded)")
    }
}

private extension Int {
    func nonZeroOr(_ fallback: Int) -> Int { self == 0 ? fallback : self }
}
