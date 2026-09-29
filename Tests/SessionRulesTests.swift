import Foundation
import SwiftData

/// Run with scripts/test-session-rules.sh.
///
/// Compiled without `ActiveWorkout.swift`, on purpose: the set-timing rules
/// and the stale-session constant have one home each, and this harness only
/// builds if that home is a file the logger is not needed for.
@main
struct SessionRulesTests {
    @MainActor static func main() throws {
        let store = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = store.mainContext
        let base = Date(timeIntervalSince1970: 1_790_000_000)

        func row(_ id: String, index: Int, in session: WorkoutSession) -> SetLog {
            let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: index,
                             weightKg: 60, reps: 8, seconds: 0,
                             targetRepsLow: 6, targetRepsHigh: 10, tracking: .weightReps)
            set.session = session
            context.insert(set)
            return set
        }

        // One stale bound, read from the snapshot the widgets use.
        precondition(WorkoutSession.staleAfter == GymTrackSnapshot.Running.staleAfter,
                     "The model must read the snapshot's stale bound, not keep its own")
        precondition(WorkoutSession.staleAfter == 12 * 3600, "A session goes stale after twelve hours")
        let old = WorkoutSession(title: "Old")
        context.insert(old)
        old.startedAt = base
        precondition(!old.isStale(at: base.addingTimeInterval(12 * 3600)), "The turn itself is not stale")
        precondition(old.isStale(at: base.addingTimeInterval(12 * 3600 + 1)))

        // The set-timing rule, called from a file the logger is not part of.
        let session = WorkoutSession(title: "Rule")
        context.insert(session)
        let sets = (0..<3).map { row("bench", index: $0, in: session) }
        sets[0].startedAt = base
        precondition(sets[0].longestPlausibleLength == 180)
        precondition(sets[0].startStillDescribes(loggedAt: base.addingTimeInterval(180)))
        precondition(!sets[0].startStillDescribes(loggedAt: base.addingTimeInterval(181)))
        session.settleStarts(afterLogging: sets[0], at: base.addingTimeInterval(200))
        precondition(sets[0].startedAt == nil, "A start no set could have filled is dropped, not shortened")

        sets[0].startedAt = base
        sets[1].startedAt = base.addingTimeInterval(-30)
        sets[2].startedAt = base.addingTimeInterval(150)
        session.settleStarts(afterLogging: sets[0], at: base.addingTimeInterval(100))
        precondition(sets[0].startedAt == base, "A start inside the bound stays")
        precondition(sets[1].startedAt == nil, "An unlogged start the log has overtaken is abandoned")
        precondition(sets[2].startedAt != nil, "A start after the log is still ahead of it")

        // `DroppedSetMemory.shared` is one object for the life of the process;
        // a test points it at its own store rather than replacing it.
        let suites = ["a", "b"].map { "com.marwanmohamed.gymtrack.tests.session-rules.\($0)" }
        let stores = suites.map { UserDefaults(suiteName: $0)! }
        for (suite, defaults) in zip(suites, stores) { defaults.removePersistentDomain(forName: suite) }
        defer { for (suite, defaults) in zip(suites, stores) { defaults.removePersistentDomain(forName: suite) } }
        let memory = DroppedSetMemory.shared
        memory.replaceStore(with: stores[0])
        let setID = UUID()
        memory.rememberTakenBack(setID, completedAt: base)
        precondition(memory.wasTakenBack(setID, loggedAt: base))
        memory.replaceStore(with: stores[1])
        precondition(DroppedSetMemory.shared === memory, "shared is a constant")
        precondition(!memory.wasTakenBack(setID, loggedAt: base), "Another store does not hold the first one's entries")

        let closing = WorkoutSession(title: "Closing")
        context.insert(closing)
        let dropped = row("squat", index: 0, in: closing)
        memory.settle(closing.id)
        memory.replaceStore(with: stores[1])
        memory.remember([DroppedSetRow(dropped, in: closing)], closing: closing.id)
        precondition(memory.row(for: dropped.id) != nil,
                     "Pointing the memory at a store forgets which sessions the wrist settled")

        print("Session rules: one start rule, one stale bound, one dropped-set memory")
    }
}
