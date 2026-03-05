import Foundation

func runStoreTests() {
    suite("RecentPRsStore") {
        let defaults = UserDefaults(suiteName: "PRNotifyTests")!
        let store = RecentPRsStore(defaults: defaults)

        // clear on empty is a no-op
        store.clear()
        check("load after clear returns empty", store.load().isEmpty)

        // record adds PRs newest-first
        let pr1 = makePR(id: 1)
        let pr2 = makePR(id: 2)
        store.record(pr1)
        store.record(pr2)
        let loaded = store.load()
        check("load returns 2 entries", loaded.count == 2)
        check("newest first: pr2 is first", loaded.first?.id == 2)

        // re-recording moves to front
        store.record(pr1)
        check("re-record moves pr1 to front", store.load().first?.id == 1)
        check("no duplicates after re-record", store.load().count == 2)

        // clear empties the store
        store.clear()
        check("load after clear is empty", store.load().isEmpty)

        // hard cap is respected
        for i in 0..<55 { store.record(makePR(id: i)) }
        check("hard cap at 50", store.load().count == 50)

        store.clear()
        defaults.removeSuite(named: "PRNotifyTests")
    }

    suite("PRActivityStore") {
        let suiteName = "PRNotifyActivityTests"
        UserDefaults().removePersistentDomain(forName: suiteName)
        let defaults = UserDefaults(suiteName: suiteName)!
        let store = PRActivityStore(defaults: defaults)

        // empty on first load
        check("load returns empty dict initially", store.load().isEmpty)

        // save and reload
        let saveCases: [(Int, Int, [String], [String])] = [
            (1, 3, ["alice"], []),
            (2, 0, [],        ["bob"]),
            (3, 5, ["alice"], ["carol"]),
        ]
        var snapshots: [Int: PRActivityStore.Snapshot] = [:]
        for (prID, comments, approvals, changes) in saveCases {
            snapshots[prID] = PRActivityStore.Snapshot(
                prID: prID, commentCount: comments,
                approvalLogins: approvals, changesLogins: changes)
        }
        store.save(snapshots)
        let reloaded = store.load()
        check("load count matches saved count", reloaded.count == saveCases.count)
        for (prID, comments, approvals, changes) in saveCases {
            let snap = reloaded[prID]
            check("pr \(prID) commentCount",    snap?.commentCount == comments)
            check("pr \(prID) approvalLogins",  snap?.approvalLogins == approvals)
            check("pr \(prID) changesLogins",   snap?.changesLogins == changes)
        }

        defaults.removeSuite(named: "PRNotifyActivityTests")
    }
}
