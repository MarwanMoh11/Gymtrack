import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// Every rule in the coach contract, checked against a live plan: each of the
/// six kinds with its limits, a stale `expect`, an unknown kind, too many
/// changes, and two changes on one slot.
///
/// What an accepted change then does to the plan is in `CoachApplyTests`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CoachValidationTests {
    typealias F = CoachFixture

    // MARK: - One change at a time

    @Test(arguments: ValidationCase.setSets)
    func setSetsMovesByOneWithinOneToTen(_ example: ValidationCase) throws {
        try judge(example)
    }

    @Test(arguments: ValidationCase.setRepRange)
    func setRepRangeStaysWithinOneToThirtyOnARepsSlot(_ example: ValidationCase) throws {
        try judge(example)
    }

    @Test(arguments: ValidationCase.setRest)
    func setRestExpectsTheRestTheSlotUsesAndStaysWithinThirtyToSixHundred(_ example: ValidationCase) throws {
        try judge(example)
    }

    @Test(arguments: ValidationCase.substitute)
    func substituteNeedsAnotherRepsExerciseUnderTheLibrarysName(_ example: ValidationCase) throws {
        try judge(example)
    }

    @Test(arguments: ValidationCase.addSlot)
    func addSlotNeedsAWholeRepsSlotOnATrainingDay(_ example: ValidationCase) throws {
        try judge(example)
    }

    @Test(arguments: ValidationCase.removeSlot)
    func removeSlotSetsNothingAndNeverEmptiesADay(_ example: ValidationCase) throws {
        try judge(example)
    }

    @Test(arguments: ValidationCase.locating)
    func aChangeNamesASlotInTheActivePlanAndSaysWhy(_ example: ValidationCase) throws {
        try judge(example)
    }

    @Test(arguments: ["effort", "volume", "priority", "exerciseChoice", "pain", "repRange", "rest"])
    func everyLeverTheContractNamesIsAccepted(lever: String) throws {
        try judge(ValidationCase("lever \(lever)", .applicable, on: .besideAnotherPlan) {
            ValidationCase.good.merging(["lever": lever]) { $1 }
        })
    }

    // MARK: - The proposal as a whole

    @Test func aProposalForAnotherPlanIsStaleNotApplicable() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let plans = try PlanShape.besideAnotherPlan.plans(in: context)

        let review = CoachValidator.review(try F.proposal(planID: F.id(0x101), changes: [ValidationCase.good]), plans: plans)

        #expect(!review.hasApplicableChange)
        #expect(review.rows.first?.status.reason?.contains("different plan") == true)
    }

    @Test func upToThreeChangesOnDistinctSlotsUnderDistinctIDsAreAllowed() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let plans = try PlanShape.besideAnotherPlan.plans(in: context)
        func review(_ changes: [[String: Any]]) throws -> CoachValidator.Review {
            CoachValidator.review(try F.proposal(changes: changes), plans: plans)
        }
        func numbered(_ n: Int, item: String, from: Int) -> [String: Any] {
            F.change("c\(n)", "setSets", day: F.dayA, item: item, expect: ["targetSets": from], to: ["targetSets": from + 1])
        }

        let three = try review([numbered(1, item: F.bench, from: 4), numbered(2, item: F.fly, from: 3),
                                numbered(3, item: F.curl, from: 3)])
        #expect(three.problem == nil && three.applicableIDs == ["c1", "c2", "c3"], "Three changes are allowed")

        let four = try review([numbered(1, item: F.bench, from: 4), numbered(2, item: F.fly, from: 3),
                               numbered(3, item: F.curl, from: 3), numbered(4, item: F.row, from: 3)])
        #expect(four.problem?.contains("more than 3") == true && !four.hasApplicableChange && four.rows.count == 4,
                "Four changes are refused as a whole")

        let sameSlot = try review([numbered(1, item: F.bench, from: 4), numbered(2, item: F.bench, from: 4)])
        #expect(sameSlot.problem?.contains("same exercise") == true && !sameSlot.hasApplicableChange,
                "Two changes on one slot are refused")

        let sameID = try review([numbered(1, item: F.bench, from: 4), numbered(1, item: F.fly, from: 3)])
        #expect(sameID.problem?.contains("share an ID") == true, "Two changes under one ID are refused")
    }

    @Test func aProposalTheContractDoesNotDescribeIsRefusedButANewerKeyIsIgnored() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let plans = try PlanShape.besideAnotherPlan.plans(in: context)
        func problem(_ changes: [[String: Any]], extra: [String: Any] = [:]) throws -> String? {
            CoachValidator.review(try F.proposal(changes: changes, extra: extra), plans: plans).problem
        }
        let good = ValidationCase.good

        #expect(try problem([]) != nil, "No changes")
        #expect(try problem([good], extra: ["format": "something-else"]) != nil, "Another format")
        #expect(try problem([good], extra: ["version": 2]) != nil, "Another version")
        #expect(try problem([good], extra: ["id": "nope"]) != nil, "A proposal ID that is not an ID")
        #expect(try problem([good], extra: ["futureTopLevel": 1]) == nil, "A key from a newer coach is ignored")
    }

    @Test func eachRowSaysWhatTheSlotIsAndWhatItWouldBecome() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let plans = try PlanShape.besideAnotherPlan.plans(in: context)
        func row(_ change: [String: Any]) throws -> CoachValidator.Row? {
            CoachValidator.review(try F.proposal(changes: [change]), plans: plans).rows.first
        }

        let edit = try #require(try row(ValidationCase.good))
        #expect(edit.before == "4 sets" && edit.after == "5 sets")
        #expect(edit.exerciseName == "Barbell Bench Press" && edit.dayName == "Push")

        let added = try row(F.change("c1", "addSlot", day: F.dayA, expect: [:], to: ValidationCase.newLift))
        #expect(added?.after == "Dumbbell Lateral Raise · 3 × 10–15 · 60 s rest", "An added slot is described in full")
    }

    // MARK: - Helpers

    /// The rest a slot without its own reads as the app default, so the
    /// settings are pinned: "setRest on the app default" expects 90.
    private func judge(_ example: ValidationCase) throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let plans = try example.shape.plans(in: context)

        let status = try F.status(example.change(), plans: plans)

        #expect(example.verdict.matches(status), "\(example.name): got \(status)")
        if let mentions = example.mentions {
            #expect(status.reason?.localizedCaseInsensitiveContains(mentions) == true,
                    "\(example.name): the reason should say \"\(mentions)\", got \"\(status.reason ?? "nothing")\"")
        }
    }
}

