import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// What accepting a proposal does to the plan and to `decisions.json`: edits in
/// place under the same IDs, a slot added and one removed, undo right after as
/// a mis-tap that leaves nothing behind, revert later that stays on the record,
/// and the leftover file of the old plan-review ratings being cleared away.
///
/// Whether a change may be applied at all is in `CoachValidationTests`; the
/// files themselves are in `CoachModelTests`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CoachApplyTests {
    typealias F = CoachFixture

    private let t0 = TestClock.at("2026-09-21T14:13:20")

    // MARK: - In place

    @Test func acceptingThreeEditsChangesTheSlotsInPlaceAndRecordsWhatTheyWere() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        let idsBefore = Set(try rig.context.fetch(FetchDescriptor<PlanItem>()).map(\.id))
        let daysBefore = Set(try rig.context.fetch(FetchDescriptor<PlanDay>()).map(\.id))
        try rig.push([
            sets("c1", item: F.bench, from: 4, to: 5),
            F.change("c2", "setRepRange", day: F.dayA, item: F.curl, expect: ["targetRepsLow": 8, "targetRepsHigh": 12],
                     to: ["targetRepsLow": 6, "targetRepsHigh": 10]),
            F.change("c3", "setRest", day: F.dayA, item: F.fly, expect: ["restSeconds": 60], to: ["restSeconds": 90]),
        ])
        #expect(rig.inbox.showsOnToday, "A pending proposal with applicable changes shows on Today")
        #expect(rig.inbox.rows.count == 3 && rig.inbox.proposal?.id == F.proposalID)

        let decision = applied(rig.inbox.apply(accepted: ["c1", "c2", "c3"], notes: ["c2": "  knees  ", "c3": " "]))
        #expect(decision != nil, "Accepting all three applies")
        #expect(try rig.item(F.bench)?.targetSets == 5)
        let curl = try rig.item(F.curl)
        #expect(curl?.targetRepsLow == 6 && curl?.targetRepsHigh == 10)
        #expect(try rig.item(F.fly)?.restSeconds == 90)
        let idsAfter = Set(try rig.context.fetch(FetchDescriptor<PlanItem>()).map(\.id))
        let daysAfter = Set(try rig.context.fetch(FetchDescriptor<PlanDay>()).map(\.id))
        #expect(idsAfter == idsBefore && daysAfter == daysBefore, "Every day and slot keeps its ID")
        #expect(!rig.inbox.showsOnToday, "A decided proposal leaves Today")

        let recorded = rig.store.loadDecisions().decisions
        try #require(recorded.count == 1)
        #expect(recorded[0].proposalID == F.proposalID && recorded[0].appliedAt == t0 && recorded[0].decidedAt == t0)
        #expect(recorded[0].changes.map(\.decision) == [.accepted, .accepted, .accepted])
        #expect(recorded[0].changes[1].note == "knees" && recorded[0].changes[2].note == nil,
                "Notes are trimmed, and a blank one is left out")
        #expect(recorded[0].before?.count == 3 && recorded[0].after?.count == 3)
        #expect(recorded[0].before?.first?.item?.targetSets == 4 && recorded[0].after?.first?.item?.targetSets == 5,
                "Before holds the old values and after the new")
        #expect(!rig.decisionsText.contains("revertedAt") && !rig.decisionsText.contains("null"),
                "Nothing is written for what has not happened")
        #expect(applied(rig.inbox.apply(accepted: ["c1"])) == nil, "A proposal can be decided only once")
    }

    @Test func aSubstituteKeepsTheSlotAndItsShapeButNotTheOldLiftsLoad() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.item(F.bench)?.targetWeightKg = 60
        try rig.context.save()
        try rig.push([F.change("c1", "substitute", day: F.dayA, item: F.bench, expect: ["catalogID": "barbell-bench-press"],
                               to: ["catalogID": "dumbbell-bench-press", "name": "Dumbbell Bench Press"])])

        #expect(applied(rig.inbox.apply(accepted: ["c1"])) != nil)
        let item = try rig.item(F.bench)
        #expect(item?.id == F.uuid(0x301) && item?.catalogID == "dumbbell-bench-press" && item?.name == "Dumbbell Bench Press",
                "The slot stays and its exercise changes")
        #expect(item?.targetSets == 4 && item?.targetRepsLow == 8 && item?.targetRepsHigh == 12 && item?.order == 0,
                "Sets, reps and place carry over")
        #expect(item?.targetWeightKg == 0, "The old lift's load is not carried to the new one")

        #expect(rig.inbox.revert() == nil)
        let back = try rig.item(F.bench)
        #expect(back?.catalogID == "barbell-bench-press" && back?.name == "Barbell Bench Press" && back?.targetWeightKg == 60,
                "Revert brings back the exercise, its name and its load")
    }

    // MARK: - Add and remove

    @Test func anAddedSlotGoesAfterTheOneNamedAndUndoingItLeavesNoTrace() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: lift(after: F.bench))])
        #expect(applied(rig.inbox.apply(accepted: ["c1"])) != nil)

        let items = try rig.items(F.dayA)
        #expect(items.map(\.catalogID) == ["barbell-bench-press", "dumbbell-lateral-raise", "dumbbell-fly", "dumbbell-curl"])
        #expect(items.map(\.order) == [0, 1, 2, 3], "The rest move down")
        let made = try #require(items.count == 4 ? items[1] : nil)
        #expect(![F.uuid(0x301), F.uuid(0x302), F.uuid(0x303)].contains(made.id), "The new slot has a new ID")
        #expect(made.targetSets == 3 && made.targetRepsLow == 10 && made.targetRepsHigh == 15 && made.restSeconds == 60
                && made.targetWeightKg == 0, "The new slot holds what was asked and no load")
        #expect(made.day?.id == F.uuid(0x200))
        let record = try #require(rig.store.loadDecisions().decisions.first)
        #expect(record.before?.count == 3 && record.before?.contains { $0.itemID == made.id.uuidString && $0.item == nil } == true,
                "The record keeps a no-item entry for the slot it made, and the two it moved")

        #expect(rig.inbox.canUndoLastDecision, "The apply just made can be undone")
        #expect(rig.inbox.undoLastDecision() == nil)
        let restored = try rig.items(F.dayA)
        #expect(restored.map(\.catalogID) == ["barbell-bench-press", "dumbbell-fly", "dumbbell-curl"])
        #expect(restored.map(\.order) == [0, 1, 2], "Undo closes up the orders")
        #expect(restored.map(\.id) == [F.uuid(0x301), F.uuid(0x302), F.uuid(0x303)], "The other slots keep their IDs")
        #expect(rig.store.loadDecisions().decisions.isEmpty && !rig.decisionsText.contains(F.proposalID),
                "Undo erases the decision record entirely")
        #expect(rig.inbox.showsOnToday && rig.inbox.decisionOnProposal == nil && !rig.inbox.canUndoLastDecision,
                "After an undo the proposal is pending again, as if never decided")
        #expect(rig.inbox.undoLastDecision() != nil, "A second undo has nothing to undo")

        // With no slot named it goes to the end, and nothing else moves.
        try rig.push([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: lift())],
                     id: "6F1C0000-0000-0000-0000-000000000002")
        #expect(applied(rig.inbox.apply(accepted: ["c1"])) != nil)
        #expect(try rig.items(F.dayA).map(\.catalogID).last == "dumbbell-lateral-raise")
        #expect(rig.store.loadDecisions().decisions.first?.before?.count == 1)
    }

    @Test func twoSlotsAddedAfterTheSameOneEachTakeAPlaceAndUndoTogether() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        var second = lift(after: F.bench)
        second["catalogID"] = "dumbbell-fly"
        second["name"] = "Dumbbell Fly"
        try rig.push([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: lift(after: F.bench)),
                      F.change("c2", "addSlot", day: F.dayA, expect: [:], to: second)])

        #expect(applied(rig.inbox.apply(accepted: ["c1", "c2"])) != nil)
        let items = try rig.items(F.dayA)
        #expect(items.count == 5 && Set(items.map(\.order)).count == 5, "Both are in, each in a place of its own")
        #expect(rig.inbox.undoLastDecision() == nil)
        #expect(try rig.items(F.dayA).map(\.order) == [0, 1, 2], "And the day is as it was")
    }

    @Test func aRemovedSlotClosesUpTheDayAndUndoBringsItBackUnderItsOwnID() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([F.change("c1", "removeSlot", day: F.dayA, item: F.fly, expect: ["catalogID": "dumbbell-fly"], to: [:])])

        #expect(applied(rig.inbox.apply(accepted: ["c1"])) != nil)
        let left = try rig.items(F.dayA)
        #expect(left.map(\.catalogID) == ["barbell-bench-press", "dumbbell-curl"] && left.map(\.order) == [0, 1])
        #expect(try rig.item(F.fly) == nil, "The removed slot is not in the store")

        #expect(rig.inbox.undoLastDecision() == nil)
        let back = try rig.items(F.dayA)
        #expect(back.map(\.id) == [F.uuid(0x301), F.uuid(0x302), F.uuid(0x303)] && back.map(\.order) == [0, 1, 2],
                "The removed slot returns under its own ID and place")
        let fly = try #require(back.count == 3 ? back[1] : nil)
        #expect(fly.catalogID == "dumbbell-fly" && fly.targetSets == 3 && fly.targetRepsLow == 10 && fly.targetRepsHigh == 15
                && fly.restSeconds == 60 && fly.day?.id == F.uuid(0x200), "With the values it had")
        #expect(back[2].targetWeightKg == 12.5, "And the slot after it keeps its load")
        #expect(rig.store.loadDecisions().decisions.isEmpty, "The record is gone")
    }

    @Test func twoRemovalsThatWouldEmptyADayLeaveTheSecondStale() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([
            F.change("c1", "removeSlot", day: F.dayB, item: F.row, expect: ["catalogID": "barbell-row"], to: [:]),
            F.change("c2", "removeSlot", day: F.dayB, item: F.plank, expect: ["catalogID": "plank-bodyweight"], to: [:]),
        ])
        #expect(rig.inbox.rows.allSatisfy { $0.status.isApplicable }, "Each removal is fine on its own")

        let decision = applied(rig.inbox.apply(accepted: ["c1", "c2"]))
        #expect(decision?.changes.map(\.decision) == [.accepted, .stale], "The second is stale once the first has gone")
        #expect(try rig.items(F.dayB).map(\.catalogID) == ["plank-bodyweight"], "The day keeps one slot")
    }

    // MARK: - Revert

    @Test func anApplyFromAnEarlierLaunchRevertsOnceAndStaysOnTheRecord() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        #expect(applied(rig.inbox.apply(accepted: ["c1"])) != nil)

        rig.relaunch()
        #expect(!rig.inbox.canUndoLastDecision && rig.inbox.undoLastDecision() != nil,
                "An apply from an earlier launch is history, not a mis-tap, and cannot be undone")
        #expect(rig.inbox.revertibleDecision?.proposalID == F.proposalID, "It can still be reverted")
        rig.now = t0.addingTimeInterval(86_400 * 9)
        #expect(rig.inbox.revert() == nil)
        #expect(try rig.item(F.bench)?.targetSets == 4, "Revert puts the plan back")
        let record = rig.store.loadDecisions().decisions
        #expect(record.count == 1 && record.first?.revertedAt == rig.now && record.first?.appliedAt == t0,
                "Revert stamps revertedAt and keeps the record")
        #expect(rig.inbox.revertibleDecision == nil && rig.inbox.revert() != nil, "A revert is done once")
        #expect(!rig.inbox.showsOnToday, "A reverted proposal does not come back to Today")
    }

    @Test func aRevertIsRefusedOnceTheLifterHasChangedWhatTheApplyWrote() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = rig.inbox.apply(accepted: ["c1"])
        rig.relaunch()
        try rig.item(F.bench)?.targetSets = 6
        try rig.context.save()

        let refusal = rig.inbox.revert()
        #expect(refusal?.reason.contains("Barbell Bench Press") == true, "The refusal names the lift")
        #expect(try rig.item(F.bench)?.targetSets == 6, "The lifter's edit is left alone")
        #expect(rig.store.loadDecisions().decisions.first?.revertedAt == nil, "Nothing is stamped")
    }

    @Test func aLoadChangedSinceTheApplyNeitherBlocksTheRevertNorIsUndoneByIt() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = rig.inbox.apply(accepted: ["c1"])
        rig.relaunch()
        // A load is the phone's, never the coach's.
        try rig.item(F.bench)?.targetWeightKg = 80
        try rig.context.save()

        #expect(rig.inbox.revert() == nil, "An edit to a field the apply never touched does not block the revert")
        let kept = try rig.item(F.bench)
        #expect(kept?.targetSets == 4 && kept?.targetWeightKg == 80, "And survives it")
    }

    @Test func anAddedSlotTheLifterHasEditedIsKeptByARevert() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: lift())])
        _ = rig.inbox.apply(accepted: ["c1"])
        rig.relaunch()
        try rig.items(F.dayA).last?.targetSets = 5
        try rig.context.save()

        #expect(rig.inbox.revert() != nil)
        #expect(try rig.items(F.dayA).count == 4)
    }

    @Test func aRemovalRevertsIntoAPlaceOfItsOwnAfterAnotherSlotWasAdded() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([F.change("c1", "removeSlot", day: F.dayA, item: F.fly, expect: ["catalogID": "dumbbell-fly"], to: [:])])
        _ = rig.inbox.apply(accepted: ["c1"])
        rig.relaunch()
        // The returning slot and this one would otherwise share order 2.
        let extra = PlanItem(catalogID: "barbell-row", name: "Bent Over Barbell Row", order: 2)
        extra.day = try F.day(F.dayA, rig.context)
        rig.context.insert(extra)
        try rig.context.save()

        #expect(rig.inbox.revert() == nil)
        let order = try rig.items(F.dayA)
        #expect(order.map(\.order) == [0, 1, 2, 3])
        #expect(order.map(\.catalogID) == ["barbell-bench-press", "dumbbell-fly", "dumbbell-curl", "barbell-row"],
                "The returning slot is where it was")
    }

    // MARK: - Deciding

    @Test func decliningEverythingChangesNothingAndCanBeUndoneOnlyInThatLaunch() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5), sets("c2", item: F.fly, from: 3, to: 4)])

        let decision = applied(rig.inbox.apply(accepted: []))
        #expect(decision?.changes.map(\.decision) == [.declined, .declined] && decision?.appliedAt == nil,
                "Declining everything records two declines and no apply")
        #expect(try rig.item(F.bench)?.targetSets == 4, "And changes nothing")
        #expect(!rig.decisionsText.contains("appliedAt") && !rig.decisionsText.contains("before")
                && !rig.decisionsText.contains("after"), "A decline leaves no apply keys in the record")
        #expect(!rig.inbox.showsOnToday && rig.inbox.revertibleDecision == nil,
                "A decline takes the proposal off Today and has nothing to revert")
        #expect(rig.inbox.canUndoLastDecision, "A mis-tapped decline can be undone on the spot")
        rig.relaunch()
        #expect(!rig.inbox.showsOnToday && !rig.inbox.canUndoLastDecision,
                "It stays off Today after a relaunch, and can no longer be undone")
    }

    @Test func undoingADeclineLeavesTheProposalPendingAndNoRecordOfIt() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        _ = applied(rig.inbox.apply(accepted: []))

        #expect(rig.inbox.undoLastDecision() == nil)
        #expect(rig.inbox.showsOnToday && rig.inbox.decisionOnProposal == nil)
        #expect(rig.store.loadDecisions().decisions.isEmpty && !rig.decisionsText.contains(F.proposalID),
                "No record of the decline is left")
        #expect(try rig.item(F.bench)?.targetSets == 4, "The plan never moved")
    }

    @Test func acceptingOneAndDecliningTheOtherAppliesOnlyTheOneAccepted() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5), sets("c2", item: F.fly, from: 3, to: 4)])

        let result = applied(rig.inbox.apply(accepted: ["c2"], notes: ["c1": "not now"]))
        #expect(result?.changes.map(\.decision) == [.declined, .accepted] && result?.changes.first?.note == "not now",
                "The decline keeps its note")
        #expect(try rig.item(F.bench)?.targetSets == 4 && rig.item(F.fly)?.targetSets == 4)
    }

    @Test func aStaleChangeIsRecordedAsStaleWhateverWasTicked() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5), sets("c2", item: F.fly, from: 2, to: 3)])
        #expect(rig.inbox.rows.map(\.status.isApplicable) == [true, false], "The second change is stale on arrival")

        let outcome = applied(rig.inbox.apply(accepted: ["c1", "c2"]))
        #expect(outcome?.changes.map(\.decision) == [.accepted, .stale])
        #expect(try rig.item(F.fly)?.targetSets == 3, "Ticking a stale change does not apply it")
    }

    @Test func acceptingOnlyChangesThatWentStaleIsRefusedAndRecordsNothing() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        // Between the screen and the tap.
        try rig.item(F.bench)?.targetSets = 3
        try rig.context.save()

        #expect(refused(rig.inbox.apply(accepted: ["c1"])))
        #expect(rig.store.loadDecisions().decisions.isEmpty && !rig.inbox.showsOnToday,
                "Nothing is recorded; the stale proposal is simply not offered")
    }

    @Test func anEmptyUnreadableOrInapplicableInboxShowsNothing() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        #expect(!rig.inbox.showsOnToday && rig.inbox.proposal == nil && rig.inbox.unreadableReason == nil,
                "An empty inbox shows nothing")
        #expect(refused(rig.inbox.apply(accepted: ["c1"])), "And has nothing to decide")

        try Data("{ \"format\": ".utf8).write(to: rig.store.proposalURL)
        rig.inbox.reload()
        #expect(!rig.inbox.showsOnToday && rig.inbox.unreadableReason != nil, "An unreadable proposal is reported, not shown")

        try rig.push([sets("c1", item: F.bench, from: 1, to: 2)])
        #expect(!rig.inbox.showsOnToday, "A proposal with nothing applicable is not shown")
    }

    // MARK: - Leftover ratings file

    @Test func theOldRatingsFileIsDeletedByAPushAndALaunchButTheProposalStays() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = try Rig(now: t0)
        defer { rig.close() }
        // An earlier build kept ratings given before a decision here. Nothing
        // reads it now, and a file nothing reads would still be pulled to the
        // Mac as if it were current.
        let leftover = rig.store.inboxURL.appendingPathComponent("ratings.json")
        try Data("{ \"format\": \"gymtrack-coach-ratings\" }".utf8).write(to: leftover)

        try rig.push([sets("c1", item: F.bench, from: 4, to: 5)])
        #expect(!FileManager.default.fileExists(atPath: leftover.path), "A push prepares the store, which deletes it")
        try Data("{}".utf8).write(to: leftover)
        rig.relaunch()
        #expect(!FileManager.default.fileExists(atPath: leftover.path) && rig.inbox.showsOnToday,
                "A launch deletes it too, and the waiting proposal is untouched")
        #expect(FileManager.default.fileExists(atPath: rig.store.proposalURL.path), "Only that file goes")
    }

    // MARK: - Helpers

    /// A phone with the fixture plan, a temporary folder standing in for
    /// `Documents/Coach`, and an inbox on a clock the test can move.
    @MainActor
    final class Rig {
        let context: ModelContext
        let store = F.temporaryStore()
        var now: Date
        private(set) var inbox: CoachInbox!

        init(now: Date) throws {
            self.now = now
            context = try TestStore.context()
            try F.insertPlan(context)
            relaunch()
        }

        /// What `coach push` does, then what opening the app does.
        func push(_ changes: [[String: Any]], id: String = F.proposalID) throws {
            store.prepare()
            try F.proposalJSON(id: id, changes: changes).write(to: store.proposalURL)
            inbox.reload()
        }

        /// A new launch: the same files and plan, none of the memory of what
        /// was just done on screen.
        func relaunch() {
            inbox = CoachInbox(context: context, store: store, now: { [unowned self] in self.now })
        }

        func close() { F.discard(store) }

        func items(_ day: String) throws -> [PlanItem] { try F.items(of: day, context) }
        func item(_ id: String) throws -> PlanItem? { try F.item(id, context) }

        var decisionsText: String { (try? String(contentsOf: store.decisionsURL, encoding: .utf8)) ?? "" }
    }

    private func sets(_ id: String, item: String, from: Int, to: Int) -> [String: Any] {
        F.change(id, "setSets", day: F.dayA, item: item, expect: ["targetSets": from], to: ["targetSets": to])
    }

    /// The lateral raise the add checks ask for, after `slot` or at the end.
    private func lift(after slot: String? = nil) -> [String: Any] {
        var lift: [String: Any] = ["catalogID": "dumbbell-lateral-raise", "name": "Dumbbell Lateral Raise", "targetSets": 3,
                                   "targetRepsLow": 10, "targetRepsHigh": 15, "restSeconds": 60]
        if let slot { lift["afterItemID"] = slot }
        return lift
    }

    private func applied(_ result: Result<CoachDecision, CoachApplier.Refusal>) -> CoachDecision? {
        if case .success(let decision) = result { return decision }
        return nil
    }

    private func refused(_ result: Result<CoachDecision, CoachApplier.Refusal>) -> Bool {
        applied(result) == nil
    }
}
