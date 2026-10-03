import Foundation
import SwiftData

/// Run with scripts/test-coach-validation.sh; no simulator is needed.
///
/// Every rule in the contract, checked against a live plan: each of the six
/// kinds with its limits, a stale `expect`, an unknown kind, too many changes,
/// and two changes on one slot.
@main
struct CoachValidationTests {
    typealias F = CoachFixture
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    enum Expected { case applicable, stale, invalid }

    @MainActor static func expect(_ expected: Expected, _ change: [String: Any], _ plans: [Plan], _ message: String,
                                  mentions: String? = nil) throws {
        let status = try F.status(change, plans: plans)
        let matches: Bool
        switch (expected, status) {
        case (.applicable, .applicable), (.stale, .stale), (.invalid, .invalid): matches = true
        default: matches = false
        }
        check(matches, "\(message) (got \(status))")
        if let mentions, let reason = status.reason {
            check(reason.localizedCaseInsensitiveContains(mentions), "\(message): the reason says \"\(mentions)\", got \"\(reason)\"")
        }
    }

    static let newLift: [String: Any] = [
        "catalogID": "dumbbell-lateral-raise", "name": "Dumbbell Lateral Raise",
        "targetSets": 3, "targetRepsLow": 10, "targetRepsHigh": 15, "restSeconds": 60,
    ]

