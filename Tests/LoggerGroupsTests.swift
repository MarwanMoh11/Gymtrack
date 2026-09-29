import Foundation
import SwiftData

/// LOG-12, the logger's read side. Run with scripts/test-logger-groups.sh; no
/// simulator is needed.
///
/// The logger used to ask `currentGroup` for every queue row, and each ask
/// rebuilt and sorted the session's groups, twice. It now takes the groups
/// once per pass and asks `currentGroup(in:)`. This holds the two answers
/// together through every move the current exercise can make, and shows that
/// nothing is held between passes (so no write path can leave a stale answer).
@main
struct LoggerGroupsTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let session = WorkoutSession(title: "Seven lifts")
        context.insert(session)

        let exerciseCount = 8, setsEach = 4
        for exercise in 0..<exerciseCount {
            for index in 0..<setsEach {
                let set = SetLog(catalogID: "lift-\(exercise)", exerciseName: "Lift \(exercise)",
                                 exerciseOrder: exercise, setIndex: index, weightKg: 40, reps: 8,
                                 targetRepsLow: 8, targetRepsHigh: 8, tracking: .weightReps)
                set.session = session
                context.insert(set)
            }
        }
        try context.save()
        let workout = ActiveWorkout(session: session, context: context, history: [])

        /// The rule as it stood before the change, written out over a fresh
        /// build, so the two are compared rather than each trusted.
        func reference() -> String? {
            let groups = session.exerciseGroups
            if let preferred = session.preferredExerciseID,
               let group = groups.first(where: { $0.catalogID == preferred && !$0.isComplete }) {
                return group.catalogID
            }
            return (groups.first { !$0.isComplete } ?? groups.last)?.catalogID
        }
        func agree(_ what: String) {
            let groups = workout.groups
            let once = workout.currentGroup(in: groups)
            precondition(once?.catalogID == reference(), "\(what): currentGroup(in:) diverged from the rule")
            precondition(workout.currentGroup?.catalogID == once?.catalogID, "\(what): currentGroup diverged")
            if let once {
                let next = once.sets.first { !$0.isCompleted }
                precondition(workout.nextSetNumber(in: once) == workout.nextSetNumber, "\(what): set number diverged")
                precondition(workout.nextSet?.id == next?.id, "\(what): next set diverged")
                precondition(workout.currentSetTotal == once.effortCount, "\(what): total diverged")
            }
        }

        agree("fresh session")
        precondition(workout.currentGroup?.catalogID == "lift-0")

        // A pick out of order.
        session.preferredExerciseID = "lift-3"
        agree("preferred exercise")
        precondition(workout.currentGroup?.catalogID == "lift-3")

        // Nothing is remembered between reads: finishing the preferred exercise
        // moves "current" on the very next read, with no invalidation step.
        for set in session.sets where set.catalogID == "lift-3" { set.isCompleted = true }
        agree("preferred exercise finished")
        precondition(workout.currentGroup?.catalogID == "lift-0",
                     "a finished preferred exercise is passed over on the next read")

        // A set logged, then undone, on the first exercise.
        let first = session.sets.filter { $0.catalogID == "lift-0" }.sorted { $0.setIndex < $1.setIndex }
        first[0].isCompleted = true
        agree("one set logged")
        precondition(workout.nextSetNumber == 2)
        first[0].unlog()
        agree("that set undone")
        precondition(workout.nextSetNumber == 1, "an undone set is the next one again")

        // A set added to an exercise, and an exercise finished outright.
        workout.addSet(to: workout.groups[0])
        agree("set added")
        precondition(workout.currentSetTotal == setsEach + 1)
        for set in session.sets { set.isCompleted = true }
        agree("everything logged")
        precondition(workout.currentGroup?.catalogID == "lift-\(exerciseCount - 1)",
                     "with nothing left the last exercise stays current")
        precondition(workout.upNextName == "")

        // What the change is for: one build for the pass, not one per row.
        // Timed rather than counted, because the build lives in the model;
        // the old pass asked for the groups 2N+5 times and the new one once.
        for set in session.sets { set.unlog() }
        session.preferredExerciseID = nil
        let passes = 200
        let rows = workout.groups.count
        var sink = 0
        let before = ContinuousClock().measure {
            for _ in 0..<passes {
                for _ in 0..<(2 * rows + 5) { sink &+= workout.currentGroup?.order ?? 0 }
            }
        }
        let after = ContinuousClock().measure {
            for _ in 0..<passes {
                let groups = workout.groups
                let current = workout.currentGroup(in: groups)
                for _ in 0..<rows { sink &+= current?.order ?? 0 }
            }
        }
        print("per-pass reads for \(rows) exercises x \(setsEach) sets, \(passes) passes:",
              "old shape \(before), new shape \(after) (\(sink))")
        precondition(after * 3 < before, "one build per pass should be several times cheaper than 2N+5")

        print("ok")
    }
}
