import Foundation
import SwiftData

/// Run with scripts/test-logger-followups.sh; no simulator is needed.
///
/// Two gaps the logger fixes left in `ActiveWorkout`. Adding the survivor of a
/// merged exercise to a session that holds the losing ID opened a second card
/// for one lift (GT-016, LIB-03). And undoing a set with a logged drop beneath
/// it left the drop in the record, taken without rest off a set that was never
/// done (LOG-03).
@main
struct LoggerFollowUpTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        try addingTheSurvivorJoinsTheMergedCard(context)
        try addingAnotherExerciseStillOpensACard(context)
        try undoTakesTheDropWithIt(context)
        try undoTakesAWholeRunOfDrops(context)
        try undoOfADropTakesOnlyWhatContinuesIt(context)
        try repeatedUndoKeepsALaterLift(context)

        guard failures == 0 else {
            print("\(failures) logger follow-up check(s) failed")
            exit(1)
        }
        print("Logger follow-up tests passed")
    }

    @MainActor @discardableResult
    static func row(_ id: String, order: Int, index: Int, in session: WorkoutSession,
                    context: ModelContext, kg: Double = 80) -> SetLog {
        let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: order, setIndex: index,
                         weightKg: kg, reps: 8, seconds: 0, targetRepsLow: 8, targetRepsHigh: 12,
                         tracking: .weightReps)
        set.session = session
        context.insert(set)
        return set
    }

    @MainActor static func session(_ title: String, _ context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: title, startedAt: .now.addingTimeInterval(-3_600))
        context.insert(session)
        return session
    }

    /// The rows of one exercise, top to bottom.
    @MainActor static func card(_ id: String, of session: WorkoutSession) -> [SetLog] {
        session.sets.filter { $0.catalogID == id }.sorted { $0.setIndex < $1.setIndex }
    }

    static func isErased(_ set: SetLog) -> Bool {
        !set.isCompleted && set.completedAt == nil && set.rpe == nil && set.startedAt == nil
    }

    // MARK: GT-016 / LIB-03

    @MainActor static func addingTheSurvivorJoinsTheMergedCard(_ context: ModelContext) throws {
        let session = session("Merged", context)
        let losing = "dumbbell-pullover-chest"
        row(losing, order: 0, index: 0, in: session, context: context, kg: 20)
        row("barbell-bench-press", order: 1, index: 0, in: session, context: context)
        try context.save()
        guard let survivor = ExerciseCatalog.shared.exercise(id: "dumbbell-pullover") else {
            check(false, "The bundled catalog must hold the survivor")
            return
        }
        precondition(ExerciseCatalog.canonicalID(for: losing) == survivor.id)

        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.addExercise(survivor, sets: 2)

        let pullovers = workout.groups.filter {
            ExerciseCatalog.canonicalID(for: $0.catalogID) == survivor.id
        }
        check(pullovers.count == 1, "Adding the survivor must not open a second card, got \(pullovers.count)")
        check(workout.groups.count == 2, "The session must still hold two exercises, got \(workout.groups.count)")
        let rows = card(losing, of: session)
        check(rows.count == 3, "The two new rows must join the card already there, got \(rows.count)")
        check(rows.map(\.setIndex) == [0, 1, 2], "The new rows must follow on, got \(rows.map(\.setIndex))")
        check(rows.allSatisfy { $0.exerciseOrder == 0 }, "The new rows must keep the card's place")
        check(rows.dropFirst().allSatisfy { $0.weightKg == 20 },
              "The new rows must open at the card's own load")
    }

    @MainActor static func addingAnotherExerciseStillOpensACard(_ context: ModelContext) throws {
        let session = session("Separate", context)
        row("dumbbell-pullover-chest", order: 0, index: 0, in: session, context: context)
        try context.save()
        guard let bench = ExerciseCatalog.shared.exercise(id: "barbell-bench-press") else {
            check(false, "The bundled catalog must hold the bench press")
            return
        }
        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.addExercise(bench, sets: 3)
        check(workout.groups.count == 2, "A different movement must get its own card")
        check(card("barbell-bench-press", of: session).map(\.exerciseOrder) == [1, 1, 1],
              "A new movement must go below the last card")
    }

    // MARK: LOG-03, second half

    @MainActor static func undoTakesTheDropWithIt(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_800)
        let session = session("Drop", context)
        let a1 = row("A", order: 0, index: 0, in: session, context: context)
        let a2 = row("A", order: 0, index: 1, in: session, context: context)
        let a3 = row("A", order: 0, index: 2, in: session, context: context)
        try context.save()

        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.complete(a1, restSeconds: nil, at: t0)
        workout.complete(a2, restSeconds: nil, at: t0.addingTimeInterval(180))
        workout.continueSet(a2)
        guard let drop = card("A", of: session).first(where: \.isContinuation) else {
            check(false, "Continuing a set must add a row")
            return
        }
        drop.weightKg = 60
        drop.startedAt = t0.addingTimeInterval(185)
        workout.complete(drop, restSeconds: nil, at: t0.addingTimeInterval(210))
        workout.rate(drop, feel: .allOut)
        check(drop.isCompleted && drop.rpe != nil, "The drop must be logged and rated before the undo")

        workout.uncomplete(a2)

        check(isErased(a2), "The undone set must be erased")
        check(isErased(drop), "A logged drop under an undone set must be taken back with it")
        check(drop.isContinuation, "The drop row must stay a continuation, as `unlog` keeps it")
        check(drop.weightKg == 60 && drop.reps == 8, "The drop must keep its numbers, so logging it again is one tap")
        check(workout.lastLoggedSetID == nil, "The drop must not stay the last logged set")
        check(a1.isCompleted, "The set above must stay logged")
        check(!a3.isCompleted, "The set below must be untouched")
        check(!workout.restTimer.isRunning, "No rest may run for a set taken back")
    }

    @MainActor static func undoTakesAWholeRunOfDrops(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_800)
        let session = session("Double drop", context)
        let a1 = row("A", order: 0, index: 0, in: session, context: context)
        let a2 = row("A", order: 0, index: 1, in: session, context: context)
        try context.save()

        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.complete(a1, restSeconds: nil, at: t0)
        workout.continueSet(a1)
        let first = card("A", of: session)[1]
        workout.complete(first, restSeconds: nil, at: t0.addingTimeInterval(30))
        workout.continueSet(first)
        let second = card("A", of: session)[2]
        workout.complete(second, restSeconds: nil, at: t0.addingTimeInterval(60))
        workout.complete(a2, restSeconds: nil, at: t0.addingTimeInterval(240))
        check(first.isContinuation && second.isContinuation && a2.setIndex == 3,
              "The run must be the set, two drops, then the next working set")

        workout.uncomplete(a1)

        check(isErased(a1) && isErased(first) && isErased(second),
              "Every logged drop in the run must be taken back with the set")
        check(a2.isCompleted, "The next working set is not part of the effort and must stay logged")
    }

    @MainActor static func undoOfADropTakesOnlyWhatContinuesIt(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_800)
        let session = session("Middle drop", context)
        let a1 = row("A", order: 0, index: 0, in: session, context: context)
        try context.save()

        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.complete(a1, restSeconds: nil, at: t0)
        workout.continueSet(a1)
        let first = card("A", of: session)[1]
        workout.complete(first, restSeconds: nil, at: t0.addingTimeInterval(30))
        workout.continueSet(first)
        let second = card("A", of: session)[2]
        workout.complete(second, restSeconds: nil, at: t0.addingTimeInterval(60))

        workout.uncomplete(first)

        check(a1.isCompleted, "The set a drop came off must stay logged when only the drop is undone")
        check(isErased(first) && isErased(second), "The drop below the undone drop must go with it")
    }

    @MainActor static func repeatedUndoKeepsALaterLift(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_800)
        let session = session("Repeated undo", context)
        let a1 = row("A", order: 0, index: 0, in: session, context: context)
        try context.save()

        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.complete(a1, restSeconds: nil, at: t0)
        workout.continueSet(a1)
        let drop = card("A", of: session)[1]
        workout.uncomplete(a1)
        // Logged on its own after the set above was taken back: a lift the
        // lifter chose to keep, which a second undo of an unlogged set must
        // not reach.
        workout.complete(drop, restSeconds: nil, at: t0.addingTimeInterval(60))
        workout.uncomplete(a1)

        check(drop.isCompleted, "An undo of a set that is not logged must not take back a lift below it")
    }
}
