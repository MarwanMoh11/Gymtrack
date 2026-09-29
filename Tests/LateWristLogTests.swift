import Foundation
import SwiftData

/// Run with scripts/test-late-wrist-logs.sh; no simulator is needed.
///
/// A Finish on the phone deletes the rows nobody logged, and a set the wrist
/// logged out of range is such a row until its message lands. These check that
/// the message, landing after the close, puts the lift back rather than being
/// dropped — and that nothing else comes back with it.
@main
struct LateWristLogTests {

    /// The rows of one session, by ID, captured before `close` deletes some of
    /// them: a deleted model cannot be read afterwards.
    struct Rows {
        let session: UUID
        let logged: UUID
        let press: UUID
        let drop: UUID
        let plank: UUID
        let spare: UUID
    }

    @MainActor static func main() throws {
        let suite = "com.marwanmohamed.gymtrack.tests.late-wrist-logs"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        DroppedSetMemory.shared.replaceStore(with: defaults)

        let end = Date.now.addingTimeInterval(-10)
        let center = WatchCommandCenter.shared

        func makeStore() throws -> ModelContainer {
            try ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
                ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
                ExerciseLoadPreference.self, HiddenExerciseRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }

        func row(_ id: String, order: Int, index: Int, tracking: TrackingMode,
                 seconds: Int = 0, in session: WorkoutSession, context: ModelContext) -> SetLog {
            let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: order, setIndex: index,
                             weightKg: 60, reps: 8, seconds: seconds,
                             targetRepsLow: 6, targetRepsHigh: 10, tracking: tracking)
            set.session = session
            context.insert(set)
            return set
        }

        /// A session one set in, with the rest of the prescription untouched
        /// as far as the phone knows, closed by the phone's Finish.
        func closedSession(in container: ModelContainer) throws -> Rows {
            let context = ModelContext(container)
            let session = WorkoutSession(title: "Phone finish")
            context.insert(session)
            let logged = row("bench", order: 0, index: 0, tracking: .weightReps, in: session, context: context)
            logged.isCompleted = true
            logged.completedAt = end.addingTimeInterval(-600)
            let press = row("bench", order: 0, index: 1, tracking: .weightReps, in: session, context: context)
            press.startedAt = end.addingTimeInterval(-300)
            let drop = row("bench", order: 0, index: 2, tracking: .weightReps, in: session, context: context)
            drop.continuesPreviousSet = true
            let spare = row("bench", order: 0, index: 3, tracking: .weightReps, in: session, context: context)
            let plank = row("plank", order: 1, index: 0, tracking: .duration, seconds: 45,
                            in: session, context: context)
            try context.save()
            let rows = Rows(session: session.id, logged: logged.id, press: press.id,
                            drop: drop.id, plank: plank.id, spare: spare.id)
            session.close(at: end, in: context)
            try context.save()
            return rows
        }

        func stored(_ id: UUID, in container: ModelContainer) -> SetLog? {
            let rows = (try? ModelContext(container).fetch(FetchDescriptor<SetLog>())) ?? []
            return rows.first { $0.id == id }
        }

        func log(_ id: UUID, weightKg: Double = 62.5, reps: Int = 9, seconds: Int = 0,
                 at moment: Date?) -> WatchCommand {
            .logSet(id: id, weightKg: weightKg, reps: reps, seconds: seconds, at: moment)
        }

