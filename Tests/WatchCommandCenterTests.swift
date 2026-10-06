import Foundation
import SwiftData

/// Run with scripts/test-watch-command-center.sh; no simulator is needed.
///
/// Drives `WatchCommandCenter.applyHeadless` for the commands that change
/// data and reads the stored rows back, the way a wake in the background
/// does with no view hierarchy. `WatchSessionRecovery` is compiled for real.
@main
struct WatchCommandCenterTests {
    @MainActor static func main() async throws {
        try logRateAndUndoLeaveTheRightRows()
        try startsAndFocusAndAddSet()
        try finishKeepsWhatWasLoggedAndDiscardsWhatWasNot()
        try discardSessionDeletesOnlyTheNamedSession()
        try routingPrefersTheUIWhenOneIsAttached()
        try theHeadlessPathSharesTheMainContext()
        try untouchedOverlapIsRemovedFromAnOpenOnlyList()
        print("Watch command center headless commands, routing and single context passed")
    }

    // MARK: - Fixtures

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A configured command center over a fresh store holding a running
    /// session of three sets of one movement.
    @MainActor static func makeRunningSession() throws -> (ModelContainer, WorkoutSession) {
        let container = try makeContainer()
        let context = container.mainContext
        let plan = Plan(name: "Test plan", isActive: true)
        let day = PlanDay(name: "Push", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        let row = PlanItem(catalogID: "bench-test", name: "bench-test", order: 0,
                           targetSets: 3, targetRepsLow: 8, targetRepsHigh: 8, targetWeightKg: 50)
        row.day = day
        context.insert(row)
        let session = SessionFactory.build(day: day, plan: plan, context: context, history: [])
        session.wasWatchDriven = true
        try context.save()
        WatchCommandCenter.shared.uiHandler = nil
        WatchCommandCenter.shared.configure(container: container)
        return (container, session)
    }

    @MainActor static func stored(_ container: ModelContainer) -> [SetLog] {
        try! ModelContext(container).fetch(FetchDescriptor<SetLog>()).sorted(by: SetLog.precedesInSession)
    }

    @MainActor static func sessions(_ container: ModelContainer) -> [WorkoutSession] {
        try! ModelContext(container).fetch(FetchDescriptor<WorkoutSession>())
    }

    // MARK: - Commands

    /// A log, its effort answer and its undo. The undo has to take the answer
    /// and the start with it, and a copy of the log that was taken back and
    /// arrives afterward must not bring the set back.
    @MainActor static func logRateAndUndoLeaveTheRightRows() throws {
        let (container, session) = try makeRunningSession()
        let first = session.sets.sorted(by: SetLog.precedesInSession)[0]
        let id = first.id
        let center = WatchCommandCenter.shared
        let moment = Date.now.addingTimeInterval(-30)

        center.applyHeadless(.announceStart(id: id, at: moment.addingTimeInterval(-40)))
        precondition(stored(container)[0].startedAt != nil, "The announced start is stored")
        center.applyHeadless(.cancelStart(id: id))
        precondition(stored(container)[0].startedAt == nil,
                     "A cancelled start leaves no key behind")

        center.applyHeadless(.logSet(id: id, weightKg: 60, reps: 8, seconds: 0, at: moment))
        var rows = stored(container)
        precondition(rows[0].isCompleted && rows[0].weightKg == 60 && rows[0].reps == 8,
                     "The log lands on the row it named")
        precondition(rows[0].completedAt.map { WatchCommand.isSameCompletion(moment, as: $0) } == true,
                     "The wrist's moment is the completion time")
        precondition(rows[1].weightKg == 60 && !rows[1].isCompleted,
                     "The load carries to the rest of the slot, as the logger does")

        let rating = WatchSetRating(sessionID: session.id, setID: id,
                                    completedAt: rows[0].completedAt!, rpe: SetFeel.hard.rawValue)
        center.applyHeadless(.rateSet(rating))
        precondition(stored(container)[0].rpe == SetFeel.hard.rawValue, "The effort answer is stored")

        var stale = rating
        stale.completedAt = rows[0].completedAt!.addingTimeInterval(-60)
        stale.rpe = SetFeel.easy.rawValue
        center.applyHeadless(.rateSet(stale))
        precondition(stored(container)[0].rpe == SetFeel.hard.rawValue,
                     "An answer about another completion is turned away")

        center.applyHeadless(.undoSet(id: id, completedAt: rows[0].completedAt))
        rows = stored(container)
        precondition(!rows[0].isCompleted && rows[0].completedAt == nil && rows[0].rpe == nil
                     && rows[0].startedAt == nil,
                     "An undone set keeps no completion, answer or start")

        center.applyHeadless(.logSet(id: id, weightKg: 60, reps: 8, seconds: 0, at: moment))
        precondition(!stored(container)[0].isCompleted,
                     "A log the wrist took back does not come back when it arrives late")
    }

    @MainActor static func startsAndFocusAndAddSet() throws {
        let (container, session) = try makeRunningSession()
        let center = WatchCommandCenter.shared

        center.applyHeadless(.focusExercise(catalogID: "bench-test"))
        precondition(sessions(container).first?.preferredExerciseID == "bench-test")
        center.applyHeadless(.focusExercise(catalogID: "not-in-session"))
        precondition(sessions(container).first?.preferredExerciseID == nil,
                     "Focus on an exercise the session lacks clears it rather than storing it")

        center.applyHeadless(.addSet(catalogID: "bench-test"))
        precondition(stored(container).count == 4, "One set is added to the exercise")
        center.applyHeadless(.addSet(catalogID: "not-in-session"))
        precondition(stored(container).count == 4, "Nothing is added to an exercise not in the session")

        // A start while one is running hands the running one back, not a second.
        center.applyHeadless(.startFreestyle)
        center.applyHeadless(.startToday)
        let open = sessions(container).filter(\.isActive)
        precondition(open.count == 1 && open[0].id == session.id,
                     "A repeated start does not open a second session")

        // With nothing running, a start opens one, marked as wrist-driven.
        let empty = try makeContainer()
        WatchCommandCenter.shared.configure(container: empty)
        WatchCommandCenter.shared.applyHeadless(.startFreestyle)
        let started = try sessions(empty)
        precondition(started.count == 1 && started[0].isActive && started[0].wasWatchDriven,
                     "A freestyle start opens one watch-driven session")
    }

    @MainActor static func finishKeepsWhatWasLoggedAndDiscardsWhatWasNot() throws {
        // Something logged: the session closes and takes the vitals.
        let (container, session) = try makeRunningSession()
        let first = session.sets.sorted(by: SetLog.precedesInSession)[0]
        let center = WatchCommandCenter.shared
        center.applyHeadless(.logSet(id: first.id, weightKg: 60, reps: 8, seconds: 0, at: .now))
        var metrics = WatchWorkoutMetrics()
        metrics.sessionID = session.id
        metrics.averageHeartRate = 118
        center.applyHeadless(.finish(metrics: metrics))
        var kept = sessions(container)
        precondition(kept.count == 1 && !kept[0].isActive && kept[0].averageHeartRate == 118,
                     "Finish closes the session and files the watch's average")
        precondition(kept[0].sets.filter { !$0.isCompleted }.isEmpty,
                     "Rows never logged are not left on a closed session")

        // A repeat of the same Finish changes nothing.
        center.applyHeadless(.finish(metrics: metrics))
        precondition(sessions(container).count == 1)

        // Nothing logged: a Finish is a mis-tap, not a workout.
        let (empty, blank) = try makeRunningSession()
        var blankMetrics = WatchWorkoutMetrics()
        blankMetrics.sessionID = blank.id
        WatchCommandCenter.shared.applyHeadless(.finish(metrics: blankMetrics))
        precondition(sessions(empty).isEmpty, "A session with nothing logged is not kept")

        // The batch form, carrying the wrist's own last log.
        let (batched, running) = try makeRunningSession()
        let target = running.sets.sorted(by: SetLog.precedesInSession)[0]
        let batch = WatchFinishBatch(
            sessionID: running.id,
            logs: [WatchPendingLog(setID: target.id, weightKg: 70, reps: 5, seconds: 0, completedAt: .now)],
            undos: [], starts: [:], cancels: [], ratings: [])
        WatchCommandCenter.shared.applyHeadless(.finishSession(batch, metrics: nil))
        kept = try sessions(batched)
        precondition(kept.count == 1 && !kept[0].isActive, "A batched Finish closes the session")
        precondition(kept[0].sets.contains { $0.weightKg == 70 && $0.reps == 5 && $0.isCompleted },
                     "The batch's unconfirmed log is applied before the close")
    }

    @MainActor static func discardSessionDeletesOnlyTheNamedSession() throws {
        let (container, session) = try makeRunningSession()
        let center = WatchCommandCenter.shared
        center.applyHeadless(.discardSession(id: UUID()))
        precondition(sessions(container).count == 1, "A discard naming another session changes nothing")
        center.applyHeadless(.discard)
        precondition(sessions(container).count == 1, "A legacy Discard has no target and is ignored")
        center.applyHeadless(.discardSession(id: session.id))
        precondition(sessions(container).isEmpty, "The named session is deleted")
        precondition(stored(container).isEmpty, "Its rows go with it")
    }

    // MARK: - Routing

    /// While a view hierarchy exists, `RootView` installs a handler that hands
    /// commands to the `ActiveWorkout`; the store-side path must stay out of
    /// its way, and pick up what the handler declines.
    @MainActor static func routingPrefersTheUIWhenOneIsAttached() throws {
        let (container, session) = try makeRunningSession()
        let context = container.mainContext
        let workout = ActiveWorkout(session: session, context: context, history: [])
        let center = WatchCommandCenter.shared
        let ids = session.sets.sorted(by: SetLog.precedesInSession).map(\.id)

        var seen: [WatchCommand] = []
        center.uiHandler = { command in
            seen.append(command)
            return workout.apply(command)
        }
        center.handle(.logSet(id: ids[0], weightKg: 55, reps: 8, seconds: 0, at: .now))
        precondition(seen.count == 1, "The UI is offered the command first")
        precondition(workout.session.sets.first { $0.id == ids[0] }?.isCompleted == true,
                     "The running workout applied it")

        // A handler that takes everything leaves the store to the UI alone.
        var declined = 0
        center.uiHandler = { _ in declined += 1; return true }
        center.handle(.logSet(id: ids[1], weightKg: 99, reps: 3, seconds: 0, at: .now))
        precondition(declined == 1 && !(session.sets.first { $0.id == ids[1] }?.isCompleted ?? true),
                     "A command the UI took is not also applied headlessly")

        // A handler that declines sends the command to the store-side path.
        center.uiHandler = { _ in false }
        center.handle(.logSet(id: ids[1], weightKg: 99, reps: 3, seconds: 0, at: .now))
        let row = stored(container).first { $0.id == ids[1] }
        precondition(row?.isCompleted == true && row?.weightKg == 99,
                     "A command the UI declined is applied headlessly")

        center.uiHandler = nil
        center.handle(.logSet(id: ids[2], weightKg: 45, reps: 10, seconds: 0, at: .now))
        precondition(stored(container).first { $0.id == ids[2] }?.isCompleted == true,
                     "With no UI at all, the store-side path takes it")
    }

    // MARK: - One context

    /// LINK-09: the command center used to write through a context of its own,
    /// so a row the screen was holding did not change until it was refetched.
    @MainActor static func theHeadlessPathSharesTheMainContext() throws {
        let (container, session) = try makeRunningSession()
        let held = try container.mainContext.fetch(FetchDescriptor<SetLog>())
            .sorted(by: SetLog.precedesInSession)[0]
        precondition(held.session?.id == session.id)
        WatchCommandCenter.shared.applyHeadless(
            .logSet(id: held.id, weightKg: 65, reps: 6, seconds: 0, at: .now))
        precondition(held.isCompleted && held.weightKg == 65,
                     "The object the screen already holds shows the wrist's log without a refetch")

        // And the other way: a row saved through another context is found.
        let other = ModelContext(container)
        let late = WorkoutSession(title: "Added elsewhere")
        other.insert(late)
        try other.save()
        // Only the first open session is the running one, so the original goes
        // first; the late one must then be the session the discard finds.
        WatchCommandCenter.shared.applyHeadless(.discardSession(id: session.id))
        WatchCommandCenter.shared.applyHeadless(.discardSession(id: late.id))
        precondition(sessions(container).isEmpty,
                     "The headless path sees a session saved through another context")
    }

    // MARK: - Overlap recovery on a narrowed fetch

    /// The headless path asks only for open sessions now. The real recovery
    /// must still find the finished workout that covers an empty duplicate.
    @MainActor static func untouchedOverlapIsRemovedFromAnOpenOnlyList() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let base = Date.now.addingTimeInterval(-3 * 3600)

        let finished = WorkoutSession(title: "Done", startedAt: base)
        finished.endedAt = base.addingTimeInterval(3600)
        let duplicate = WorkoutSession(title: "Duplicate", startedAt: base.addingTimeInterval(1800))
        let apart = WorkoutSession(title: "Later", startedAt: base.addingTimeInterval(2 * 3600))
        for session in [finished, duplicate, apart] { context.insert(session) }
        try context.save()

        let kept = WatchSessionRecovery.discardUntouchedOverlaps([duplicate, apart], in: context)
        precondition(kept.map(\.title) == ["Later"], "Only the session inside a finished one goes")
        precondition(sessions(container).map(\.title).sorted() == ["Done", "Later"],
                     "The duplicate is gone from the store, the finished one stays")

        // And through the command path: a set of the duplicate is not logged.
        let ghost = WorkoutSession(title: "Ghost", startedAt: base.addingTimeInterval(600))
        let row = SetLog(catalogID: "bench-test", exerciseName: "bench-test", exerciseOrder: 0,
                         setIndex: 0, weightKg: 50, reps: 8, seconds: 0,
                         targetRepsLow: 8, targetRepsHigh: 8, tracking: .weightReps)
        row.session = ghost
        context.insert(ghost)
        context.insert(row)
        try context.save()
        WatchCommandCenter.shared.configure(container: container)
        WatchCommandCenter.shared.applyHeadless(
            .logSet(id: row.id, weightKg: 50, reps: 8, seconds: 0, at: .now))
        precondition(sessions(container).allSatisfy { $0.title != "Ghost" },
                     "An empty duplicate is removed before a command can log into it")
    }
}