    @MainActor static func checkKinds() throws {
        let container = try F.makeContainer()
        let context = container.mainContext
        try F.insertPlan(context)
        // A slot already at the top of the sets range, in a day of its own.
        let ten = PlanItem(catalogID: "barbell-bench-press", name: "Barbell Bench Press", order: 1, targetSets: 10)
        ten.id = F.uuid(0x310)
        ten.day = try context.fetch(FetchDescriptor<PlanDay>()).first { $0.id == F.uuid(0x203) }
        context.insert(ten)
        let one = PlanItem(catalogID: "barbell-row", name: "Bent Over Barbell Row", order: 2, targetSets: 1)
        one.id = F.uuid(0x311)
        one.day = ten.day
        context.insert(one)
        try context.save()
        let plans = try context.fetch(FetchDescriptor<Plan>())
        let ten16 = F.id(0x310), one17 = F.id(0x311)

        // setSets
        func sets(_ item: String, day: String = F.dayA, from: Int, to: Int) -> [String: Any] {
            F.change("c1", "setSets", day: day, item: item, expect: ["targetSets": from], to: ["targetSets": to])
        }
        try expect(.applicable, sets(F.bench, from: 4, to: 5), plans, "setSets up by one")
        try expect(.applicable, sets(F.bench, from: 4, to: 3), plans, "setSets down by one")
        try expect(.invalid, sets(F.bench, from: 4, to: 6), plans, "setSets by two", mentions: "one")
        try expect(.invalid, sets(F.bench, from: 4, to: 4), plans, "setSets by none")
        try expect(.invalid, sets(ten16, day: F.soloDay, from: 10, to: 11), plans, "setSets past 10", mentions: "10")
        try expect(.applicable, sets(ten16, day: F.soloDay, from: 10, to: 9), plans, "setSets down from 10")
        try expect(.invalid, sets(one17, day: F.soloDay, from: 1, to: 0), plans, "setSets below 1")
        try expect(.stale, sets(F.bench, from: 3, to: 4), plans, "setSets whose expect no longer matches", mentions: "now has 4")
        try expect(.invalid, F.change("c1", "setSets", day: F.dayA, item: F.bench, to: ["targetSets": 5]), plans,
                   "setSets with no expect")

        // setRepRange
        func reps(_ item: String, from: (Int, Int), to: (Int, Int), day: String = F.dayA) -> [String: Any] {
            F.change("c1", "setRepRange", day: day, item: item,
                     expect: ["targetRepsLow": from.0, "targetRepsHigh": from.1],
                     to: ["targetRepsLow": to.0, "targetRepsHigh": to.1])
        }
        try expect(.applicable, reps(F.curl, from: (8, 12), to: (6, 10)), plans, "setRepRange to a lower range")
        try expect(.applicable, reps(F.curl, from: (8, 12), to: (1, 30)), plans, "setRepRange at both limits")
        try expect(.invalid, reps(F.curl, from: (8, 12), to: (0, 10)), plans, "setRepRange low of 0")
        try expect(.invalid, reps(F.curl, from: (8, 12), to: (8, 31)), plans, "setRepRange high of 31")
        try expect(.invalid, reps(F.curl, from: (8, 12), to: (12, 8)), plans, "setRepRange low above high")
        try expect(.invalid, reps(F.curl, from: (8, 12), to: (8, 12)), plans, "setRepRange that changes nothing")
        try expect(.stale, reps(F.curl, from: (6, 10), to: (5, 8)), plans, "setRepRange with a stale expect", mentions: "8–12")
        try expect(.invalid, reps(F.plank, from: (0, 0), to: (8, 12), day: F.dayB), plans, "setRepRange on a timed slot",
                   mentions: "timed")

        // setRest: the expect is the rest the slot actually uses, an override or the default
        func rest(_ item: String, from: Int, to: Int) -> [String: Any] {
            F.change("c1", "setRest", day: F.dayA, item: item, expect: ["restSeconds": from], to: ["restSeconds": to])
        }
        try expect(.applicable, rest(F.fly, from: 60, to: 90), plans, "setRest on an override")
        try expect(.applicable, rest(F.bench, from: 90, to: 120), plans, "setRest on the app default, read as 90")
        try expect(.applicable, rest(F.fly, from: 60, to: 30), plans, "setRest at 30")
        try expect(.applicable, rest(F.fly, from: 60, to: 600), plans, "setRest at 600")
        try expect(.invalid, rest(F.fly, from: 60, to: 29), plans, "setRest under 30")
        try expect(.invalid, rest(F.fly, from: 60, to: 601), plans, "setRest over 600")
        try expect(.invalid, rest(F.fly, from: 60, to: 60), plans, "setRest that changes nothing")
        try expect(.stale, rest(F.fly, from: 90, to: 120), plans, "setRest with a stale expect", mentions: "60")

        // substitute
        func swap(_ item: String, from: String, to: [String: Any], day: String = F.dayA) -> [String: Any] {
            F.change("c1", "substitute", day: day, item: item, expect: ["catalogID": from], to: to)
        }
        let dbBench: [String: Any] = ["catalogID": "dumbbell-bench-press", "name": "Dumbbell Bench Press"]
        try expect(.applicable, swap(F.bench, from: "barbell-bench-press", to: dbBench), plans, "substitute")
        try expect(.invalid, swap(F.bench, from: "barbell-bench-press",
                                  to: ["catalogID": "no-such-lift", "name": "Nothing"]), plans,
                   "substitute to an exercise the library lacks", mentions: "library")
        try expect(.invalid, swap(F.bench, from: "barbell-bench-press",
                                  to: ["catalogID": "plank-bodyweight", "name": "Standard Plank"]), plans,
                   "substitute to a timed exercise", mentions: "timed")
        try expect(.invalid, swap(F.bench, from: "barbell-bench-press",
                                  to: ["catalogID": "dumbbell-bench-press", "name": "Incline Press"]), plans,
                   "substitute under a name the library does not use", mentions: "name")
        try expect(.invalid, swap(F.bench, from: "barbell-bench-press",
                                  to: ["catalogID": "barbell-bench-press", "name": "Barbell Bench Press"]), plans,
                   "substitute for itself")
        try expect(.invalid, swap(F.plank, from: "plank-bodyweight", to: dbBench, day: F.dayB), plans,
                   "substitute on a timed slot", mentions: "timed")
        try expect(.stale, swap(F.bench, from: "dumbbell-fly", to: dbBench), plans, "substitute with a stale expect")
        try expect(.invalid, swap(F.bench, from: "barbell-bench-press", to: ["catalogID": "dumbbell-bench-press"]), plans,
                   "substitute with no name")

        // addSlot
        func add(_ day: String = F.dayA, to: [String: Any] = newLift, expect: [String: Any]? = [:]) -> [String: Any] {
            F.change("c1", "addSlot", day: day, expect: expect, to: to)
        }
        try expect(.applicable, add(), plans, "addSlot at the end of a day")
        try expect(.applicable, add(to: newLift.merging(["afterItemID": F.bench]) { $1 }), plans, "addSlot after a slot")
        try expect(.applicable, add(expect: nil), plans, "addSlot with no expect at all")
        try expect(.invalid, add(F.restDay), plans, "addSlot on a rest day", mentions: "rest day")
        try expect(.invalid, add(to: newLift.merging(["catalogID": "plank-bodyweight", "name": "Standard Plank"]) { $1 }),
                   plans, "addSlot of a timed exercise", mentions: "timed")
        try expect(.invalid, add(to: newLift.merging(["targetSets": 0]) { $1 }), plans, "addSlot with no sets")
        try expect(.invalid, add(to: newLift.merging(["targetSets": 11]) { $1 }), plans, "addSlot with 11 sets")
        try expect(.invalid, add(to: newLift.merging(["restSeconds": 20]) { $1 }), plans, "addSlot with 20 s rest")
        try expect(.invalid, add(to: newLift.merging(["targetRepsLow": 16]) { $1 }), plans, "addSlot with low above high")
        try expect(.invalid, add(to: newLift.filter { $0.key != "restSeconds" }), plans, "addSlot missing its rest")
        try expect(.invalid, add(expect: ["catalogID": "x"]), plans, "addSlot that expects something")
        try expect(.stale, add(to: newLift.merging(["afterItemID": F.row]) { $1 }), plans,
                   "addSlot after a slot from another day")
        try expect(.stale, add(to: newLift.merging(["afterItemID": F.id(0x999)]) { $1 }), plans,
                   "addSlot after a slot that is gone")

        // removeSlot
        func remove(_ item: String, from: String, day: String = F.dayA) -> [String: Any] {
            F.change("c1", "removeSlot", day: day, item: item, expect: ["catalogID": from], to: [:])
        }
        try expect(.applicable, remove(F.fly, from: "dumbbell-fly"), plans, "removeSlot")
        try expect(.stale, remove(F.fly, from: "dumbbell-curl"), plans, "removeSlot with a stale expect")
        try expect(.applicable, remove(F.squat, from: "barbell-back-squat", day: F.soloDay), plans,
                   "removeSlot while the day keeps other slots") // the solo day holds three here
        try expect(.invalid, remove(F.id(0x304), from: "barbell-row", day: F.dayB).merging(["to": ["targetSets": 1]]) { $1 },
                   plans, "removeSlot that sets something")
    }

