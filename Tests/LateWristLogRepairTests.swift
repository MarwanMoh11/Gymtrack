import Foundation
import SwiftData

/// Run with scripts/test-late-wrist-log-repairs.sh; no simulator is needed.
///
/// What was left over once late wrist logs came back: a headless focus and a
/// Finish batch that ignored the rules for a set's start, starts stored before
/// those rules, a Health workout dropped with its session, a set the phone
/// undid coming back with the wrist's Finish, and a re-log lost behind its own
/// undo. Each is driven through the command center as the wrist drives it.
@main
struct LateWristLogRepairTests {

    @MainActor static func main() throws {
        let suite = "com.marwanmohamed.gymtrack.tests.late-wrist-log-repairs"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        DroppedSetMemory.shared.replaceStore(with: defaults)

        let now = Date.now
        let center = WatchCommandCenter.shared

        func makeStore() throws -> ModelContainer {
            try ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
                ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
                ExerciseLoadPreference.self, HiddenExerciseRecord.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
        }

        func row(_ id: String, order: Int, index: Int, in session: WorkoutSession,
                 context: ModelContext) -> SetLog {
            let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: order, setIndex: index,
                             weightKg: 60, reps: 8, seconds: 0,
                             targetRepsLow: 6, targetRepsHigh: 10, tracking: .weightReps)
            set.session = session
            context.insert(set)
            return set
        }

        func stored(_ id: UUID, in container: ModelContainer) -> SetLog? {
            ((try? ModelContext(container).fetch(FetchDescriptor<SetLog>())) ?? []).first { $0.id == id }
        }

        func log(_ id: UUID, weightKg: Double = 62.5, reps: Int = 9, at moment: Date?) -> WatchCommand {
            .logSet(id: id, weightKg: weightKg, reps: reps, seconds: 0, at: moment)
        }

        func pending(_ id: UUID, at moment: Date, weightKg: Double = 62.5, reps: Int = 9) -> WatchPendingLog {
            WatchPendingLog(setID: id, weightKg: weightKg, reps: reps, seconds: 0, completedAt: moment)
        }

        func batch(_ session: UUID, logs: [WatchPendingLog] = [], undos: Set<UUID> = [],
                   starts: [UUID: Date] = [:]) -> WatchFinishBatch {
            WatchFinishBatch(sessionID: session, logs: logs, undos: undos, starts: starts,
                             cancels: [], ratings: [])
        }

        // A headless focus onto another exercise drops the start announced on
        // this one, as the logger's own does; a focus on nothing known does not.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Focus")
            context.insert(session)
            let bench = row("bench", order: 0, index: 0, in: session, context: context)
            let squat = row("squat", order: 1, index: 0, in: session, context: context)
            bench.startedAt = now.addingTimeInterval(-60)
            try context.save()
            center.configure(container: store)

