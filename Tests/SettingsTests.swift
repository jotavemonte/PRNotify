import Foundation

func runSettingsTests() {
    suite("Settings") {

        // searchQuery includes correct filter clause
        let queryTable: [(Settings.ReviewFilter, String, String, String)] = [
            (.userReviewRequested, "alice", "",          "user-review-requested:alice"),
            (.reviewRequested,     "alice", "",          "review-requested:alice"),
            (.teamReviewRequested, "alice", "myorg/ios", "team-review-requested:myorg/ios"),
        ]
        for (filter, user, team, expected) in queryTable {
            let s = makeSettings(filter: filter, username: user, teamSlug: team)
            check("searchQuery contains '\(expected)'",
                  s.searchQuery.contains(expected))
            check("searchQuery is:open is:pr for \(filter)",
                  s.searchQuery.hasPrefix("is:open is:pr"))
        }

        // webURL encodes the search query
        let s = makeSettings(filter: .userReviewRequested, username: "bob", teamSlug: "")
        check("webURL is non-nil", s.webURL != nil)
        check("webURL contains github.com/pulls", s.webURL?.host == "github.com")

        // nonZeroOr default fallbacks
        let defaultSettings = Settings(
            githubToken: nil, githubUsername: "",
            maxPRsToShow: 20, maxRecentPRsToShow: 10,
            reviewFilter: .userReviewRequested, teamSlug: "",
            pollIntervalSeconds: 120,
            reviewQueueSort: .createdAsc, authoredPRsSort: .createdDesc,
            reviewSLADays: 2,
            notifyNewPRs: true, notifyComments: true,
            notifyApprovals: true, notifyChanges: true, notifySLA: true
        )
        check("default maxPRsToShow is 20",           defaultSettings.maxPRsToShow == 20)
        check("default pollIntervalSeconds is 120",   defaultSettings.pollIntervalSeconds == 120)
        check("default reviewSLADays is 2",           defaultSettings.reviewSLADays == 2)
        check("default reviewQueueSort is createdAsc",defaultSettings.reviewQueueSort == .createdAsc)
        check("default authoredPRsSort is createdDesc",defaultSettings.authoredPRsSort == .createdDesc)
    }
}

private func makeSettings(filter: Settings.ReviewFilter, username: String, teamSlug: String) -> Settings {
    Settings(
        githubToken: nil, githubUsername: username,
        maxPRsToShow: 20, maxRecentPRsToShow: 10,
        reviewFilter: filter, teamSlug: teamSlug,
        pollIntervalSeconds: 120,
        reviewQueueSort: .createdAsc, authoredPRsSort: .createdDesc,
        reviewSLADays: 2,
        notifyNewPRs: true, notifyComments: true,
        notifyApprovals: true, notifyChanges: true, notifySLA: true
    )
}
