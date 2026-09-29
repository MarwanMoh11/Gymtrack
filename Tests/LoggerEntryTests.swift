import Foundation
import SwiftData

/// Run with scripts/test-logger-entry.sh; no simulator is needed.
///
/// Three review findings about what the logger writes down: a load offer is
/// answered only by a set it was about, and undoing that set takes the answer
/// back (SESS-02); a typed number can't crash the logger or store a load nobody
/// lifted (XC-01); and new rows carry no hold time, reps or target nobody set
/// (DATA-04, the source side).
@main
struct LoggerEntryTests {
    /// Pass case names to run only those — how each was seen to fail on its
    /// own against the code before the fix.
    @MainActor static func main() throws {
        let cases: [(String, @MainActor () throws -> Void)] = [
            ("offer-standing", otherExercisesAndDropRowsLeaveTheOfferStanding),
            ("offer-taken-by-hand", aLiftAtTheOfferedRungCountsAsTaken),
            ("offer-undo", undoingTheAnsweringSetRestoresTheOffer),
            ("taken-undo", aTakenOffersUndoOutlivesOtherExercises),
            ("row-measures", newRowsCarryOnlyTheirOwnMeasure),
            ("off-plan-targets", offPlanRowsHaveNoInventedTarget),
            ("typed-entry", typedEntryIsBounded),
        ]
        let chosen = Set(CommandLine.arguments.dropFirst())
        for (name, run) in cases where chosen.isEmpty || chosen.contains(name) {
            try run()
        }
        print("Logger entry tests passed.")
    }

    // MARK: - Fixture