        // A late log through the headless path puts the row back, logged with
        // the wrist's values and moment, and shaped as it was.
        do {
            let store = try makeStore()
            let rows = try closedSession(in: store)
            precondition(stored(rows.press, in: store) == nil, "Close deletes the untouched rows")
            center.configure(container: store)

            center.handle(log(rows.press, at: end.addingTimeInterval(-240)))
            guard let press = stored(rows.press, in: store) else {
                preconditionFailure("A wrist log landing after the phone's Finish must put its set back")
            }
            precondition(press.session?.id == rows.session && press.isCompleted)
            precondition(press.completedAt == end.addingTimeInterval(-240), "The wrist's moment, not arrival")
            precondition(press.weightKg == 62.5 && press.reps == 9 && press.seconds == 0)
            precondition(press.trackingRaw == TrackingMode.weightReps.rawValue)
            precondition(press.setIndex == 1 && press.exerciseOrder == 0 && press.catalogID == "bench")
            precondition(press.targetRepsLow == 6 && press.targetRepsHigh == 10)
            precondition(press.startedAt == end.addingTimeInterval(-300), "The announced start comes back with it")
            precondition(press.rpe == nil && !press.hasHeartRate, "Nothing the wrist didn't send is invented")

            center.handle(log(rows.drop, weightKg: 45, reps: 6, at: end.addingTimeInterval(-200)))
            precondition(stored(rows.drop, in: store)?.continuesPreviousSet == true,
                         "A drop whose parent came back is still a drop")

            center.handle(log(rows.plank, weightKg: 0, reps: 0, seconds: 50, at: end.addingTimeInterval(-100)))
            let plank = stored(rows.plank, in: store)
            precondition(plank?.seconds == 50 && plank?.trackingRaw == TrackingMode.duration.rawValue)

            center.handle(log(rows.press, weightKg: 99, at: end.addingTimeInterval(-240)))
            precondition(stored(rows.press, in: store)?.weightKg == 62.5,
                         "A repeated delivery cannot rewrite the row it put back")
            precondition(stored(rows.spare, in: store) == nil, "A row nobody lifted stays gone")

            center.handle(.rateSet(WatchSetRating(sessionID: rows.session, setID: rows.press,
                                                  completedAt: end.addingTimeInterval(-240), rpe: 8)))
            precondition(stored(rows.press, in: store)?.rpe == 8, "The closed-session rating path accepts it")

            center.handle(.undoSet(id: rows.plank))
            precondition(stored(rows.plank, in: store) == nil, "Undoing a put-back row removes it")
            center.handle(log(rows.plank, seconds: 50, at: end.addingTimeInterval(-100)))
            precondition(stored(rows.plank, in: store) == nil, "A taken-back set cannot be put back again")

            center.handle(.undoSet(id: rows.press))
            precondition(stored(rows.press, in: store) == nil)
            precondition(stored(rows.drop, in: store)?.continuesPreviousSet == nil,
                         "A drop off a set taken back is a set of its own, not a drop off the one above")

            center.handle(.undoSet(id: rows.logged))
            precondition(stored(rows.logged, in: store)?.isCompleted == true,
                         "A set the phone closed as logged is never rewritten by a queued command")
        }

        // A log stamped after the end, or not stamped at all, is not a late
        // copy of anything the session held.
        do {
            let store = try makeStore()
            let rows = try closedSession(in: store)
            center.configure(container: store)
            center.handle(log(rows.press, at: end.addingTimeInterval(5)))
            center.handle(log(rows.drop, at: nil))
            precondition(stored(rows.press, in: store) == nil, "No set after the lifter stopped")
            precondition(stored(rows.drop, in: store) == nil, "No stamp reads as now, after the end")
        }

        // The channels are unordered: an undo that overtook its log.
        do {
            let store = try makeStore()
            let rows = try closedSession(in: store)
            center.configure(container: store)
            center.handle(.undoSet(id: rows.press))
            center.handle(log(rows.press, at: end.addingTimeInterval(-240)))
            precondition(stored(rows.press, in: store) == nil, "An undo before its log leaves no trace")
        }

