import Foundation
import SwiftData

/// Run with scripts/test-session-lifecycle.sh. Takes about fifteen seconds:
/// the Health write after a stale close waits out the twelve seconds a watch
/// gets to hand over its own workout, exactly as a Finish does.
///
/// STATS-05: a Finish with nothing logged is a Discard, on the phone and on
/// the headless wrist path alike, so no empty session is kept. WATCH-10: a
/// session the phone retires for being left open is told to the wrist as
/// finished when it kept sets, and gets its Health workout; one deleted for
/// being empty is told as discarded and gets none.
@main
struct SessionLifecycleTests {

    @MainActor
    static func main() async throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        try checkPhoneFinish(container)
        WatchCommandCenter.shared.configure(container: container)
        try checkHeadlessWristFinish(container)
        try await checkStaleClose(container)
        print("Session lifecycle checks passed")
    }

    @MainActor
    static func insertSession(_ context: ModelContext, startedAgo seconds: TimeInterval = 600,
                              loggedAfter minutes: Double?) -> WorkoutSession {
        let session = WorkoutSession(title: "Push", startedAt: Date.now.addingTimeInterval(-seconds))
        context.insert(session)
        if let minutes {
            let logged = SetLog(catalogID: "bench", exerciseName: "Bench",
                                exerciseOrder: 0, setIndex: 0, weightKg: 60, reps: 8)
            logged.isCompleted = true
            logged.completedAt = session.startedAt.addingTimeInterval(minutes * 60)
            logged.session = session
            context.insert(logged)
        }
        let untouched = SetLog(catalogID: "bench", exerciseName: "Bench",
                               exerciseOrder: 0, setIndex: 1, weightKg: 60, reps: 8)
        untouched.session = session
        context.insert(untouched)
        return session
    }

    @MainActor
    static func stored(_ id: UUID, in container: ModelContainer) -> WorkoutSession? {
        let all = (try? ModelContext(container).fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return all.first { $0.id == id }
    }

    // MARK: - STATS-05

    @MainActor
    static func checkPhoneFinish(_ container: ModelContainer) throws {
        let context = ModelContext(container)

        let empty = insertSession(context, loggedAfter: nil)
        let emptyID = empty.id
        try context.save()
        ActiveWorkout(session: empty, context: context, history: []).finish()
        precondition(stored(emptyID, in: container) == nil,
                     "The phone's Finish with nothing logged keeps no session")
        precondition(WatchBridge.shared.ends.last == WatchSessionEnd(sessionID: emptyID, reason: .discarded),
                     "The wrist hears an empty Finish as a Discard")

        let lifted = insertSession(context, loggedAfter: 5)
        let liftedID = lifted.id
        try context.save()
        ActiveWorkout(session: lifted, context: context, history: []).finish()
        let kept = stored(liftedID, in: container)
        precondition(kept?.endedAt != nil && kept?.sets.count == 1,
                     "A Finish with a set logged closes the session as before")
        precondition(WatchBridge.shared.ends.last == WatchSessionEnd(sessionID: liftedID, reason: .finished))
    }

    @MainActor
    static func checkHeadlessWristFinish(_ container: ModelContainer) throws {
        let context = ModelContext(container)

        // Started well before the phone Finish above: the real WatchSessionRecovery
        // reads an untouched session that begins inside a finished workout as a
        // duplicate and deletes it on lookup, which is not the path under test.
        let empty = insertSession(context, startedAgo: 7_200, loggedAfter: nil)
        let emptyID = empty.id
        try context.save()
        let liveActivityEnds = WorkoutLiveActivity.shared.endCount
        let emptyBatch = WatchFinishBatch(sessionID: emptyID, logs: [], undos: [], starts: [:], cancels: [],
                                          ratings: [], endedAt: .now)
        WatchCommandCenter.shared.handle(.finishSession(emptyBatch, metrics: nil))
        precondition(stored(emptyID, in: container) == nil,
                     "A wrist Finish with nothing logged, applied with the phone asleep, keeps no session")
        precondition(WatchBridge.shared.ends.last == WatchSessionEnd(sessionID: emptyID, reason: .discarded),
                     "The headless empty Finish is told to the wrist as a Discard")
        precondition(WorkoutLiveActivity.shared.endCount > liveActivityEnds,
                     "The Live Activity comes down as it does for a Discard")

        // The batch's own log counts: a Finish that overtook the wrist's only
        // log is not an empty one.
        let overtaken = insertSession(context, startedAgo: 5_400, loggedAfter: nil)
        let overtakenID = overtaken.id
        let rowID = overtaken.sets[0].id
        try context.save()
        let log = WatchPendingLog(setID: rowID, weightKg: 60, reps: 8, seconds: 0,
                                  completedAt: Date.now.addingTimeInterval(-30))
        let batch = WatchFinishBatch(sessionID: overtakenID, logs: [log], undos: [], starts: [:], cancels: [],
                                     ratings: [], endedAt: .now)
        WatchCommandCenter.shared.handle(.finishSession(batch, metrics: nil))
        let closed = stored(overtakenID, in: container)
        precondition(closed?.endedAt != nil && closed?.completedSets.count == 1,
                     "A Finish carrying the wrist's only log keeps the session and the set")
        precondition(WatchBridge.shared.ends.last == WatchSessionEnd(sessionID: overtakenID, reason: .finished))
    }

    // MARK: - WATCH-10

    @MainActor
    static func checkStaleClose(_ container: ModelContainer) async throws {
        let context = ModelContext(container)

        let forgottenEmpty = insertSession(context, startedAgo: 13 * 3600, loggedAfter: nil)
        let emptyID = forgottenEmpty.id
        try context.save()
        WatchCommandCenter.shared.handle(.requestMirror)
        precondition(stored(emptyID, in: container) == nil, "A stale session with nothing logged is deleted")
        precondition(WatchBridge.shared.ends.last == WatchSessionEnd(sessionID: emptyID, reason: .discarded),
                     "The wrist hears an empty stale session was discarded")

        let forgotten = insertSession(context, startedAgo: 13 * 3600, loggedAfter: 40)
        let forgottenID = forgotten.id
        let lastSet = forgotten.startedAt.addingTimeInterval(40 * 60)
        try context.save()
        WatchCommandCenter.shared.handle(.requestMirror)
        precondition(stored(forgottenID, in: container)?.endedAt == lastSet,
                     "A stale session with sets closes at its last set")
        precondition(WatchBridge.shared.ends.last == WatchSessionEnd(sessionID: forgottenID, reason: .finished),
                     "The wrist hears a stale session with sets finished, so a recording is kept, not thrown away")

        // The Health write waits for a watch workout first, as after a Finish.
        try await Task.sleep(for: .seconds(14))
        let saved = HealthKitService.shared.savedSessionIDs
        precondition(saved.contains(forgottenID), "A stale session with sets gets its Health workout")
        precondition(!saved.contains(emptyID), "A stale session deleted for being empty gets none")
    }
}