    @MainActor static func checkLonelySlot() throws {
        let container = try F.makeContainer()
        let context = container.mainContext
        try F.insertPlan(context)
        let plans = try context.fetch(FetchDescriptor<Plan>())
        let only = F.change("c1", "removeSlot", day: F.soloDay, item: F.squat,
                            expect: ["catalogID": "barbell-back-squat"], to: [:])
        try expect(.invalid, only, plans, "removeSlot on a day's only slot", mentions: "no exercises")
    }

    @MainActor static func checkLocating() throws {
        let container = try F.makeContainer()
        let context = container.mainContext
        try F.insertPlan(context)
        let other = Plan(name: "Other")
        other.id = F.uuid(0x101)
        context.insert(other)
        try context.save()
        let plans = try context.fetch(FetchDescriptor<Plan>())
        let good = F.change("c1", "setSets", day: F.dayA, item: F.bench, expect: ["targetSets": 4], to: ["targetSets": 5])

        try expect(.stale, F.change("c1", "setSets", day: F.id(0x999), item: F.bench,
                                    expect: ["targetSets": 4], to: ["targetSets": 5]), plans, "a day that is not in the plan")
        try expect(.stale, F.change("c1", "setSets", day: F.dayA, item: F.id(0x999),
                                    expect: ["targetSets": 4], to: ["targetSets": 5]), plans, "a slot that is not in the plan")
        try expect(.stale, F.change("c1", "setSets", day: F.dayB, item: F.bench,
                                    expect: ["targetSets": 4], to: ["targetSets": 5]), plans, "a slot named under another day")
        try expect(.invalid, F.change("c1", "setSets", day: "not-a-uuid", item: F.bench,
                                      expect: ["targetSets": 4], to: ["targetSets": 5]), plans, "a day that is not an ID")
        try expect(.invalid, F.change("c1", "setSets", day: F.dayA,
                                      expect: ["targetSets": 4], to: ["targetSets": 5]), plans, "a slot change naming no slot")
        try expect(.invalid, F.change("c1", "moveSlot", day: F.dayA, item: F.bench), plans, "an unknown kind",
                   mentions: "kind")

        var noReason = good
        noReason["reason"] = "  "
        try expect(.invalid, noReason, plans, "a change with a blank reason", mentions: "reason")
        var badLever = good
        badLever["lever"] = "vibes"
        try expect(.invalid, badLever, plans, "a change with an unknown lever", mentions: "lever")
        var noEvidence = good
        noEvidence["evidence"] = nil
        try expect(.invalid, noEvidence, plans, "a change with no evidence", mentions: "evidence")
        for lever in ["effort", "volume", "priority", "exerciseChoice", "pain", "repRange", "rest"] {
            var change = good
            change["lever"] = lever
            try expect(.applicable, change, plans, "lever \(lever)")
        }

        var future = good
        future["futureField"] = ["a": 1]
        try expect(.applicable, future, plans, "a change with a key from a newer coach")

        // The proposal as a whole.
        let review = CoachValidator.review(try F.proposal(planID: F.id(0x101), changes: [good]), plans: plans)
        check(!review.hasApplicableChange && review.rows[0].status.reason?.contains("different plan") == true,
              "a proposal for another plan is stale, not applicable")

        func problem(_ changes: [[String: Any]], extra: [String: Any] = [:]) throws -> CoachValidator.Review {
            CoachValidator.review(try F.proposal(changes: changes, extra: extra), plans: plans)
        }
        func numbered(_ n: Int, item: String, from: Int) -> [String: Any] {
            F.change("c\(n)", "setSets", day: F.dayA, item: item, expect: ["targetSets": from], to: ["targetSets": from + 1])
        }
        let three = try problem([numbered(1, item: F.bench, from: 4), numbered(2, item: F.fly, from: 3),
                                 numbered(3, item: F.curl, from: 3)])
        check(three.problem == nil && three.applicableIDs == ["c1", "c2", "c3"], "three changes are allowed")
        let four = try problem([numbered(1, item: F.bench, from: 4), numbered(2, item: F.fly, from: 3),
                                numbered(3, item: F.curl, from: 3), numbered(4, item: F.row, from: 3)])
        check(four.problem?.contains("more than 3") == true && !four.hasApplicableChange && four.rows.count == 4,
              "four changes are refused as a whole")
        let sameSlot = try problem([numbered(1, item: F.bench, from: 4), numbered(2, item: F.bench, from: 4)])
        check(sameSlot.problem?.contains("same exercise") == true && !sameSlot.hasApplicableChange,
              "two changes on one slot are refused")
        let sameID = try problem([numbered(1, item: F.bench, from: 4), numbered(1, item: F.fly, from: 3)])
        check(sameID.problem?.contains("share an ID") == true, "two changes under one ID are refused")
        check(try problem([]).problem != nil, "a proposal with no changes is refused")
        check(try problem([good], extra: ["format": "something-else"]).problem != nil, "another format is refused")
        check(try problem([good], extra: ["version": 2]).problem != nil, "another version is refused")
        check(try problem([good], extra: ["id": "nope"]).problem != nil, "a proposal ID that is not an ID is refused")
        check(try problem([good], extra: ["futureTopLevel": 1]).problem == nil, "a key from a newer coach is ignored")

        // What the screen shows beside each change.
        let row = try problem([good]).rows[0]
        check(row.before == "4 sets" && row.after == "5 sets" && row.exerciseName == "Barbell Bench Press"
              && row.dayName == "Push", "a row says what the slot is and what it would become")
        let addRow = try problem([F.change("c1", "addSlot", day: F.dayA, expect: [:], to: newLift)]).rows[0]
        check(addRow.after == "Dumbbell Lateral Raise · 3 × 10–15 · 60 s rest", "an added slot is described in full")
    }

    static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        do {
            try await MainActor.run { try checkKinds(); try checkLonelySlot(); try checkLocating() }
        } catch {
            print("FAIL: threw \(error)")
            exit(1)
        }
        let failed = await MainActor.run { failures }
        if failed > 0 { exit(1) }
        print("Coach validation checks passed")
    }
}