/// The plan a validation case is checked against.
enum PlanShape: Sendable {
    /// The fixture plan as built.
    case asBuilt
    /// The fixture plan with two more slots on the leg day: one already at the
    /// top of the sets range and one at the bottom. The leg day then holds
    /// three, so removing the squat leaves it something.
    case crowdedLegDay
    /// The fixture plan beside a second, inactive one.
    case besideAnotherPlan

    @MainActor func plans(in context: ModelContext) throws -> [Plan] {
        try CoachFixture.insertPlan(context)
        switch self {
        case .asBuilt:
            break
        case .crowdedLegDay:
            let legs = try CoachFixture.day(CoachFixture.soloDay, context)
            let ten = PlanItem(catalogID: "barbell-bench-press", name: "Barbell Bench Press", order: 1, targetSets: 10)
            ten.id = ValidationCase.tenSets
            ten.day = legs
            context.insert(ten)
            let one = PlanItem(catalogID: "barbell-row", name: "Bent Over Barbell Row", order: 2, targetSets: 1)
            one.id = ValidationCase.oneSet
            one.day = legs
            context.insert(one)
        case .besideAnotherPlan:
            let other = Plan(name: "Other")
            other.id = CoachFixture.uuid(0x101)
            context.insert(other)
        }
        try context.save()
        return try context.fetch(FetchDescriptor<Plan>())
    }
}

/// One change, and what the phone must make of it against the plan as it is.
struct ValidationCase: Sendable, CustomTestStringConvertible {
    typealias F = CoachFixture

    enum Verdict: Sendable {
        case applicable, stale, invalid

