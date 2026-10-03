import Foundation
import SwiftData

/// Run with scripts/test-coach-apply.sh; no simulator is needed.
///
/// What accepting a proposal does to the plan and to `decisions.json`: edits in
/// place under the same IDs, a slot added and one removed, undo right after as
/// a mis-tap that leaves nothing behind, revert later that stays on the record,
/// and ratings that are never filed under the wrong person.
@main
struct CoachApplyTests {
    typealias F = CoachFixture
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static let t0 = Date(timeIntervalSince1970: 1_790_000_000)
    static let proposalID = "6F1C0000-0000-0000-0000-000000000001"

    /// A phone with the fixture plan, a temporary folder to stand in for
    /// Documents/Coach, and an inbox on a clock the checks can move.
    @MainActor final class Rig {
        let container: ModelContainer
        let context: ModelContext
        let store = F.temporaryStore()
        var now = CoachApplyTests.t0
        private(set) var inbox: CoachInbox!

        init() throws {
            container = try F.makeContainer()
            context = container.mainContext
            try F.insertPlan(context)
            inbox = CoachInbox(context: context, store: store, now: { [unowned self] in self.now })
        }

        /// What `coach push` does, then what opening the app does.
        func push(_ changes: [[String: Any]], id: String = CoachApplyTests.proposalID) throws {
            store.prepare()
            try F.proposalJSON(id: id, changes: changes).write(to: store.proposalURL)
            inbox.reload()
        }

        /// A new launch: the same files and plan, none of the memory of what
        /// was just done on screen.
        func relaunch() {
            inbox = CoachInbox(context: context, store: store, now: { [unowned self] in self.now })
        }

        func items(_ day: String) throws -> [PlanItem] { try F.items(of: day, context) }
        func item(_ id: String) throws -> PlanItem? { try F.item(id, context) }

        var decisionsText: String { (try? String(contentsOf: store.decisionsURL, encoding: .utf8)) ?? "" }
    }

    static func sets(_ id: String, item: String, from: Int, to: Int, day: String = F.dayA) -> [String: Any] {
        F.change(id, "setSets", day: day, item: item, expect: ["targetSets": from], to: ["targetSets": to])
    }

    static func applied(_ result: Result<CoachDecision, CoachApplier.Refusal>) -> CoachDecision? {
        if case .success(let decision) = result { return decision }
        return nil
    }

    // MARK: In place

