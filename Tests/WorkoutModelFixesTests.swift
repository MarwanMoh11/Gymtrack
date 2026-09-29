import Foundation
import SwiftData

/// Run with scripts/test-workout-model-fixes.sh; no simulator is needed.
///
/// LOG-05, LOG-09, LOG-10 (SESS-06) and SESS-08 from the 2026-09-28 review,
/// and the wrist's undo applied with no logger running.
@main
struct WorkoutModelFixesTests {
    @MainActor static func main() throws {
        AppSettings.shared.restTimerAutoStart = true

        // One check can be run alone by name, to see it fail against a tree
        // without its fix: `build/workout-model-fixes/check <name>`.
        let checks: [(String, @MainActor () throws -> Void)] = [
            ("LOG-05", undoStopsOnlyTheRestItBelongsTo),
            ("LOG-09", removingAContinuationBringsBackItsRest),
            ("LOG-10-phone", startAbandonedForAnotherExerciseNeverPairsWithALaterLog),
            ("LOG-10-cap", startPastWhatTheSetCouldFillIsDropped),
            ("LOG-10-headless", headlessLogsAndStartsFollowTheSameRules),
            ("undo-headless", headlessUndoTakesTheDropsBackToo),
            ("SESS-08", deletedSessionLeavesTheRunningWorkout),
        ]
        let only = CommandLine.arguments.dropFirst().first
        for (name, check) in checks where only == nil || only == name {
            try check()
        }
        print("Rest ownership, abandoned starts, headless undo and deleted history passed")
    }

    // MARK: - Fixture

    /// A running session of three exercises, one set list each: a bench, a row
    /// and a timed hold. Built directly rather than from a plan; nothing here
    /// depends on one.
    @MainActor final class Fixture {
        let container: ModelContainer
        let context: ModelContext
        let session: WorkoutSession
        let history: [WorkoutSession]
        let bench: [SetLog]
        let row: [SetLog]
        let hold: SetLog
        lazy var workout = ActiveWorkout(session: session, context: context, history: history)

        init(history: (ModelContext) -> [WorkoutSession] = { _ in [] }) throws {
            let container = try ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
                ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
                ExerciseLoadPreference.self, HiddenExerciseRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            let session = WorkoutSession(title: "Today", startedAt: .now.addingTimeInterval(-3_600))
            context.insert(session)
            self.container = container
            self.context = context
            self.session = session
            self.history = history(context)
            bench = (0..<3).map { Fixture.makeSet("bench-test", $0, order: 0, of: session, in: context) }
            row = (0..<3).map { Fixture.makeSet("row-test", $0, order: 1, of: session, in: context) }
            hold = Fixture.makeSet("hold-test", 0, order: 2, of: session, in: context,
                                   tracking: .duration, seconds: 300)
            try context.save()
        }

        @discardableResult
        static func makeSet(_ catalogID: String, _ index: Int, order: Int, of session: WorkoutSession,
                            in context: ModelContext, weight: Double = 50, reps: Int = 10,
                            tracking: TrackingMode = .weightReps, seconds: Int = 0) -> SetLog {
            let set = SetLog(catalogID: catalogID, exerciseName: catalogID, exerciseOrder: order,
                             setIndex: index, weightKg: weight, reps: tracking == .duration ? 0 : reps,
                             seconds: seconds, targetRepsLow: reps, targetRepsHigh: reps,
                             tracking: tracking)
            set.session = session
            context.insert(set)
            return set
        }
    }

    static func ago(_ seconds: TimeInterval) -> Date { .now.addingTimeInterval(-seconds) }

    // MARK: - LOG-05

