import Foundation
import SwiftData

/// Run with scripts/test-wrist-redelivery-undo.sh; no simulator is needed.
///
/// Two loose ends of the wrist link. A wrist undo taken while the phone was
/// asleep left the load its log had carried sitting on the rows below, which
/// the phone's own undo never does. And a wrist log delivered twice after the
/// phone undid it re-completed a set nobody lifted again. Both are driven
/// through the command center as the wrist drives it.
@main
struct WristRedeliveryUndoTests {

    @MainActor static func main() throws {
        let suite = "com.marwanmohamed.gymtrack.tests.wrist-redelivery-undo"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        DroppedSetMemory.shared.replaceStore(with: defaults)

        let now = Date.now
        let center = WatchCommandCenter.shared
        center.uiHandler = nil

        func makeStore() throws -> ModelContainer {
            try ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
                ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
                ExerciseLoadPreference.self, HiddenExerciseRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }

        func rows(_ id: String, count: Int, kg: Double = 60, seconds: Int = 0,
                  tracking: TrackingMode = .weightReps, in session: WorkoutSession,
                  context: ModelContext) -> [SetLog] {
            (0..<count).map { index in
                let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: index,
                                 weightKg: kg, reps: 8, seconds: seconds,
                                 targetRepsLow: 6, targetRepsHigh: 10, tracking: tracking)
                set.session = session
                context.insert(set)
                return set
            }
        }

        func log(_ id: UUID, weightKg: Double, seconds: Int = 0, at moment: Date) -> WatchCommand {
            .logSet(id: id, weightKg: weightKg, reps: 9, seconds: seconds, at: moment)
        }

        // A wrist undo answering a wrist log puts the rows the log prefilled
        // back where they were.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Carry")
            context.insert(session)
            let bench = rows("bench", count: 4, in: session, context: context)
            try context.save()
            center.configure(container: store)

            let stamp = now.addingTimeInterval(-90)
            center.applyHeadless(log(bench[0].id, weightKg: 65, at: stamp))
            precondition(bench[1...].allSatisfy { $0.weightKg == 65 }, "The log carries its load down the card")
            center.applyHeadless(.undoSet(id: bench[0].id, completedAt: stamp))
            precondition(!bench[0].isCompleted, "The undo took the set back")
            precondition(bench[1...].allSatisfy { $0.weightKg == 60 },
                         "The rows go back to what they held; a set never lifted leaves no load behind")

            // A stale undo names a log the row does not hold: nothing is taken
            // back, so nothing is restored either.
            let second = now.addingTimeInterval(-60)
            center.applyHeadless(log(bench[0].id, weightKg: 67.5, at: second))
            precondition(bench[1...].allSatisfy { $0.weightKg == 67.5 }, "A re-log carries again")
            center.applyHeadless(.undoSet(id: bench[0].id, completedAt: second.addingTimeInterval(-30)))
            precondition(bench[0].isCompleted && bench[1...].allSatisfy { $0.weightKg == 67.5 },
                         "An undo of a log the row does not hold restores nothing")
            center.applyHeadless(.undoSet(id: bench[0].id, completedAt: second))
            precondition(bench[1...].allSatisfy { $0.weightKg == 60 }, "The re-log's own undo restores it too")
        }

        // A row the lifter has typed into since is theirs and stays as typed;
        // the rows they left alone still go back.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Typed")
            context.insert(session)
            let curl = rows("curl", count: 3, kg: 20, in: session, context: context)
            try context.save()
            center.configure(container: store)

            let stamp = now.addingTimeInterval(-45)
            center.applyHeadless(log(curl[0].id, weightKg: 22.5, at: stamp))
            curl[1].weightKg = 25
            center.applyHeadless(.undoSet(id: curl[0].id, completedAt: stamp))
            precondition(curl[1].weightKg == 25, "A weight the lifter chose is not overwritten by an undo")
            precondition(curl[2].weightKg == 20, "The row left alone goes back")

            // A log that carried nothing has nothing to restore.
            let flat = rows("row", count: 2, kg: 50, in: session, context: context)
            try context.save()
            let flatStamp = now.addingTimeInterval(-30)
            center.applyHeadless(log(flat[0].id, weightKg: 50, at: flatStamp))
            center.applyHeadless(.undoSet(id: flat[0].id, completedAt: flatStamp))
            precondition(flat[1].weightKg == 50 && !flat[0].isCompleted, "Nothing carried, nothing moved")
        }

        // A timed exercise carries its seconds as well, and gets them back.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Timed")
            context.insert(session)
            let plank = rows("plank", count: 3, kg: 0, seconds: 30, tracking: .duration,
                             in: session, context: context)
            try context.save()
            center.configure(container: store)

            let stamp = now.addingTimeInterval(-20)
            center.applyHeadless(log(plank[0].id, weightKg: 0, seconds: 45, at: stamp))
            precondition(plank[1...].allSatisfy { $0.seconds == 45 }, "The hold carries down the card")
            center.applyHeadless(.undoSet(id: plank[0].id, completedAt: stamp))
            precondition(plank[1...].allSatisfy { $0.seconds == 30 }, "The hold goes back with the undo")
        }

        // A wrist log delivered again after the phone undid it, with no logger
        // on screen, does not complete the set again or carry its load twice.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Headless again")
            context.insert(session)
            let press = rows("press", count: 3, in: session, context: context)
            try context.save()
            center.configure(container: store)

            let stamp = now.addingTimeInterval(-15)
            center.applyHeadless(log(press[0].id, weightKg: 62.5, at: stamp))
            press[0].unlog()
            center.applyHeadless(log(press[0].id, weightKg: 62.5, at: stamp))
            precondition(!press[0].isCompleted, "The same log again does not re-complete a set that was undone")
            precondition(press[1...].allSatisfy { $0.weightKg == 62.5 }, "And carries nothing further")

            center.applyHeadless(log(press[0].id, weightKg: 62.5, at: stamp.addingTimeInterval(20)))
            precondition(press[0].isCompleted, "A genuine re-log, stamped anew, is still taken")
        }

        // The same, with the logger on screen: it applies the wrist's log,
        // the lifter takes the set back on the phone, and the wrist's copy
        // arrives again.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Logger again")
            context.insert(session)
            let squat = rows("squat", count: 3, kg: 100, in: session, context: context)
            try context.save()
            center.configure(container: store)
            let workout = ActiveWorkout(session: session, context: context, history: [])
            center.uiHandler = { workout.apply($0) }
            defer { center.uiHandler = nil }

            let stamp = now.addingTimeInterval(-10)
            center.handle(log(squat[0].id, weightKg: 102.5, at: stamp))
            precondition(squat[0].isCompleted, "The logger applied the wrist's log")
            workout.uncomplete(squat[0])
            precondition(!squat[0].isCompleted, "The phone took the set back")

            center.handle(log(squat[0].id, weightKg: 102.5, at: stamp))
            precondition(!squat[0].isCompleted,
                         "A re-delivered copy of a log the phone undid must not complete the set again")
            precondition(workout.apply(log(squat[0].id, weightKg: 102.5, at: stamp)),
                         "The logger answers a heard log as handled, so nothing else is owed it")
            precondition(!squat[0].isCompleted && squat[1...].allSatisfy { $0.weightKg == 100 },
                         "Nothing was carried down the card either")

            center.handle(log(squat[0].id, weightKg: 102.5, at: stamp.addingTimeInterval(5)))
            precondition(squat[0].isCompleted, "A log stamped anew is a new lift and is applied")
        }

        print("wrist redelivery and undo checks passed")
    }
}