    @MainActor static func checkInPlace() throws {
        let rig = try Rig()
        let idsBefore = Set(try rig.context.fetch(FetchDescriptor<PlanItem>()).map(\.id))
        let daysBefore = Set(try rig.context.fetch(FetchDescriptor<PlanDay>()).map(\.id))
        try rig.push([
            sets("c1", item: F.bench, from: 4, to: 5),
            F.change("c2", "setRepRange", day: F.dayA, item: F.curl, expect: ["targetRepsLow": 8, "targetRepsHigh": 12],
                     to: ["targetRepsLow": 6, "targetRepsHigh": 10]),
            F.change("c3", "setRest", day: F.dayA, item: F.fly, expect: ["restSeconds": 60], to: ["restSeconds": 90]),
        ])
        check(rig.inbox.showsOnToday, "a pending proposal with applicable changes shows on Today")
        check(rig.inbox.rows.count == 3 && rig.inbox.proposal?.id == proposalID, "the proposal and its rows are readable")

        let decision = applied(rig.inbox.apply(accepted: ["c1", "c2", "c3"], notes: ["c2": "  knees  ", "c3": " "]))
        check(decision != nil, "accepting all three applies")
        check(try rig.item(F.bench)?.targetSets == 5, "setSets applied")
        let curl = try rig.item(F.curl)
        check(curl?.targetRepsLow == 6 && curl?.targetRepsHigh == 10, "setRepRange applied")
        check(try rig.item(F.fly)?.restSeconds == 90, "setRest applied")
        let idsAfter = Set(try rig.context.fetch(FetchDescriptor<PlanItem>()).map(\.id))
        let daysAfter = Set(try rig.context.fetch(FetchDescriptor<PlanDay>()).map(\.id))
        check(idsAfter == idsBefore && daysAfter == daysBefore, "edits are in place: every day and slot keeps its ID")
        check(!rig.inbox.showsOnToday, "a decided proposal leaves Today")

        let recorded = rig.store.loadDecisions().decisions
        check(recorded.count == 1 && recorded[0].proposalID == proposalID && recorded[0].appliedAt == t0
              && recorded[0].decidedAt == t0, "the decision is recorded with when it was applied")
        check(recorded[0].changes.map(\.decision) == [.accepted, .accepted, .accepted]
              && recorded[0].changes[1].note == "knees" && recorded[0].changes[2].note == nil,
              "each change is recorded, notes trimmed and blank ones left out")
        check(recorded[0].before?.count == 3 && recorded[0].after?.count == 3, "the before and after of each slot are kept")
        check(recorded[0].before?.first?.item?.targetSets == 4 && recorded[0].after?.first?.item?.targetSets == 5,
              "before holds the old values and after the new")
        check(!rig.decisionsText.contains("revertedAt") && !rig.decisionsText.contains("ratings")
              && !rig.decisionsText.contains("null"), "nothing is written for what has not happened")
        check(applied(rig.inbox.apply(accepted: ["c1"])) == nil, "a proposal can be decided only once")

        // substitute carries sets, reps and rest, and sets no load.
        let swap = try Rig()
        try swap.item(F.bench)?.targetWeightKg = 60
        try swap.context.save()
        try swap.push([F.change("c1", "substitute", day: F.dayA, item: F.bench, expect: ["catalogID": "barbell-bench-press"],
                                to: ["catalogID": "dumbbell-bench-press", "name": "Dumbbell Bench Press"])])
        check(applied(swap.inbox.apply(accepted: ["c1"])) != nil, "substitute applies")
        let item = try swap.item(F.bench)
        check(item?.id == F.uuid(0x301) && item?.catalogID == "dumbbell-bench-press" && item?.name == "Dumbbell Bench Press",
              "substitute keeps the slot and changes its exercise")
        check(item?.targetSets == 4 && item?.targetRepsLow == 8 && item?.targetRepsHigh == 12 && item?.order == 0,
              "sets, reps and place carry over")
        check(item?.targetWeightKg == 0, "the old lift's load is not carried to the new one")
        check(swap.inbox.revert() == nil, "substitute reverts")
        let back = try swap.item(F.bench)
        check(back?.catalogID == "barbell-bench-press" && back?.name == "Barbell Bench Press" && back?.targetWeightKg == 60,
              "revert brings back the exercise, its name and its load")
    }

    // MARK: Add and remove

    @MainActor static func checkAddSlot() throws {
        let rig = try Rig()
        let lift: [String: Any] = ["catalogID": "dumbbell-lateral-raise", "name": "Dumbbell Lateral Raise", "targetSets": 3,
                                   "targetRepsLow": 10, "targetRepsHigh": 15, "restSeconds": 60, "afterItemID": F.bench]
        try rig.push([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: lift)])
        check(applied(rig.inbox.apply(accepted: ["c1"])) != nil, "addSlot applies")

        let items = try rig.items(F.dayA)
        check(items.map(\.catalogID) == ["barbell-bench-press", "dumbbell-lateral-raise", "dumbbell-fly", "dumbbell-curl"]
              && items.map(\.order) == [0, 1, 2, 3], "the new slot goes after the one named and the rest move down")
        let made = items[1]
        check(!Set(["301", "302", "303"].map { F.uuid(Int($0, radix: 16)!) }).contains(made.id), "the new slot has a new ID")
        check(made.targetSets == 3 && made.targetRepsLow == 10 && made.targetRepsHigh == 15 && made.restSeconds == 60
              && made.targetWeightKg == 0, "the new slot holds what was asked and no load")
        check(made.day?.id == F.uuid(0x200), "the new slot is in its day")
        let record = rig.store.loadDecisions().decisions[0]
        check(record.before?.count == 3 && record.before?.contains { $0.itemID == made.id.uuidString && $0.item == nil } == true,
              "the record keeps a no-item entry for the slot it made, and the two it moved")