    /// Bench 3 x 8–10 at 100 kg, row 3 x 8–10 at 60 kg, and a timed plank —
    /// a fresh store every time, so no case sees another's leftovers.
    @MainActor
    static func freshWorkout() throws -> ActiveWorkout {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        retained.append(container)

        let plan = Plan(name: "Offers")
        let day = PlanDay(name: "Upper", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        for (order, (id, load)) in [("bench-test", 100.0), ("row-test", 60)].enumerated() {
            let item = PlanItem(catalogID: id, name: id, order: order, targetSets: 3,
                                targetRepsLow: 8, targetRepsHigh: 10, targetWeightKg: load)
            item.day = day
            context.insert(item)
        }
        let plank = PlanItem(catalogID: "plank-test", name: "plank-test", order: 2,
                             targetSets: 2, targetSeconds: 60)
        plank.trackingRaw = TrackingMode.duration.rawValue
        plank.day = day
        context.insert(plank)

        return ActiveWorkout.start(day: day, plan: plan, context: context, history: [])
    }

    /// The container has to outlive the case, or its context goes with it.
    @MainActor static var retained: [ModelContainer] = []

    @MainActor
    static func sets(_ id: String, in workout: ActiveWorkout) -> [SetLog] {
        workout.groups.first { $0.catalogID == id }?.sets ?? []
    }

    /// Bench set 1 cleared the top of its range and felt easy: the logger
    /// offers the next rung for the two sets still to come.
    @MainActor
    static func offerAfterEasyOpener(in workout: ActiveWorkout) -> SetLog {
        let opener = sets("bench-test", in: workout)[0]
        opener.reps = 10
        workout.complete(opener, restSeconds: nil)
        workout.rate(opener, feel: .easy)
        precondition(workout.pendingNudge(for: "bench-test")?.setID == opener.id, "An easy top-of-range set is offered a rung")
        precondition(workout.pendingNudge(for: "bench-test")?.setCount == 2)
        return opener
    }

    // MARK: - SESS-02

    @MainActor
    static func otherExercisesAndDropRowsLeaveTheOfferStanding() throws {
        let workout = try freshWorkout()
        let opener = offerAfterEasyOpener(in: workout)
        let rung = workout.pendingNudge(for: "bench-test")!.toKg

        workout.complete(sets("row-test", in: workout)[0], restSeconds: nil)
        precondition(opener.loadNudgeOutcome == nil,
                     "A superset partner's set is no answer to the bench offer")
        precondition(workout.pendingNudge(for: "bench-test")?.setID == opener.id, "The offer stands over its own card")

        workout.continueSet(opener)
        let drop = sets("bench-test", in: workout)[1]
        precondition(drop.isContinuation)
        drop.weightKg = 80
        workout.complete(drop, restSeconds: nil)
        precondition(opener.loadNudgeOutcome == nil, "A drop row is no answer to the offer either")
        precondition(workout.pendingNudge(for: "bench-test")?.setID == opener.id)

        let next = sets("bench-test", in: workout)[2]
        precondition(!next.isContinuation && next.weightKg == 100)
        workout.complete(next, restSeconds: nil)
        precondition(opener.loadNudgeOutcome == .declined && opener.loadNudgeToKg == rung,
                     "The next working set at the weight that stood is a decline")
        precondition(workout.pendingNudge(for: "bench-test") == nil)
    }

    @MainActor
    static func aLiftAtTheOfferedRungCountsAsTaken() throws {
        let workout = try freshWorkout()
        let opener = offerAfterEasyOpener(in: workout)
        let rung = workout.pendingNudge(for: "bench-test")!.toKg
        let second = sets("bench-test", in: workout)[1]
        // Typed in pounds and converted back, as a lifter on a pound-marked
        // bench would dial it: the same rung, not necessarily the same bits.
        second.weightKg = WeightUnit.lb.toKg(WeightUnit.lb.fromKg(rung))
        workout.complete(second, restSeconds: nil)
        precondition(opener.loadNudgeOutcome == .taken && opener.loadNudgeToKg == rung,
                     "A set dialled to the offered rung by hand took the offer")
        precondition(workout.pendingNudge(for: "bench-test") == nil)
    }

    @MainActor
    static func undoingTheAnsweringSetRestoresTheOffer() throws {
        for takesTheRung in [false, true] {
            let workout = try freshWorkout()
            let opener = offerAfterEasyOpener(in: workout)
            let offered = workout.pendingNudge(for: "bench-test")
            let second = sets("bench-test", in: workout)[1]
            let lifted = takesTheRung ? offered!.toKg : second.weightKg
            second.weightKg = lifted
            workout.complete(second, restSeconds: nil)
            precondition(opener.loadNudgeOutcome != nil)

            workout.uncomplete(second)
            precondition(opener.loadNudgeOutcome == nil && opener.loadNudgeToKg == nil,
                         "Undoing the set that answered the offer leaves no answer behind (\(lifted) kg)")
            precondition(workout.pendingNudge(for: "bench-test") == offered,
                         "The offer stands again, exactly as it did (\(lifted) kg)")
        }
    }

    @MainActor
    static func aTakenOffersUndoOutlivesOtherExercises() throws {
        let workout = try freshWorkout()
        let opener = offerAfterEasyOpener(in: workout)
        workout.apply(workout.pendingNudge(for: "bench-test")!)
        precondition(workout.takenNudge(for: "bench-test") != nil && opener.loadNudgeOutcome == .taken)

        workout.complete(sets("row-test", in: workout)[0], restSeconds: nil)
        precondition(workout.takenNudge(for: "bench-test") != nil, "Another exercise's set leaves the undo open")

        let second = sets("bench-test", in: workout)[1]
        precondition(second.weightKg == opener.loadNudgeToKg)
        workout.complete(second, restSeconds: nil)
        precondition(workout.takenNudge(for: "bench-test") == nil, "Lifting a moved set closes the undo")
        precondition(opener.loadNudgeOutcome == .taken)

        workout.uncomplete(second)
        precondition(workout.takenNudge(for: "bench-test") != nil, "Undoing that set opens it again")
        workout.undoTakenNudge(workout.takenNudge(for: "bench-test")!)
        precondition(sets("bench-test", in: workout)[1...].allSatisfy { $0.weightKg == 100 },
                     "Undoing the take puts back every weight, including the set logged and undone")
        precondition(opener.loadNudgeOutcome == nil && workout.pendingNudge(for: "bench-test")?.setID == opener.id)
    }

    // MARK: - DATA-04, source side

    @MainActor
    static func newRowsCarryOnlyTheirOwnMeasure() throws {
        let workout = try freshWorkout()
        let bench = sets("bench-test", in: workout)
        precondition(bench.allSatisfy { $0.seconds == 0 && $0.reps == 8 },
                     "A weighted row is seeded with reps and no hold time")
        let plank = sets("plank-test", in: workout)
        precondition(plank.count == 2 && plank.allSatisfy { $0.seconds == 60 && $0.reps == 0 },
                     "A timed row is seeded with its hold and no reps")

        workout.complete(bench[0], restSeconds: nil)
        workout.continueSet(bench[0])
        let drop = sets("bench-test", in: workout)[1]
        precondition(drop.isContinuation && drop.seconds == 0 && drop.reps == 8)
        precondition(drop.targetRepsLow == 0 && drop.targetRepsHigh == 0)

        // A row saved before sessions stopped seeding a hold onto every row.
        bench[1].seconds = 45
        workout.complete(bench[1], restSeconds: nil)
        workout.continueSet(bench[1])
        let olderDrop = sets("bench-test", in: workout).first { $0.isContinuation && $0.setIndex > 2 }
        precondition(olderDrop?.seconds == 0, "A drop row does not copy an unmeasured hold forward")

        workout.complete(plank[0], restSeconds: nil)
        workout.continueSet(plank[0])
        let plankContinuation = sets("plank-test", in: workout)[1]
        precondition(plankContinuation.isContinuation
                     && plankContinuation.seconds == 60 && plankContinuation.reps == 0)
    }

    @MainActor
    static func offPlanRowsHaveNoInventedTarget() throws {
        let workout = try freshWorkout()
        let curl = CatalogExercise(id: "curl-test", name: "curl-test", category: "strength",
                                   muscleGroups: [], equipment: [], details: nil,
                                   difficulty: nil, tracking: .weightReps)
        workout.addExercise(curl, sets: 2)
        let curls = sets("curl-test", in: workout)
        precondition(curls.count == 2 && curls.allSatisfy {
            $0.targetRepsLow == 0 && $0.targetRepsHigh == 0 && $0.seconds == 0 && $0.reps == 10
        }, "An exercise added on the floor has no target and no hold time")

        let hold = CatalogExercise(id: "hold-test", name: "hold-test", category: "core",
                                   muscleGroups: [], equipment: [], details: nil,
                                   difficulty: nil, tracking: .duration)
        workout.addExercise(hold, sets: 1)
        let holds = sets("hold-test", in: workout)
        precondition(holds.count == 1 && holds[0].reps == 0 && holds[0].seconds == 45)

        // More of a planned exercise keeps the range the plan gave it.
        workout.addExercise(CatalogExercise(id: "bench-test", name: "bench-test", category: "strength",
                                            muscleGroups: [], equipment: [], details: nil,
                                            difficulty: nil, tracking: .weightReps), sets: 1)
        let extraBench = sets("bench-test", in: workout).last!
        precondition(extraBench.targetRepsLow == 8 && extraBench.targetRepsHigh == 10)

        // No range reads as no range: an easy set offers the next rung, and an
        // all-out one is never said to have fallen short of a target.
        curls[0].weightKg = 20
        curls[0].reps = 6
        workout.complete(curls[0], restSeconds: nil)
        precondition(!curls[0].hitTopOfRange && !curls[0].fellShortOfRange)
        workout.rate(curls[0], feel: .allOut)
        precondition(workout.pendingNudge(for: "curl-test") == nil, "No target, so nothing fell short of one")
        workout.rate(curls[0], feel: .easy)
        precondition(workout.pendingNudge(for: "curl-test")?.setID == curls[0].id && workout.pendingNudge(for: "curl-test")?.toKg == curls[0].loadScale.step(kg: 20, by: 1))
    }

    // MARK: - XC-01

    @MainActor static func typedEntryIsBounded() {
        let weight = 500.0
        precondition(StepperEntry.parse("1e999", maximum: weight) == nil, "Infinity is refused")
        precondition(StepperEntry.parse("inf", maximum: weight) == nil)
        precondition(StepperEntry.parse("nan", maximum: weight) == nil)
        precondition(StepperEntry.parse("99999999999999999999", maximum: 3_600) == nil,
                     "Twenty digits are refused rather than trapping")
        precondition(StepperEntry.parse("1000", maximum: weight) == nil, "Past the ceiling is refused")
        precondition(StepperEntry.parse("-5", maximum: weight) == nil)
        precondition(StepperEntry.parse("", maximum: weight) == nil)
        precondition(StepperEntry.parse("500", maximum: weight) == 500)
        precondition(StepperEntry.parse(" 100 ", maximum: weight) == 100)
        precondition(StepperEntry.parse("60,5", maximum: weight) == 60.5, "The decimal comma reads")
        precondition(StepperEntry.parse("٦٠٫٥", maximum: weight) == 60.5, "Arabic-Indic digits read")
        precondition(StepperEntry.parse("-0", maximum: weight).map { $0.sign } == .plus)

        precondition(StepperEntry.count(1e20, maximum: 100, current: 8) == nil)
        precondition(StepperEntry.count(.infinity, maximum: 100, current: 8) == nil)
        precondition(StepperEntry.count(.nan, maximum: 100, current: 8) == nil)
        precondition(StepperEntry.count(Double(Int.max), maximum: 100, current: Int.max) == nil)
        precondition(StepperEntry.count(12.7, maximum: 100, current: 8) == 12)
        precondition(StepperEntry.count(101, maximum: StepperEntry.maximumReps, current: 100) == nil)
        precondition(StepperEntry.count(149, maximum: 100, current: 150) == 149,
                     "A count stored before the ceiling can still be stepped down")
        precondition(!StepperEntry.accepts(1_000, maximum: weight, current: 100))
        precondition(StepperEntry.accepts(997.5, maximum: weight, current: 1_000))
        precondition(!StepperEntry.accepts(-2.5, maximum: weight, current: 0))
    }
}