        func matches(_ status: CoachValidator.Status) -> Bool {
            switch (self, status) {
            case (.applicable, .applicable), (.stale, .stale), (.invalid, .invalid): true
            default: false
            }
        }
    }

    let name: String
    let verdict: Verdict
    /// A word the reason must use, so the screen says why rather than only
    /// that a change was refused.
    let mentions: String?
    let shape: PlanShape
    /// A closure because a change is a JSON dictionary, which can't be sent
    /// across to the test as an argument.
    let change: @Sendable () -> [String: Any]

    init(_ name: String, _ verdict: Verdict, mentions: String? = nil, on shape: PlanShape = .crowdedLegDay,
         _ change: @escaping @Sendable () -> [String: Any]) {
        self.name = name
        self.verdict = verdict
        self.mentions = mentions
        self.shape = shape
        self.change = change
    }

    var testDescription: String { name }

    static let tenSets = F.uuid(0x310)
    static let oneSet = F.uuid(0x311)

    static var newLift: [String: Any] {
        ["catalogID": "dumbbell-lateral-raise", "name": "Dumbbell Lateral Raise",
         "targetSets": 3, "targetRepsLow": 10, "targetRepsHigh": 15, "restSeconds": 60]
    }

    /// A change with nothing wrong with it, for the checks that break one thing.
    static var good: [String: Any] {
        F.change("c1", "setSets", day: F.dayA, item: F.bench, expect: ["targetSets": 4], to: ["targetSets": 5])
    }

    // MARK: setSets

    static let setSets: [ValidationCase] = [
        .init("setSets up by one", .applicable) { sets(F.bench, from: 4, to: 5) },
        .init("setSets down by one", .applicable) { sets(F.bench, from: 4, to: 3) },
        .init("setSets by two", .invalid, mentions: "one") { sets(F.bench, from: 4, to: 6) },
        .init("setSets by none", .invalid) { sets(F.bench, from: 4, to: 4) },
        .init("setSets past 10", .invalid, mentions: "10") { sets(tenSets.uuidString, day: F.soloDay, from: 10, to: 11) },
        .init("setSets down from 10", .applicable) { sets(tenSets.uuidString, day: F.soloDay, from: 10, to: 9) },
        .init("setSets below 1", .invalid) { sets(oneSet.uuidString, day: F.soloDay, from: 1, to: 0) },
        .init("setSets whose expect no longer matches", .stale, mentions: "now has 4") { sets(F.bench, from: 3, to: 4) },
        .init("setSets with no expect", .invalid) {
            F.change("c1", "setSets", day: F.dayA, item: F.bench, to: ["targetSets": 5])
        },
    ]

    static func sets(_ item: String, day: String = F.dayA, from: Int, to: Int) -> [String: Any] {
        F.change("c1", "setSets", day: day, item: item, expect: ["targetSets": from], to: ["targetSets": to])
    }

    // MARK: setRepRange

    static let setRepRange: [ValidationCase] = [
        .init("setRepRange to a lower range", .applicable) { reps(F.curl, from: (8, 12), to: (6, 10)) },
        .init("setRepRange at both limits", .applicable) { reps(F.curl, from: (8, 12), to: (1, 30)) },
        .init("setRepRange low of 0", .invalid) { reps(F.curl, from: (8, 12), to: (0, 10)) },
        .init("setRepRange high of 31", .invalid) { reps(F.curl, from: (8, 12), to: (8, 31)) },
        .init("setRepRange low above high", .invalid) { reps(F.curl, from: (8, 12), to: (12, 8)) },
        .init("setRepRange that changes nothing", .invalid) { reps(F.curl, from: (8, 12), to: (8, 12)) },
        .init("setRepRange with a stale expect", .stale, mentions: "8–12") { reps(F.curl, from: (6, 10), to: (5, 8)) },
        .init("setRepRange on a timed slot", .invalid, mentions: "timed") {
            reps(F.plank, from: (0, 0), to: (8, 12), day: F.dayB)
        },
    ]