        // Undo right after: the plan and the record both go back.
        check(rig.inbox.canUndoLastDecision, "the apply just made can be undone")
        check(rig.inbox.undoLastDecision() == nil, "undo succeeds")
        let restored = try rig.items(F.dayA)
        check(restored.map(\.catalogID) == ["barbell-bench-press", "dumbbell-fly", "dumbbell-curl"]
              && restored.map(\.order) == [0, 1, 2], "undo removes the slot and closes up the orders")
        check(restored.map(\.id) == [F.uuid(0x301), F.uuid(0x302), F.uuid(0x303)], "the other slots keep their IDs")
        check(rig.store.loadDecisions().decisions.isEmpty && !rig.decisionsText.contains(proposalID),
              "undo erases the decision record entirely")
        check(rig.inbox.showsOnToday && rig.inbox.decisionOnProposal == nil && !rig.inbox.canUndoLastDecision,
              "after an undo the proposal is pending again, as if never decided")
        check(rig.inbox.undoLastDecision() != nil, "a second undo has nothing to undo")

        // At the end of the day: nothing else moves.
        var atEnd = lift
        atEnd["afterItemID"] = nil
        try rig.push([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: atEnd)], id: "6F1C0000-0000-0000-0000-000000000002")
        check(applied(rig.inbox.apply(accepted: ["c1"])) != nil, "addSlot with no afterItemID applies")
        check(try rig.items(F.dayA).map(\.catalogID).last == "dumbbell-lateral-raise"
              && rig.store.loadDecisions().decisions[0].before?.count == 1, "it goes to the end and moves nothing")

        // Two added in one apply, after the same slot, undo together.
        let twice = try Rig()
        var second = lift
        second["catalogID"] = "dumbbell-fly"
        second["name"] = "Dumbbell Fly"
        try twice.push([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: lift),
                        F.change("c2", "addSlot", day: F.dayA, expect: [:], to: second)])
        check(applied(twice.inbox.apply(accepted: ["c1", "c2"])) != nil, "two added slots apply")
        check(try twice.items(F.dayA).count == 5 && Set(try twice.items(F.dayA).map(\.order)).count == 5,
              "both are in, each in a place of its own")
        check(twice.inbox.undoLastDecision() == nil, "both undo")
        check(try twice.items(F.dayA).map(\.order) == [0, 1, 2], "and the day is as it was")
    }

    @MainActor static func checkRemoveSlot() throws {
        let rig = try Rig()
        try rig.push([F.change("c1", "removeSlot", day: F.dayA, item: F.fly, expect: ["catalogID": "dumbbell-fly"], to: [:])])
        check(applied(rig.inbox.apply(accepted: ["c1"])) != nil, "removeSlot applies")
        let left = try rig.items(F.dayA)
        check(left.map(\.catalogID) == ["barbell-bench-press", "dumbbell-curl"] && left.map(\.order) == [0, 1],
              "the slot is gone and the orders close up")
        check(try rig.item(F.fly) == nil, "the removed slot is not in the store")

        check(rig.inbox.undoLastDecision() == nil, "undo of a removal succeeds")
        let back = try rig.items(F.dayA)
        check(back.map(\.id) == [F.uuid(0x301), F.uuid(0x302), F.uuid(0x303)] && back.map(\.order) == [0, 1, 2],
              "the removed slot returns under its own ID and place")
        let fly = back[1]
        check(fly.catalogID == "dumbbell-fly" && fly.targetSets == 3 && fly.targetRepsLow == 10 && fly.targetRepsHigh == 15
              && fly.restSeconds == 60 && fly.day?.id == F.uuid(0x200), "with the values it had")
        check(back[2].targetWeightKg == 12.5, "and the slot after it keeps its load")
        check(rig.store.loadDecisions().decisions.isEmpty, "the record is gone")

        // Two removals that are each fine alone would empty the day together.
        let both = try Rig()
        try both.push([
            F.change("c1", "removeSlot", day: F.dayB, item: F.row, expect: ["catalogID": "barbell-row"], to: [:]),
            F.change("c2", "removeSlot", day: F.dayB, item: F.plank, expect: ["catalogID": "plank-bodyweight"], to: [:]),
        ])
        check(both.inbox.rows.allSatisfy { $0.status.isApplicable }, "each removal is fine on its own")
        let decision = applied(both.inbox.apply(accepted: ["c1", "c2"]))
        check(decision?.changes.map(\.decision) == [.accepted, .stale], "the second is stale once the first has gone")
        check(try both.items(F.dayB).map(\.catalogID) == ["plank-bodyweight"], "the day keeps one slot")
    }

    // MARK: Revert

    @MainActor static func checkRevert() throws {
        let rig = try Rig()
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        check(applied(rig.inbox.apply(accepted: ["c1"])) != nil, "applies")

        rig.relaunch()
        check(!rig.inbox.canUndoLastDecision && rig.inbox.undoLastDecision() != nil,
              "an apply from an earlier launch is history, not a mis-tap, and cannot be undone")
        check(rig.inbox.revertibleDecision?.proposalID == proposalID, "it can still be reverted")
        rig.now = t0.addingTimeInterval(86_400 * 9)
        check(rig.inbox.revert() == nil, "revert succeeds")
        check(try rig.item(F.bench)?.targetSets == 4, "revert puts the plan back")
        let record = rig.store.loadDecisions().decisions
        check(record.count == 1 && record[0].revertedAt == rig.now && record[0].appliedAt == t0,
              "revert stamps revertedAt and keeps the record")
        check(rig.inbox.revertibleDecision == nil && rig.inbox.revert() != nil, "a revert is done once")
        check(!rig.inbox.showsOnToday, "a reverted proposal does not come back to Today")

        // The lifter changed it since: refuse, say so, touch nothing.
        let edited = try Rig()
        try edited.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = edited.inbox.apply(accepted: ["c1"])
        edited.relaunch()
        try edited.item(F.bench)?.targetSets = 6
        try edited.context.save()
        let refusal = edited.inbox.revert()
        check(refusal?.reason.contains("Barbell Bench Press") == true, "revert after a later edit is refused, naming the lift")
        check(try edited.item(F.bench)?.targetSets == 6, "and the lifter's edit is left alone")
        check(edited.store.loadDecisions().decisions[0].revertedAt == nil, "and nothing is stamped")

        // A load is the phone's, so changing it is no reason to refuse, or to undo it.
        let loaded = try Rig()
        try loaded.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = loaded.inbox.apply(accepted: ["c1"])
        loaded.relaunch()
        try loaded.item(F.bench)?.targetWeightKg = 80
        try loaded.context.save()
        check(loaded.inbox.revert() == nil, "an edit to a field the apply never touched does not block the revert")
        let kept = try loaded.item(F.bench)
        check(kept?.targetSets == 4 && kept?.targetWeightKg == 80, "and survives it")

        // Added, then edited by the lifter.
        let added = try Rig()
        let lift: [String: Any] = ["catalogID": "dumbbell-lateral-raise", "name": "Dumbbell Lateral Raise", "targetSets": 3,
                                   "targetRepsLow": 10, "targetRepsHigh": 15, "restSeconds": 60]
        try added.push([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: lift)])
        _ = added.inbox.apply(accepted: ["c1"])
        added.relaunch()
        try added.items(F.dayA).last?.targetSets = 5
        try added.context.save()
        let refused = added.inbox.revert() != nil
        let slots = try added.items(F.dayA).count
        check(refused && slots == 4, "an added slot the lifter has edited is kept")

        // Removed, then another slot added: the returning slot and the new one share a place.
        let gap = try Rig()
        try gap.push([F.change("c1", "removeSlot", day: F.dayA, item: F.fly, expect: ["catalogID": "dumbbell-fly"], to: [:])])
        _ = gap.inbox.apply(accepted: ["c1"])
        gap.relaunch()
        let extra = PlanItem(catalogID: "barbell-row", name: "Bent Over Barbell Row", order: 2)
        extra.day = try gap.context.fetch(FetchDescriptor<PlanDay>()).first { $0.id == F.uuid(0x200) }
        gap.context.insert(extra)
        try gap.context.save()
        check(gap.inbox.revert() == nil, "a removal reverts after something else was added")
        let order = try gap.items(F.dayA)
        check(order.map(\.order) == [0, 1, 2, 3] && order.map(\.catalogID)
              == ["barbell-bench-press", "dumbbell-fly", "dumbbell-curl", "barbell-row"],
              "and every slot has a place of its own, the returning one where it was")
    }

    // MARK: Deciding

    @MainActor static func checkDeciding() throws {
        // Decline everything.
        let rig = try Rig()
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5), sets("c2", item: F.fly, from: 3, to: 4)])
        let decision = applied(rig.inbox.apply(accepted: []))
        check(decision?.changes.map(\.decision) == [.declined, .declined] && decision?.appliedAt == nil,
              "declining everything records two declines and no apply")
        check(try rig.item(F.bench)?.targetSets == 4, "and changes nothing")
        check(!rig.decisionsText.contains("appliedAt") && !rig.decisionsText.contains("before")
              && !rig.decisionsText.contains("after"), "a decline leaves no apply keys in the record")
        check(!rig.inbox.showsOnToday && rig.inbox.revertibleDecision == nil,
              "a decline takes the proposal off Today and has nothing to revert")
        check(rig.inbox.canUndoLastDecision, "but a mis-tapped decline can be undone on the spot")
        check(rig.inbox.ratableDecision?.proposalID == proposalID, "and it can be rated")
        rig.relaunch()
        check(!rig.inbox.showsOnToday && !rig.inbox.canUndoLastDecision,
              "it stays off Today after a relaunch, and can no longer be undone")

        // Undo a decline of everything: the proposal comes back, the record goes.
        let misTap = try Rig()
        try misTap.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = applied(misTap.inbox.apply(accepted: []))
        check(misTap.inbox.undoLastDecision() == nil, "undoing a decline succeeds")
        check(misTap.inbox.showsOnToday && misTap.inbox.decisionOnProposal == nil
              && misTap.store.loadDecisions().decisions.isEmpty && !misTap.decisionsText.contains(proposalID),
              "after undoing a decline the proposal is pending again and no record of the decline is left")
        check(try misTap.item(F.bench)?.targetSets == 4, "and the plan never moved")

        // Accept one, decline one.
        let mixed = try Rig()
        try mixed.push([sets("c1", item: F.bench, from: 4, to: 5), sets("c2", item: F.fly, from: 3, to: 4)])
        let result = applied(mixed.inbox.apply(accepted: ["c2"], notes: ["c1": "not now"]))
        check(result?.changes.map(\.decision) == [.declined, .accepted] && result?.changes[0].note == "not now",
              "one accepted and one declined, with its note")
        check(try mixed.item(F.bench)?.targetSets == 4 && mixed.item(F.fly)?.targetSets == 4, "only the accepted one is applied")

        // A stale change is recorded as stale whatever was ticked, and cannot be applied.
        let stale = try Rig()
        try stale.push([sets("c1", item: F.bench, from: 4, to: 5), sets("c2", item: F.fly, from: 2, to: 3)])
        check(stale.inbox.rows.map(\.status.isApplicable) == [true, false], "the second change is stale on arrival")
        let outcome = applied(stale.inbox.apply(accepted: ["c1", "c2"]))
        let flySets = try stale.item(F.fly)?.targetSets
        check(outcome?.changes.map(\.decision) == [.accepted, .stale] && flySets == 3,
              "ticking a stale change does not apply it")

        // Everything accepted went stale between the screen and the tap.
        let moved = try Rig()
        try moved.push([sets("c1", item: F.bench, from: 4, to: 5)])
        try moved.item(F.bench)?.targetSets = 3
        try moved.context.save()
        check(moved.inbox.apply(accepted: ["c1"]).isFailure, "accepting only changes that went stale is refused")
        check(moved.store.loadDecisions().decisions.isEmpty && !moved.inbox.showsOnToday,
              "and nothing is recorded; the stale proposal is simply not offered")

        // States with nothing to show.
        let empty = try Rig()
        check(!empty.inbox.showsOnToday && empty.inbox.proposal == nil && empty.inbox.unreadableReason == nil,
              "an empty inbox shows nothing")
        check(empty.inbox.apply(accepted: ["c1"]).isFailure, "and has nothing to decide")
        try Data("{ \"format\": ".utf8).write(to: empty.store.proposalURL)
        empty.inbox.reload()
        check(!empty.inbox.showsOnToday && empty.inbox.unreadableReason != nil, "an unreadable proposal is reported, not shown")
        try empty.push([sets("c1", item: F.bench, from: 1, to: 2)])
        check(!empty.inbox.showsOnToday, "a proposal with nothing applicable is not shown")
    }

    // MARK: Ratings

    @MainActor static func checkRatings() throws {
        let rig = try Rig()
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        let early = rig.inbox.addRating(score: 4, rater: .user)
        check(early != nil && rig.store.loadDecisions().decisions.isEmpty,
              "a proposal can be rated before it is decided, and that decides nothing")
        rig.inbox.removeRating(early!)
        _ = rig.inbox.apply(accepted: ["c1"])

        check(rig.inbox.addRating(score: 0, rater: .user) == nil && rig.inbox.addRating(score: 6, rater: .user) == nil,
              "a score outside 1 to 5 is refused")
        check(!rig.decisionsText.contains("ratings"), "no rating, no ratings key")
        let mine = rig.inbox.addRating(score: 4, rater: .user, raterName: "Ignored", note: "  good  ")
        check(mine?.rater == .user && mine?.raterName == nil && mine?.note == "good",
              "the user's rating carries no name, whatever was passed")
        let theirs = rig.inbox.addRating(score: 3, rater: .other, raterName: " Sam ")
        let nameless = rig.inbox.addRating(score: 2, rater: .other, raterName: "  ")
        check(theirs?.rater == .other && theirs?.raterName == "Sam" && nameless?.raterName == nil,
              "someone else's rating keeps their name when given")
        let ratings = rig.store.loadDecisions().decisions[0].ratings
        check(ratings?.map(\.rater) == [.user, .other, .other] && ratings?.map(\.score) == [4, 3, 2],
              "all three are filed, each under its own rater")
        check(ratings?.filter { $0.rater == .user }.count == 1, "only one is filed as the user's")
        check(rig.decisionsText.contains("\"rater\" : \"self\"") && rig.decisionsText.contains("\"rater\" : \"other\""),
              "raters are written as self and other")
        check(rig.decisionsText.components(separatedBy: "raterName").count == 2, "only the named rating has a raterName key")

        rig.inbox.removeRating(theirs!)
        rig.inbox.removeRating(nameless!)
        rig.inbox.removeRating(mine!)
        check(rig.store.loadDecisions().decisions[0].ratings == nil && !rig.decisionsText.contains("ratings"),
              "a rating taken back leaves no trace, not even an empty list")

        // Still ratable after a revert: having trained on it is the point.
        rig.relaunch()
        _ = rig.inbox.revert()
        check(rig.inbox.addRating(score: 2, rater: .user, note: "knees hurt") != nil, "a reverted change can still be rated")
    }

    // MARK: Ratings before and without a decision

    static let secondProposalID = "6F1C0000-0000-0000-0000-000000000002"

    @MainActor static func pendingFileExists(_ rig: Rig) -> Bool {
        FileManager.default.fileExists(atPath: rig.store.pendingRatingsURL.path)
    }

    @MainActor static func pendingText(_ rig: Rig) -> String {
        (try? String(contentsOf: rig.store.pendingRatingsURL, encoding: .utf8)) ?? ""
    }

    @MainActor static func checkDeclinedRatings() throws {
        let rig = try Rig()
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = rig.inbox.apply(accepted: [])
        let rating = rig.inbox.addRating(score: 1, rater: .user, note: "useless")
        check(rating != nil && rig.store.loadDecisions().decisions[0].ratings?.map(\.score) == [1],
              "a review declined entirely can be rated, in its decision record")
        check(!pendingFileExists(rig), "a decided proposal has no pending file")
        rig.relaunch()
        let theirs = rig.inbox.addRating(score: 2, rater: .other, raterName: "Sam")
        check(theirs?.rater == .other && rig.inbox.ratings().count == 2, "and again after a relaunch, by someone else")
        rig.inbox.removeRating(rating!)
        rig.inbox.removeRating(theirs!)
        check(rig.store.loadDecisions().decisions[0].ratings == nil && !rig.decisionsText.contains("ratings"),
              "taking them back leaves no ratings key")
    }

    @MainActor static func checkPendingRatings() throws {
        let rig = try Rig()
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5), sets("c2", item: F.fly, from: 3, to: 4)])
        let mine = rig.inbox.addRating(score: 4, rater: .user, raterName: "Ignored")
        let theirs = rig.inbox.addRating(score: 2, rater: .other, raterName: " Sam ", note: "too much volume")
        check(mine != nil && theirs != nil && rig.inbox.showsOnToday && rig.store.loadDecisions().decisions.isEmpty,
              "rating before deciding leaves the proposal undecided and writes no decision")
        let file = rig.store.loadPendingRatings()
        check(file?.proposalID == proposalID && file?.format == "gymtrack-coach-ratings" && file?.version == 1
              && file?.ratings.map(\.rater) == [.user, .other], "the ratings wait in ratings.json under the proposal id")
        let text = pendingText(rig)
        check(text.contains("\"rater\" : \"self\"") && text.contains("\"rater\" : \"other\"")
              && text.components(separatedBy: "raterName").count == 2 && !text.contains("null"),
              "raters are written as self and other, and an absent name is an absent key")
        check(file?.ratings.last?.raterName == "Sam", "someone else's rating keeps rater other and their name")
        rig.relaunch()
        check(rig.inbox.ratings().count == 2 && rig.inbox.showsOnToday, "pending ratings survive a relaunch")

        // Taking back the last one leaves no file and no empty list.
        let solo = try Rig()
        try solo.push([sets("c1", item: F.bench, from: 4, to: 5)])
        let lone = solo.inbox.addRating(score: 3, rater: .user)
        solo.inbox.removeRating(lone!)
        check(!pendingFileExists(solo), "a pending rating taken back leaves no file")

        // Deciding moves them into the record and removes the file.
        let decision = applied(rig.inbox.apply(accepted: ["c1"]))
        check(decision?.ratings?.map(\.score) == [4, 2] && decision?.ratings?.map(\.rater) == [.user, .other],
              "applying carries the pending ratings into the decision, raters intact")
        check(rig.store.loadDecisions().decisions[0].ratings?.count == 2 && !pendingFileExists(rig)
              && rig.inbox.pendingRatings.isEmpty, "they are in decisions.json and the pending file is gone")

        // Undo takes the decision back and leaves the ratings waiting.
        let late = rig.inbox.addRating(score: 5, rater: .other, raterName: "Dana")
        check(late != nil && rig.store.loadDecisions().decisions[0].ratings?.count == 3,
              "a rating after the decision goes to the decision")
        check(rig.inbox.undoLastDecision() == nil, "undo succeeds")
        check(rig.store.loadDecisions().decisions.isEmpty && rig.inbox.decisionOnProposal == nil,
              "undo erases the decision record")
        let back = rig.store.loadPendingRatings()
        check(back?.proposalID == proposalID && back?.ratings.map(\.score) == [4, 2, 5]
              && back?.ratings.map(\.rater) == [.user, .other, .other],
              "but the ratings people gave go back to the pending file, raters intact")
        check(rig.inbox.ratings().count == 3 && rig.inbox.showsOnToday, "and the proposal is pending with its ratings")

        // An undo with nothing rated leaves no file behind.
        let bare = try Rig()
        try bare.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = bare.inbox.apply(accepted: ["c1"])
        _ = bare.inbox.undoLastDecision()
        check(!pendingFileExists(bare), "undo of an unrated apply writes no pending file")

        // Deciding all over again moves them once more, this time as a decline.
        let again = applied(rig.inbox.apply(accepted: []))
        check(again?.appliedAt == nil && again?.ratings?.count == 3 && !pendingFileExists(rig),
              "declining everything also moves the pending ratings into the record")
        check(rig.store.loadDecisions().decisions[0].ratings?.map(\.rater) == [.user, .other, .other],
              "with every rater as it was given")
    }

    @MainActor static func checkReplacedProposal() throws {
        let rig = try Rig()
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = rig.inbox.addRating(score: 2, rater: .user)
        try rig.push([sets("c1", item: F.fly, from: 3, to: 4)], id: secondProposalID)
        check(!pendingFileExists(rig) && rig.inbox.ratings().isEmpty,
              "a proposal that replaces the inbox file drops the old one's pending ratings")
        let fresh = rig.inbox.addRating(score: 5, rater: .other, raterName: "Sam")
        check(fresh != nil && rig.store.loadPendingRatings()?.proposalID == secondProposalID,
              "and ratings for the new one are filed under its own id")

        // A pending file for a proposal that is already decided is a leftover.
        let decided = applied(rig.inbox.apply(accepted: ["c1"]))
        check(decided?.ratings?.count == 1, "the new proposal's rating moves into its decision")
        try rig.store.savePendingRatings(CoachPendingRatings(proposalID: secondProposalID, ratings: decided?.ratings ?? []))
        rig.inbox.reload()
        check(!pendingFileExists(rig) && rig.store.loadDecisions().decisions[0].ratings?.count == 1,
              "a leftover for a decided proposal is deleted, not applied a second time")

        // A proposal that fits nothing is never decided, so it takes no ratings.
        let empty = try Rig()
        try empty.push([sets("c1", item: F.bench, from: 1, to: 2)])
        check(!empty.inbox.canRate() && empty.inbox.addRating(score: 3, rater: .user) == nil && !pendingFileExists(empty),
              "a proposal with nothing applicable cannot be rated")
    }

    @MainActor static func checkRatingSubjects() throws {
        // The history rates the record even while a newer proposal waits.
        let rig = try Rig()
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = rig.inbox.apply(accepted: ["c1"])
        try rig.push([sets("c1", item: F.fly, from: 3, to: 4)], id: secondProposalID)
        check(rig.inbox.ratableDecision?.proposalID == proposalID, "the latest decision is the ratable one while another waits")
        let old = rig.inbox.addRating(score: 4, rater: .user, on: .decision)
        let new = rig.inbox.addRating(score: 2, rater: .other, raterName: "Sam")
        check(old != nil && new != nil && rig.store.loadDecisions().decisions[0].ratings?.map(\.score) == [4]
              && rig.store.loadPendingRatings()?.proposalID == secondProposalID
              && rig.store.loadPendingRatings()?.ratings.map(\.score) == [2],
              "a rating on the record and one on the waiting proposal each go where they were aimed")
        check(rig.inbox.ratings(on: .decision).map(\.score) == [4] && rig.inbox.ratings().map(\.score) == [2],
              "and each is read back from there")
        rig.inbox.removeRating(old!)
        rig.inbox.removeRating(new!)
        check(rig.store.loadDecisions().decisions[0].ratings == nil && !pendingFileExists(rig),
              "each is taken back from the file it was in")
    }

    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        do {
            try await MainActor.run {
                try checkInPlace(); try checkAddSlot(); try checkRemoveSlot()
                try checkRevert(); try checkDeciding(); try checkRatings()
                try checkDeclinedRatings(); try checkPendingRatings()
                try checkReplacedProposal(); try checkRatingSubjects()
            }
        } catch {
            print("FAIL: threw \(error)")
            exit(1)
        }
        let failed = await MainActor.run { failures }
        if failed > 0 { exit(1) }
        print("Coach apply checks passed")
    }
}

extension Result {
    var isFailure: Bool { if case .failure = self { true } else { false } }
}