    /// Undoing a set stopped the running rest whichever set it belonged to.
    @MainActor static func undoStopsOnlyTheRestItBelongsTo() throws {
        let f = try Fixture()
        let workout = f.workout
        workout.complete(f.bench[0], restSeconds: 120)
        workout.complete(f.bench[1], restSeconds: 120)
        workout.complete(f.row[0], restSeconds: 120)
        let rowRest = workout.restTimer.endsAt
        precondition(rowRest != nil, "The row's rest is running")

        workout.uncomplete(f.bench[0])
        precondition(!f.bench[0].isCompleted)
        precondition(workout.restTimer.endsAt == rowRest,
                     "Undoing an earlier exercise's set leaves the rest that is running")

        workout.uncomplete(f.row[0])
        precondition(!workout.restTimer.isRunning, "Undoing the set whose rest it is stops it")

        // The drop below is taken back with its parent, and a rest that was the
        // drop's goes with it.
        let g = try Fixture()
        g.workout.complete(g.bench[0], restSeconds: 120)
        g.workout.continueSet(g.bench[0])
        let drop = g.session.sets.first { $0.isContinuation }!
        g.workout.complete(drop, restSeconds: 120)
        precondition(g.workout.restTimer.isRunning)
        g.workout.uncomplete(g.bench[0])
        precondition(!drop.isCompleted && !g.bench[0].isCompleted)
        precondition(!g.workout.restTimer.isRunning,
                     "The rest of a drop undone with its parent stops")

        // And when another exercise has logged since, the drop's undo is not
        // that exercise's rest.
        let h = try Fixture()
        h.workout.complete(h.bench[0], restSeconds: 120)
        h.workout.continueSet(h.bench[0])
        let dropH = h.session.sets.first { $0.isContinuation }!
        h.workout.complete(dropH, restSeconds: 120)
        h.workout.complete(h.row[0], restSeconds: 45)
        let rowRestH = h.workout.restTimer.endsAt
        h.workout.uncomplete(h.bench[0])
        precondition(!dropH.isCompleted)
        precondition(h.workout.restTimer.endsAt == rowRestH,
                     "A rest that began after the undone rows is not theirs to stop")
    }

    // MARK: - LOG-09

    /// `continueSet` stops the rest and `removeContinuation` did not put it back.
    @MainActor static func removingAContinuationBringsBackItsRest() throws {
        let f = try Fixture()
        let workout = f.workout
        workout.complete(f.bench[0], restSeconds: 120)
        let before = workout.restTimer.endsAt
        precondition(before != nil)
        workout.continueSet(f.bench[0])
        precondition(!workout.restTimer.isRunning, "Continuing stops the rest")
        let row = f.session.sets.first { $0.isContinuation }!
        workout.removeContinuation(row)
        precondition(workout.restTimer.endsAt == before && workout.restTimer.totalSeconds == 120,
                     "The mis-tap costs nothing, the countdown included")

        // A newer rest is not overwritten by the old one.
        let g = try Fixture()
        g.workout.complete(g.bench[0], restSeconds: 120)
        g.workout.continueSet(g.bench[0])
        let rowG = g.session.sets.first { $0.isContinuation }!
        g.workout.complete(g.row[0], restSeconds: 30)
        let newer = g.workout.restTimer.endsAt
        g.workout.removeContinuation(rowG)
        precondition(g.workout.restTimer.endsAt == newer && g.workout.restTimer.totalSeconds == 30,
                     "Removing the row leaves the rest that has started since")

        // Nor is a rest revived for a set that has been taken back.
        let h = try Fixture()
        h.workout.complete(h.bench[0], restSeconds: 120)
        h.workout.continueSet(h.bench[0])
        let rowH = h.session.sets.first { $0.isContinuation }!
        h.workout.uncomplete(h.bench[0])
        h.workout.removeContinuation(rowH)
        precondition(!h.workout.restTimer.isRunning,
                     "The rest of a set that was undone stays gone")
    }

    // MARK: - LOG-10 / SESS-06, phone