    static func reps(_ item: String, from: (Int, Int), to: (Int, Int), day: String = F.dayA) -> [String: Any] {
        F.change("c1", "setRepRange", day: day, item: item,
                 expect: ["targetRepsLow": from.0, "targetRepsHigh": from.1],
                 to: ["targetRepsLow": to.0, "targetRepsHigh": to.1])
    }

    // MARK: setRest

    /// The expect is the rest the slot actually uses: its own, or the default.
    static let setRest: [ValidationCase] = [
        .init("setRest on an override", .applicable) { rest(F.fly, from: 60, to: 90) },
        .init("setRest on the app default, read as 90", .applicable) { rest(F.bench, from: 90, to: 120) },
        .init("setRest at 30", .applicable) { rest(F.fly, from: 60, to: 30) },
        .init("setRest at 600", .applicable) { rest(F.fly, from: 60, to: 600) },
        .init("setRest under 30", .invalid) { rest(F.fly, from: 60, to: 29) },
        .init("setRest over 600", .invalid) { rest(F.fly, from: 60, to: 601) },
        .init("setRest that changes nothing", .invalid) { rest(F.fly, from: 60, to: 60) },
        .init("setRest with a stale expect", .stale, mentions: "60") { rest(F.fly, from: 90, to: 120) },
    ]

    static func rest(_ item: String, from: Int, to: Int) -> [String: Any] {
        F.change("c1", "setRest", day: F.dayA, item: item, expect: ["restSeconds": from], to: ["restSeconds": to])
    }

    // MARK: substitute

    static let substitute: [ValidationCase] = [
        .init("substitute", .applicable) { swap(F.bench, from: "barbell-bench-press", to: dumbbellBench) },
        .init("substitute to an exercise the library lacks", .invalid, mentions: "library") {
            swap(F.bench, from: "barbell-bench-press", to: ["catalogID": "no-such-lift", "name": "Nothing"])
        },
        .init("substitute to a timed exercise", .invalid, mentions: "timed") {
            swap(F.bench, from: "barbell-bench-press", to: ["catalogID": "plank-bodyweight", "name": "Standard Plank"])
        },
        .init("substitute under a name the library does not use", .invalid, mentions: "name") {
            swap(F.bench, from: "barbell-bench-press", to: ["catalogID": "dumbbell-bench-press", "name": "Incline Press"])
        },
        .init("substitute for itself", .invalid) {
            swap(F.bench, from: "barbell-bench-press", to: ["catalogID": "barbell-bench-press", "name": "Barbell Bench Press"])
        },
        .init("substitute on a timed slot", .invalid, mentions: "timed") {
            swap(F.plank, from: "plank-bodyweight", to: dumbbellBench, day: F.dayB)
        },
        .init("substitute with a stale expect", .stale) { swap(F.bench, from: "dumbbell-fly", to: dumbbellBench) },
        .init("substitute with no name", .invalid) {
            swap(F.bench, from: "barbell-bench-press", to: ["catalogID": "dumbbell-bench-press"])
        },
    ]

    static var dumbbellBench: [String: Any] { ["catalogID": "dumbbell-bench-press", "name": "Dumbbell Bench Press"] }

    static func swap(_ item: String, from: String, to: [String: Any], day: String = F.dayA) -> [String: Any] {
        F.change("c1", "substitute", day: day, item: item, expect: ["catalogID": from], to: to)
    }

    // MARK: addSlot

    static let addSlot: [ValidationCase] = [
        .init("addSlot at the end of a day", .applicable) { add() },
        .init("addSlot after a slot", .applicable) { add(to: lift(["afterItemID": F.bench])) },
        .init("addSlot with no expect at all", .applicable) { add(expect: nil) },
        .init("addSlot on a rest day", .invalid, mentions: "rest day") { add(F.restDay) },
        .init("addSlot of a timed exercise", .invalid, mentions: "timed") {
            add(to: lift(["catalogID": "plank-bodyweight", "name": "Standard Plank"]))
        },
        .init("addSlot with no sets", .invalid) { add(to: lift(["targetSets": 0])) },
        .init("addSlot with 11 sets", .invalid) { add(to: lift(["targetSets": 11])) },
        .init("addSlot with 20 s rest", .invalid) { add(to: lift(["restSeconds": 20])) },
        .init("addSlot with low above high", .invalid) { add(to: lift(["targetRepsLow": 16])) },
        .init("addSlot missing its rest", .invalid) { add(to: newLift.filter { $0.key != "restSeconds" }) },
        .init("addSlot that expects something", .invalid) { add(expect: ["catalogID": "x"]) },
        .init("addSlot after a slot from another day", .stale) { add(to: lift(["afterItemID": F.row])) },
        .init("addSlot after a slot that is gone", .stale) { add(to: lift(["afterItemID": F.id(0x999)])) },
    ]