        // The wrist's own Finish, landing after the phone's.
        do {
            let store = try makeStore()
            let rows = try closedSession(in: store)
            center.configure(container: store)
            let batch = WatchFinishBatch(
                sessionID: rows.session,
                logs: [
                    WatchPendingLog(setID: rows.press, weightKg: 62.5, reps: 9, seconds: 0,
                                    completedAt: end.addingTimeInterval(-240)),
                    WatchPendingLog(setID: rows.drop, weightKg: 45, reps: 6, seconds: 0,
                                    completedAt: end.addingTimeInterval(-200)),
                    WatchPendingLog(setID: rows.plank, weightKg: 0, reps: 0, seconds: 50,
                                    completedAt: end.addingTimeInterval(-100)),
                ],
                undos: [rows.plank],
                starts: [rows.drop: end.addingTimeInterval(-210)],
                cancels: [],
                ratings: []
            )
            center.handle(.finishSession(batch, metrics: nil))
            let press = stored(rows.press, in: store)
            let drop = stored(rows.drop, in: store)
            precondition(press?.isCompleted == true && press?.completedAt == end.addingTimeInterval(-240),
                         "A late finish batch puts back the sets it logged")
            precondition(drop?.isCompleted == true && drop?.startedAt == end.addingTimeInterval(-210))
            precondition(stored(rows.plank, in: store) == nil, "Its undos are honoured")
            center.handle(log(rows.plank, seconds: 50, at: end.addingTimeInterval(-100)))
            precondition(stored(rows.plank, in: store) == nil, "And a queued log cannot undo the undo")
        }

        // A session deleted since has nothing left for a late log to join.
        do {
            let store = try makeStore()
            let rows = try closedSession(in: store)
            let context = ModelContext(store)
            for session in try context.fetch(FetchDescriptor<WorkoutSession>()) { context.delete(session) }
            try context.save()
            center.configure(container: store)
            center.handle(log(rows.press, at: end.addingTimeInterval(-240)))
            precondition(stored(rows.press, in: store) == nil, "A discarded session recreates nothing")
        }

        // The memory outlives the process, for a week.
        do {
            let store = try makeStore()
            let rows = try closedSession(in: store)
            DroppedSetMemory.shared.replaceStore(with: defaults)
            center.configure(container: store)
            precondition(DroppedSetMemory.shared.row(for: rows.spare, now: .now.addingTimeInterval(6 * 86400)) != nil)
            precondition(DroppedSetMemory.shared.row(for: rows.spare, now: .now.addingTimeInterval(8 * 86400)) == nil,
                         "The memory expires")
            center.handle(log(rows.press, at: end.addingTimeInterval(-240)))
            precondition(stored(rows.press, in: store)?.isCompleted == true,
                         "A relaunch between the close and the log loses nothing")
        }

        // A session the wrist's own batch finished keeps no memory: every row
        // the wrist counted was in that batch, so a later log is a stale one.
        do {
            let store = try makeStore()
            let context = ModelContext(store)
            let session = WorkoutSession(title: "Wrist finish")
            context.insert(session)
            let taken = row("bench", order: 0, index: 0, tracking: .weightReps, in: session, context: context)
            let takenID = taken.id
            try context.save()
            session.applyWatchFinish(WatchFinishBatch(sessionID: session.id, logs: [], undos: [takenID],
                                                      starts: [:], cancels: [], ratings: []))
            session.close(at: end, in: context)
            try context.save()
            precondition(DroppedSetMemory.shared.row(for: takenID) == nil)
            center.configure(container: store)
            center.handle(log(takenID, at: end.addingTimeInterval(-60)))
            precondition(stored(takenID, in: store) == nil, "The wrist's own Finish is its final word")
        }

        // With a logger on screen, an unknown set is passed on, and the path it
        // is passed to reaches the finished session and nothing else.
        do {
            let store = try makeStore()
            let rows = try closedSession(in: store)
            let context = ModelContext(store)
            let running = WorkoutSession(title: "Next workout")
            context.insert(running)
            let next = row("squat", order: 0, index: 0, tracking: .weightReps, in: running, context: context)
            try context.save()
            center.configure(container: store)
            let workout = ActiveWorkout(session: running, context: context, history: [])
            let late = log(rows.press, at: end.addingTimeInterval(-240))
            precondition(!workout.apply(late), "The logger must not swallow a set it has no row for")
            precondition(!workout.apply(.undoSet(id: rows.drop)))
            center.applyToFinishedSession(late)
            precondition(stored(rows.press, in: store)?.session?.id == rows.session)
            precondition(!next.isCompleted && running.sets.count == 1, "The running session is untouched")
        }

        print("Late wrist logs after a phone Finish passed")
    }
}