    @MainActor static func startAbandonedForAnotherExerciseNeverPairsWithALaterLog() throws {
        // Moving to another exercise drops the start; staying keeps it.
        let f = try Fixture()
        f.workout.announceStart(f.bench[0], at: ago(1_500))
        precondition(f.bench[0].startedAt != nil)
        f.workout.focus(on: "bench-test")
        precondition(f.bench[0].startedAt != nil, "Focusing the same exercise keeps its start")
        f.workout.focus(on: "row-test")
        precondition(f.bench[0].startedAt == nil, "Moving to the rows abandons the bench start")

        // Logging another exercise's set overtakes it, even with no focus in
        // between and a gap short enough for the length bound to allow.
        let g = try Fixture()
        g.workout.announceStart(g.bench[0], at: ago(100))
        g.workout.complete(g.row[0], restSeconds: nil, at: ago(50))
        precondition(g.bench[0].startedAt == nil, "A later log of another set overtakes the start")
        g.workout.complete(g.bench[0], restSeconds: nil)
        precondition(g.bench[0].startedAt == nil && g.bench[0].timeUnderTension == nil,
                     "The bench set carries no time under tension")

        // A start announced later than another set's is the only one under way.
        let h = try Fixture()
        h.workout.announceStart(h.bench[0], at: ago(100))
        h.workout.announceStart(h.row[0], at: ago(30))
        precondition(h.bench[0].startedAt == nil && h.row[0].startedAt != nil)

        // The rest an abandoned start cut short is not put back by a late cancel.
        let i = try Fixture()
        i.workout.complete(i.row[2], restSeconds: 120)
        i.workout.announceStart(i.bench[0], at: ago(10))
        precondition(!i.workout.restTimer.isRunning, "Announcing stops the rest")
        i.workout.focus(on: "row-test")
        i.workout.cancelStart(i.bench[0])
        precondition(!i.workout.restTimer.isRunning, "A start already dropped restores nothing")

        // A start that is still the set's own is untouched: a set logged after
        // a plausible interval keeps both stamps.
        let j = try Fixture()
        j.workout.announceStart(j.bench[0], at: ago(60))
        j.workout.complete(j.bench[0], restSeconds: nil)
        precondition(j.bench[0].startedAt != nil, "A plausible start stays")
        let tension = j.bench[0].timeUnderTension ?? 0
        precondition(tension > 55 && tension < 65, "and gives the set its length")
    }

    /// The cap is relative to the set.
    @MainActor static func startPastWhatTheSetCouldFillIsDropped() throws {
        let f = try Fixture()
        f.workout.announceStart(f.bench[0], at: ago(1_500))
        f.workout.complete(f.bench[0], restSeconds: nil)
        precondition(f.bench[0].startedAt == nil && f.bench[0].timeUnderTension == nil,
                     "A 25 minute gap is not a set")

        f.workout.announceStart(f.bench[1], at: ago(400))
        f.workout.complete(f.bench[1], restSeconds: nil)
        precondition(f.bench[1].startedAt == nil, "Ten reps do not take nearly seven minutes")

        // The same gap before a five minute hold is believable.
        f.workout.announceStart(f.hold, at: ago(400))
        f.workout.complete(f.hold, restSeconds: nil)
        precondition(f.hold.startedAt != nil && f.hold.timeUnderTension != nil,
                     "A five minute hold can take that long")

        // And a start that only just stays inside the bound is kept.
        let g = try Fixture()
        g.workout.announceStart(g.bench[0], at: ago(170))
        g.workout.complete(g.bench[0], restSeconds: nil)
        precondition(g.bench[0].startedAt != nil)
    }

    // MARK: - LOG-10 / SESS-06, headless

    @MainActor static func fetchSets(_ container: ModelContainer) throws -> [String: [SetLog]] {
        let sets = try ModelContext(container).fetch(FetchDescriptor<SetLog>())
        return Dictionary(grouping: sets.sorted { $0.setIndex < $1.setIndex }, by: \.catalogID)
    }