    static func lift(_ overrides: [String: Any]) -> [String: Any] {
        newLift.merging(overrides) { $1 }
    }

    static func add(_ day: String = F.dayA, to: [String: Any] = newLift, expect: [String: Any]? = [:]) -> [String: Any] {
        F.change("c1", "addSlot", day: day, expect: expect, to: to)
    }

    // MARK: removeSlot

    static let removeSlot: [ValidationCase] = [
        .init("removeSlot", .applicable) { remove(F.fly, from: "dumbbell-fly") },
        .init("removeSlot with a stale expect", .stale) { remove(F.fly, from: "dumbbell-curl") },
        .init("removeSlot while the day keeps other slots", .applicable) {
            remove(F.squat, from: "barbell-back-squat", day: F.soloDay)
        },
        .init("removeSlot that sets something", .invalid) {
            remove(F.row, from: "barbell-row", day: F.dayB).merging(["to": ["targetSets": 1]]) { $1 }
        },
        .init("removeSlot on a day's only slot", .invalid, mentions: "no exercises", on: .asBuilt) {
            remove(F.squat, from: "barbell-back-squat", day: F.soloDay)
        },
    ]

    static func remove(_ item: String, from: String, day: String = F.dayA) -> [String: Any] {
        F.change("c1", "removeSlot", day: day, item: item, expect: ["catalogID": from], to: [:])
    }

    // MARK: Finding the slot, and the fields every change carries

    static let locating: [ValidationCase] = [
        .init("a day that is not in the plan", .stale, on: .besideAnotherPlan) {
            F.change("c1", "setSets", day: F.id(0x999), item: F.bench, expect: ["targetSets": 4], to: ["targetSets": 5])
        },
        .init("a slot that is not in the plan", .stale, on: .besideAnotherPlan) {
            F.change("c1", "setSets", day: F.dayA, item: F.id(0x999), expect: ["targetSets": 4], to: ["targetSets": 5])
        },
        .init("a slot named under another day", .stale, on: .besideAnotherPlan) {
            F.change("c1", "setSets", day: F.dayB, item: F.bench, expect: ["targetSets": 4], to: ["targetSets": 5])
        },
        .init("a day that is not an ID", .invalid, on: .besideAnotherPlan) {
            F.change("c1", "setSets", day: "not-a-uuid", item: F.bench, expect: ["targetSets": 4], to: ["targetSets": 5])
        },
        .init("a slot change naming no slot", .invalid, on: .besideAnotherPlan) {
            F.change("c1", "setSets", day: F.dayA, expect: ["targetSets": 4], to: ["targetSets": 5])
        },
        .init("an unknown kind", .invalid, mentions: "kind", on: .besideAnotherPlan) {
            F.change("c1", "moveSlot", day: F.dayA, item: F.bench)
        },
        .init("a change with a blank reason", .invalid, mentions: "reason", on: .besideAnotherPlan) {
            good.merging(["reason": "  "]) { $1 }
        },
        .init("a change with an unknown lever", .invalid, mentions: "lever", on: .besideAnotherPlan) {
            good.merging(["lever": "vibes"]) { $1 }
        },
        .init("a change with no evidence", .invalid, mentions: "evidence", on: .besideAnotherPlan) {
            good.filter { $0.key != "evidence" }
        },
        .init("a change with a key from a newer coach", .applicable, on: .besideAnotherPlan) {
            good.merging(["futureField": ["a": 1]]) { $1 }
        },
    ]
}