            center.applyHeadless(.focusExercise(catalogID: "deadlift"))
            precondition(bench.startedAt != nil, "A focus on an exercise the session lacks moves nothing")
            center.applyHeadless(.focusExercise(catalogID: "squat"))
            precondition(bench.startedAt == nil, "Moving on abandons the start announced elsewhere")
            squat.startedAt = now.addingTimeInterval(-30)
            center.applyHeadless(.focusExercise(catalogID: "squat"))
            precondition(squat.startedAt != nil, "Focusing where the set already is keeps its start")
        }

        // A Finish batch holds the starts it replays to the live rules.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Batch")
            context.insert(session)
            let slow = row("bench", order: 0, index: 0, in: session, context: context)
            let quick = row("bench", order: 0, index: 1, in: session, context: context)
            let abandoned = row("squat", order: 1, index: 0, in: session, context: context)
            let survivor = row("squat", order: 1, index: 1, in: session, context: context)
            try context.save()
            let slowLog = now.addingTimeInterval(-600)
            let quickLog = now.addingTimeInterval(-400)
            let b = batch(session.id,
                          logs: [pending(slow.id, at: slowLog), pending(quick.id, at: quickLog)],
                          starts: [slow.id: slowLog.addingTimeInterval(-1200),
                                   quick.id: quickLog.addingTimeInterval(-70),
                                   abandoned.id: now.addingTimeInterval(-900),
                                   survivor.id: now.addingTimeInterval(-100)])
            session.applyWatchFinish(b)
            precondition(slow.isCompleted && slow.startedAt == nil,
                         "A start twenty minutes before its log is not a set's length, and is dropped")
            precondition(quick.startedAt == quickLog.addingTimeInterval(-70),
                         "A start a set could have filled stays")
            precondition(abandoned.startedAt == nil,
                         "A start another set's later log overtook is dropped, as it is when live")
            precondition(survivor.startedAt == now.addingTimeInterval(-100),
                         "The set under way when the batch was sent keeps its start")
        }

        // The same, through a session the phone closed first, both for a row a
        // live late log puts back and for one the batch does.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Closed")
            context.insert(session)
            let kept = row("bench", order: 0, index: 0, in: session, context: context)
            kept.isCompleted = true
            kept.completedAt = now.addingTimeInterval(-900)
            let liveLate = row("bench", order: 0, index: 1, in: session, context: context)
            let batchLate = row("bench", order: 0, index: 2, in: session, context: context)
            liveLate.startedAt = now.addingTimeInterval(-1700)
            batchLate.startedAt = now.addingTimeInterval(-1600)
            try context.save()
            let ids = (live: liveLate.id, batch: batchLate.id, session: session.id)
            session.close(at: now.addingTimeInterval(-10), in: context)
            try context.save()
            center.configure(container: store)

            center.handle(log(ids.live, at: now.addingTimeInterval(-300)))
            precondition(stored(ids.live, in: store)?.isCompleted == true)
            precondition(stored(ids.live, in: store)?.startedAt == nil,
                         "A remembered start too old for the log is not put back with the row")
            center.handle(.finishSession(batch(ids.session,
                                                logs: [pending(ids.batch, at: now.addingTimeInterval(-200))],
                                                starts: [ids.batch: now.addingTimeInterval(-1600)]),
                                         metrics: nil))
            precondition(stored(ids.batch, in: store)?.isCompleted == true)
            precondition(stored(ids.batch, in: store)?.startedAt == nil,
                         "Nor is one a late batch replays")
        }

        // Starts stored before the rule existed are dropped once, and only
        // those no set could have filled.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "History")
            context.insert(session)
            let logged = now.addingTimeInterval(-3600)
            let honest = row("bench", order: 0, index: 0, in: session, context: context)
            let detour = row("bench", order: 0, index: 1, in: session, context: context)
            let backwards = row("bench", order: 0, index: 2, in: session, context: context)
            let open = row("bench", order: 0, index: 3, in: session, context: context)
            for set in [honest, detour, backwards] { set.isCompleted = true; set.completedAt = logged }
            honest.startedAt = logged.addingTimeInterval(-90)
            detour.startedAt = logged.addingTimeInterval(-1500)
            backwards.startedAt = logged.addingTimeInterval(30)
            open.startedAt = now.addingTimeInterval(-3000)
            try context.save()

            let once = UserDefaults(suiteName: suite + ".once")!
            once.removePersistentDomain(forName: suite + ".once")
            defer { once.removePersistentDomain(forName: suite + ".once") }
            center.repairStoredStartsOnce(in: context, defaults: once)
            precondition(honest.startedAt == logged.addingTimeInterval(-90), "A believable start is untouched")
            precondition(detour.startedAt == nil, "A start too old for its log is dropped, not shortened")
            precondition(backwards.startedAt == nil, "A start after its own log is dropped")
            precondition(open.startedAt != nil, "A set still open is not the repair's to judge")
            precondition(detour.isCompleted && detour.completedAt == logged, "Nothing but the start changes")

            detour.startedAt = logged.addingTimeInterval(-1500)
            center.repairStoredStartsOnce(in: context, defaults: once)
            precondition(detour.startedAt != nil, "The repair runs once")
            precondition(SetLog.dropImplausibleStoredStarts(in: context) == 1, "Run directly it finds the same rows")
        }

        // A Health workout for a session that is gone is queued by Finish too.
        do {
            let store = try makeStore()
            center.configure(container: store)
            let health = HealthKitService.shared
            let before = health.orphanWorkouts.count
            let finishWorkout = UUID(), batchWorkout = UUID()
            var metrics = WatchWorkoutMetrics(sessionID: UUID(), healthWorkoutID: finishWorkout)
            center.applyHeadless(.finish(metrics: metrics))
            precondition(health.orphanWorkouts.suffix(1) == [finishWorkout], "A Finish for a deleted session queues its workout")
            let gone = UUID()
            metrics = WatchWorkoutMetrics(sessionID: gone, healthWorkoutID: batchWorkout)
            center.applyHeadless(.finishSession(batch(gone), metrics: metrics))
            precondition(health.orphanWorkouts.suffix(1) == [batchWorkout], "So does a Finish batch")
            center.applyHeadless(.finishSession(batch(gone), metrics: WatchWorkoutMetrics(sessionID: gone)))
            precondition(health.orphanWorkouts.count == before + 2, "No workout, nothing to queue")
        }

        // A phone undo, then the wrist's Finish: the batch still holds the log
        // the phone took and the lifter took back, and must not return it. A
        // log the phone never heard, in the same batch, still lands.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Undo then finish")
            context.insert(session)
            let undone = row("bench", order: 0, index: 0, in: session, context: context)
            let unheard = row("bench", order: 0, index: 1, in: session, context: context)
            let heardAt = now.addingTimeInterval(-300)
            try context.save()
            let ids = (undone: undone.id, unheard: unheard.id, session: session.id)
            center.configure(container: store)

            center.handle(log(ids.undone, at: heardAt))
            precondition(undone.isCompleted, "The phone took the wrist's log")
            undone.unlog()
            try context.save()
            center.handle(.finishSession(batch(ids.session,
                                                logs: [pending(ids.undone, at: heardAt),
                                                       pending(ids.unheard, at: now.addingTimeInterval(-200))]),
                                         metrics: nil))
            precondition(stored(ids.undone, in: store) == nil,
                         "A set the phone took back stays taken back through the wrist's Finish")
            precondition(stored(ids.unheard, in: store)?.isCompleted == true,
                         "A log the phone never heard still lands")
        }

        // The same after the phone's own Finish closed the session: the row it
        // dropped as unlogged is not owed to a copy of a log it already had,
        // whether that copy comes as a batch or as a queued log.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Undo, phone finish")
            context.insert(session)
            let undone = row("bench", order: 0, index: 0, in: session, context: context)
            let unheard = row("bench", order: 0, index: 1, in: session, context: context)
            let heardAt = now.addingTimeInterval(-300)
            try context.save()
            let ids = (undone: undone.id, unheard: unheard.id, session: session.id)
            center.configure(container: store)

            center.handle(log(ids.undone, at: heardAt))
            undone.unlog()
            session.close(at: now.addingTimeInterval(-10), in: context)
            try context.save()
            precondition(DroppedSetMemory.shared.row(for: ids.undone) != nil, "The undone row was dropped at the close")

            center.handle(log(ids.undone, at: heardAt))
            precondition(stored(ids.undone, in: store) == nil, "A queued copy of a log the phone had does not restore it")
            center.handle(.finishSession(batch(ids.session,
                                                logs: [pending(ids.undone, at: heardAt),
                                                       pending(ids.unheard, at: now.addingTimeInterval(-200))]),
                                         metrics: nil))
            precondition(stored(ids.undone, in: store) == nil, "Nor does a late Finish batch")
            precondition(stored(ids.unheard, in: store)?.isCompleted == true,
                         "A lift the phone never heard is still put back")
        }

        // Log, undo and re-log, all late, in either order of the first two.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Late trio")
            context.insert(session)
            let inOrder = row("bench", order: 0, index: 0, in: session, context: context)
            let overtaken = row("bench", order: 0, index: 1, in: session, context: context)
            let legacy = row("bench", order: 0, index: 2, in: session, context: context)
            try context.save()
            let ids = (inOrder: inOrder.id, overtaken: overtaken.id, legacy: legacy.id)
            session.close(at: now.addingTimeInterval(-10), in: context)
            try context.save()
            center.configure(container: store)
            let first = now.addingTimeInterval(-300), second = now.addingTimeInterval(-200)

            center.handle(log(ids.inOrder, weightKg: 60, at: first))
            precondition(stored(ids.inOrder, in: store)?.isCompleted == true)
            center.handle(.undoSet(id: ids.inOrder, completedAt: first))
            precondition(stored(ids.inOrder, in: store) == nil)
            center.handle(log(ids.inOrder, weightKg: 60, at: first))
            precondition(stored(ids.inOrder, in: store) == nil, "The log that was taken back stays taken back")
            center.handle(log(ids.inOrder, weightKg: 65, at: second))
            precondition(stored(ids.inOrder, in: store)?.weightKg == 65, "The re-log is not lost behind its undo")
            precondition(stored(ids.inOrder, in: store)?.completedAt == second)

            center.handle(.undoSet(id: ids.overtaken, completedAt: first))
            center.handle(log(ids.overtaken, weightKg: 60, at: first))
            precondition(stored(ids.overtaken, in: store) == nil, "An undo that overtook its log still wins")
            center.handle(log(ids.overtaken, weightKg: 65, at: second))
            precondition(stored(ids.overtaken, in: store)?.completedAt == second,
                         "And the re-log after it lands")

            center.handle(.undoSet(id: ids.legacy))
            center.handle(log(ids.legacy, at: first))
            precondition(stored(ids.legacy, in: store) == nil, "An undo with no stamp still takes the row with it")
        }

        // The start rules have one copy, in SessionClosing, which the logger and
        // the replay both call. This pins the cap and the overtaken rule to
        // literal numbers, so a change to either fails here and not silently
        // in both paths at once.
        do {
            let store = try makeStore()
            let context = store.mainContext
            let session = WorkoutSession(title: "Rule")
            context.insert(session)
            let base = now.addingTimeInterval(-3600)
            for (tracking, amount, bound) in [(TrackingMode.weightReps, 1, 180.0), (.weightReps, 12, 180),
                                              (.weightReps, 18, 240), (.weightReps, 30, 360),
                                              (.duration, 10, 180), (.duration, 45, 180),
                                              (.duration, 120, 300)] {
                let set = SetLog(catalogID: "x", exerciseName: "x", exerciseOrder: 0, setIndex: 0,
                                 weightKg: 0, reps: tracking == .duration ? 0 : amount,
                                 seconds: tracking == .duration ? amount : 0,
                                 targetRepsLow: 1, targetRepsHigh: 1, tracking: tracking)
                set.session = session
                context.insert(set)
                precondition(set.longestPlausibleLength == bound,
                             "The cap for \(tracking) \(amount) is \(set.longestPlausibleLength), not \(bound)")
                for (length, fits) in [(-5.0, false), (0, true), (bound, true), (bound + 1, false)] {
                    set.startedAt = base
                    precondition(set.startStillDescribes(loggedAt: base.addingTimeInterval(length)) == fits,
                                 "\(tracking) \(amount): a start \(length)s before the log should\(fits ? "" : " not") describe it")
                }
                set.startedAt = nil
                precondition(!set.startStillDescribes(loggedAt: base))
            }
            try context.save()

            let sets = (0..<4).map { row("bench", order: 0, index: $0, in: session, context: context) }
            sets[0].startedAt = base.addingTimeInterval(-50)
            sets[1].startedAt = base.addingTimeInterval(10)
            sets[2].isCompleted = true
            sets[2].startedAt = base.addingTimeInterval(-20)
            let dropped = session.dropOvertakenStarts(besides: sets[3], at: base)
            precondition(dropped == [sets[0].id], "Only the unlogged start before the log was overtaken")
            precondition(sets.map { $0.startedAt != nil } == [false, true, true, false],
                         "A later start and a logged set's own start are left alone")
        }

        print("Late wrist log repairs: focus and batch starts, stored starts, orphans, phone undo, re-log")
    }
}