    @MainActor static func headlessLogsAndStartsFollowTheSameRules() throws {
        let f = try Fixture()
        WatchCommandCenter.shared.configure(container: f.container)
        let center = WatchCommandCenter.shared

        // Abandoned for the rows, logged from the wrist after the detour.
        center.handle(.announceStart(id: f.bench[0].id, at: ago(100)))
        center.handle(.logSet(id: f.row[0].id, weightKg: 50, reps: 10, seconds: 0, at: ago(50)))
        center.handle(.logSet(id: f.bench[0].id, weightKg: 50, reps: 10, seconds: 0, at: .now))
        var sets = try fetchSets(f.container)
        precondition(sets["bench-test"]![0].isCompleted && sets["row-test"]![0].isCompleted)
        precondition(sets["bench-test"]![0].startedAt == nil,
                     "A later log of another set overtakes the start on the headless path too")

        // Too long for one set.
        center.handle(.announceStart(id: f.bench[1].id, at: ago(1_500)))
        center.handle(.logSet(id: f.bench[1].id, weightKg: 50, reps: 10, seconds: 0, at: .now))
        sets = try fetchSets(f.container)
        precondition(sets["bench-test"]![1].isCompleted && sets["bench-test"]![1].startedAt == nil,
                     "A start too old for the set is dropped, not clamped")

        // A start that fits is kept.
        center.handle(.announceStart(id: f.bench[2].id, at: ago(60)))
        center.handle(.logSet(id: f.bench[2].id, weightKg: 50, reps: 10, seconds: 0, at: .now))
        sets = try fetchSets(f.container)
        precondition(sets["bench-test"]![2].startedAt != nil && sets["bench-test"]![2].timeUnderTension != nil)

        // Only one start stands.
        center.handle(.announceStart(id: f.row[1].id, at: ago(100)))
        center.handle(.announceStart(id: f.row[2].id, at: ago(30)))
        sets = try fetchSets(f.container)
        precondition(sets["row-test"]![1].startedAt == nil && sets["row-test"]![2].startedAt != nil,
                     "A later announcement supersedes an earlier one")
    }

    // MARK: - Follow-up: the wrist's undo takes the drops back

    @MainActor static func headlessUndoTakesTheDropsBackToo() throws {
        let f = try Fixture()
        let logged = ago(300)
        for (offset, set) in f.bench.prefix(3).enumerated() {
            set.isCompleted = true
            set.completedAt = logged.addingTimeInterval(TimeInterval(offset * 20))
            set.rpe = 8
        }
        f.bench[1].continuesPreviousSet = true
        f.bench[1].startedAt = logged.addingTimeInterval(5)
        try f.context.save()

        WatchCommandCenter.shared.configure(container: f.container)
        WatchCommandCenter.shared.handle(.undoSet(id: f.bench[0].id, completedAt: f.bench[0].completedAt))

        let sets = try fetchSets(f.container)["bench-test"]!
        precondition(!sets[0].isCompleted && sets[0].rpe == nil)
        precondition(!sets[1].isCompleted && sets[1].completedAt == nil
                     && sets[1].rpe == nil && sets[1].startedAt == nil,
                     "The logged drop beneath the set goes with it")
        precondition(sets[1].isContinuation, "The row keeps being a continuation")
        precondition(sets[2].isCompleted, "A set that isn't a continuation is not this undo's to take back")
    }

    // MARK: - SESS-08

    @MainActor static func pastSession(daysAgo: Int, benchKg: Double, in context: ModelContext) -> WorkoutSession {
        let past = WorkoutSession(title: "Past", startedAt: .now.addingTimeInterval(-86_400 * Double(daysAgo)))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        context.insert(past)
        for index in 0..<3 {
            let set = Fixture.makeSet("bench-test", index, order: 0, of: past, in: context,
                                      weight: benchKg, reps: 5)
            set.isCompleted = true
            set.completedAt = past.endedAt
        }
        return past
    }

    @MainActor static func deletedSessionLeavesTheRunningWorkout() throws {
        var typo: WorkoutSession!
        let f = try Fixture(history: { context in
            let older = pastSession(daysAgo: 14, benchKg: 60, in: context)
            typo = pastSession(daysAgo: 7, benchKg: 500, in: context)
            return [older, typo]
        })
        let workout = f.workout
        precondition(workout.lastPerformance(for: "bench-test").first?.weightKg == 500)

        // A first set logged builds the record baseline, 500 kg in it.
        f.bench[0].weightKg = 40
        f.bench[0].reps = 5
        workout.complete(f.bench[0], restSeconds: nil)
        precondition(!workout.isPR(f.bench[0]))

        f.context.delete(typo)
        try f.context.save()
        precondition(typo.modelContext == nil, "The delete is saved")

        precondition(workout.lastPerformance(for: "bench-test").first?.weightKg == 60,
                     "The hint falls back to the session that is still there")
        f.bench[1].weightKg = 100
        f.bench[1].reps = 5
        workout.complete(f.bench[1], restSeconds: nil)
        precondition(workout.isPR(f.bench[1]),
                     "The record to beat no longer includes the deleted session")
    }
}
