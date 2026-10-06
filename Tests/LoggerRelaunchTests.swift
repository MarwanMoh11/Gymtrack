import Foundation
import SwiftData

/// SESS-02's relaunch half: the load offers, the takes still open to undo and
/// what logging a set carried onto the rows below it survive the app being
/// reclaimed mid-workout, and none of it outlives its session.
/// Run with scripts/test-logger-relaunch.sh; no simulator is needed.
@main
struct LoggerRelaunchTests {
    static let bench = "bench-relaunch"

    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        try withStore { try aStandingOfferAndTheUndoOfItsDeclineSurvive(context, $0) }
        try withStore { try aTakenOfferAndItsUndoSurvive(context, $0) }
        try withStore { try aTakeSettledByLoggingCanStillBeReopened(context, $0) }
        try withStore { try aCarriedLoadIsRestoredByUndoingAfterARelaunch(context, $0) }
        try withStore { try memoryThatContradictsTheRecordIsNotResurrected(context, $0) }
        try withStore { try nothingToRememberStoresNothing(context, $0) }
        try withStore { try aClosedSessionLeavesNoKeyBehind(context, $0) }
        try withStore { try otherSessionsMemoryIsSweptAtLaunch(context, $0) }
        print("Logger relaunch checks passed")
    }

    /// A suite of its own per case, so one case's keys are never another's.
    @MainActor static func withStore(_ body: (LoggerMemoryStore) throws -> Void) throws {
        let name = "gymtrack.relaunch-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        try body(LoggerMemoryStore(defaults: defaults))
    }

    /// Four bench sets at 100 kg for 8-10, all still to do.
    @MainActor static func makeSession(_ context: ModelContext) -> (WorkoutSession, [SetLog]) {
        let session = WorkoutSession(title: "Relaunch")
        context.insert(session)
        let rows = (0..<4).map { index -> SetLog in
            let set = SetLog(catalogID: bench, exerciseName: bench, exerciseOrder: 0, setIndex: index,
                             weightKg: 100, reps: 8, targetRepsLow: 8, targetRepsHigh: 10,
                             tracking: .weightReps)
            set.session = session
            context.insert(set)
            return set
        }
        return (session, rows)
    }

    /// The app coming back: a new logger over the same session and store.
    @MainActor static func relaunch(_ session: WorkoutSession, _ context: ModelContext,
                                    _ store: LoggerMemoryStore) -> ActiveWorkout {
        ActiveWorkout(session: session, context: context, history: [], memory: store)
    }

    /// An easy top-of-range opener, which offers a rung for the three to come.
    @MainActor static func offerAfterEasyOpener(_ workout: ActiveWorkout, _ opener: SetLog)
        -> ActiveWorkout.LoadNudge {
        opener.reps = 10
        workout.complete(opener, restSeconds: nil)
        workout.rate(opener, feel: .easy)
        guard let offer = workout.pendingNudge(for: bench), offer.setCount == 3 else {
            preconditionFailure("Setup: an easy top-of-range set offers a rung for the three sets to come")
        }
        return offer
    }

    @MainActor
    static func aStandingOfferAndTheUndoOfItsDeclineSurvive(_ context: ModelContext,
                                                            _ store: LoggerMemoryStore) throws {
        let (session, rows) = makeSession(context)
        let first = relaunch(session, context, store)
        let offer = offerAfterEasyOpener(first, rows[0])
        precondition(store.storedSessionIDs == [session.id], "An offer is remembered under its session")

        let second = relaunch(session, context, store)
        precondition(second.pendingNudge(for: bench) == offer, "The offer is still standing after a relaunch")
        precondition(rows[0].loadNudgeOutcome == nil, "Restoring an offer files nothing")

        // Lifted at the weight it stood at, not the rung: a decline.
        second.complete(rows[1], restSeconds: nil)
        precondition(rows[0].loadNudgeOutcome == .declined && second.pendingNudge(for: bench) == nil)

        let third = relaunch(session, context, store)
        third.uncomplete(rows[1])
        precondition(rows[0].loadNudgeOutcome == nil && rows[0].loadNudgeToKg == nil,
                     "Undoing after a relaunch takes the decline back off the record")
        precondition(third.pendingNudge(for: bench) == offer, "and stands the offer up again")
    }

    @MainActor
    static func aTakenOfferAndItsUndoSurvive(_ context: ModelContext, _ store: LoggerMemoryStore) throws {
        let (session, rows) = makeSession(context)
        let first = relaunch(session, context, store)
        let offer = offerAfterEasyOpener(first, rows[0])
        first.apply(offer)
        precondition(rows[1...].allSatisfy { $0.weightKg == offer.toKg } && rows[0].loadNudgeOutcome == .taken)

        let second = relaunch(session, context, store)
        precondition(second.pendingNudge(for: bench) == nil)
        guard let take = second.takenNudge(for: bench) else { preconditionFailure("The take was forgotten") }
        precondition(take.nudge == offer && take.previousKg.count == 3)
        second.undoTakenNudge(take)
        precondition(rows[1...].allSatisfy { $0.weightKg == 100 }, "Every weight goes back after a relaunch")
        precondition(rows[0].loadNudgeOutcome == nil, "and the take leaves no trace")
        precondition(second.pendingNudge(for: bench) == offer)
    }

    @MainActor
    static func aTakeSettledByLoggingCanStillBeReopened(_ context: ModelContext,
                                                        _ store: LoggerMemoryStore) throws {
        let (session, rows) = makeSession(context)
        let first = relaunch(session, context, store)
        let offer = offerAfterEasyOpener(first, rows[0])
        first.apply(offer)
        first.complete(rows[1], restSeconds: nil)
        precondition(first.takenNudge(for: bench) == nil, "Lifting a moved set closes the undo")

        let second = relaunch(session, context, store)
        precondition(second.takenNudge(for: bench) == nil)
        second.uncomplete(rows[1])
        guard let reopened = second.takenNudge(for: bench) else {
            preconditionFailure("Undoing the set after a relaunch must open the take again")
        }
        second.undoTakenNudge(reopened)
        precondition(rows[1...].allSatisfy { $0.weightKg == 100 },
                     "Including the set that was logged and undone")
    }

    @MainActor
    static func aCarriedLoadIsRestoredByUndoingAfterARelaunch(_ context: ModelContext,
                                                              _ store: LoggerMemoryStore) throws {
        let (session, rows) = makeSession(context)
        let first = relaunch(session, context, store)
        rows[0].weightKg = 105
        first.complete(rows[0], restSeconds: nil)
        precondition(rows[1...].allSatisfy { $0.weightKg == 105 }, "Setup: the logged load is carried down")

        let second = relaunch(session, context, store)
        second.uncomplete(rows[0])
        precondition(rows[1...].allSatisfy { $0.weightKg == 100 },
                     "A set taken back after a relaunch puts back what it prefilled")

        // A row typed over since stays as typed, as it does without a relaunch.
        rows[0].weightKg = 105
        second.complete(rows[0], restSeconds: nil)
        rows[2].weightKg = 110
        let third = relaunch(session, context, store)
        third.uncomplete(rows[0])
        precondition(rows[1].weightKg == 100 && rows[2].weightKg == 110 && rows[3].weightKg == 100)
    }

    @MainActor
    static func memoryThatContradictsTheRecordIsNotResurrected(_ context: ModelContext,
                                                               _ store: LoggerMemoryStore) throws {
        // The offer's set taken back behind the logger's back.
        var (session, rows) = makeSession(context)
        var workout = relaunch(session, context, store)
        _ = offerAfterEasyOpener(workout, rows[0])
        rows[0].unlog()
        workout = relaunch(session, context, store)
        precondition(workout.pendingNudge(for: bench) == nil, "An offer about a set no longer logged is dropped")
        precondition(store.storedSessionIDs.isEmpty, "and what was dropped is not kept")

        // A decline filed since the offer was written down.
        (session, rows) = makeSession(context)
        workout = relaunch(session, context, store)
        let offer = offerAfterEasyOpener(workout, rows[0])
        rows[0].recordLoadNudge(.declined, toKg: offer.toKg)
        workout = relaunch(session, context, store)
        precondition(workout.pendingNudge(for: bench) == nil, "An offer the record already answered is dropped")

        // A take whose sets are all logged by now has nothing to undo.
        (session, rows) = makeSession(context)
        workout = relaunch(session, context, store)
        let another = offerAfterEasyOpener(workout, rows[0])
        workout.apply(another)
        for row in rows[1...] { row.isCompleted = true; row.completedAt = .now }
        workout = relaunch(session, context, store)
        precondition(workout.takenNudge(for: bench) == nil, "A take with nothing left to move is dropped")
    }

    @MainActor
    static func nothingToRememberStoresNothing(_ context: ModelContext, _ store: LoggerMemoryStore) throws {
        let (session, rows) = makeSession(context)
        let workout = relaunch(session, context, store)
        workout.complete(rows[0], restSeconds: nil)
        workout.rate(rows[0], feel: .solid)
        precondition(store.storedSessionIDs.isEmpty,
                     "No offer and no carry means no key: a lifter who ignores the feature can't tell it shipped")
    }

    @MainActor
    static func aClosedSessionLeavesNoKeyBehind(_ context: ModelContext, _ store: LoggerMemoryStore) throws {
        // Finished.
        var (session, rows) = makeSession(context)
        var workout = relaunch(session, context, store)
        rows[0].weightKg = 105
        _ = offerAfterEasyOpener(workout, rows[0])
        precondition(store.storedSessionIDs == [session.id])
        workout.finish()
        precondition(store.storedSessionIDs.isEmpty, "Finish removes the session's memory")
        // A save landing after the end, as a settled edit can, writes nothing.
        workout.clearRating(rows[0])
        precondition(store.storedSessionIDs.isEmpty, "A late save must not write it back")

        // Discarded.
        (session, rows) = makeSession(context)
        workout = relaunch(session, context, store)
        _ = offerAfterEasyOpener(workout, rows[0])
        precondition(store.storedSessionIDs == [session.id])
        workout.discard()
        precondition(store.storedSessionIDs.isEmpty, "Discard removes the session's memory")

        // Finished empty, which is a discard underneath.
        (session, rows) = makeSession(context)
        workout = relaunch(session, context, store)
        store.save(LoggerMemory(offers: [LoggerMemory.Offer(setID: rows[0].id, fromIndex: 0, catalogID: bench,
                                                            fromKg: 100, toKg: 105, setCount: 3, feel: 6.0)]),
                   for: session.id)
        workout.finish()
        precondition(store.storedSessionIDs.isEmpty, "An empty Finish leaves no key either")
    }

    @MainActor
    static func otherSessionsMemoryIsSweptAtLaunch(_ context: ModelContext, _ store: LoggerMemoryStore) throws {
        let leftover = LoggerMemory(carries: [LoggerMemory.Carried(setID: UUID(), rows: [
            LoggerMemory.Carry(rowID: UUID(), kg: 100, seconds: 0, carriedKg: 105, carriedSeconds: 0)])])

        // A session the wrist closed while the app was suspended, so no logger
        // was there to clear its own; and a key that names no session at all.
        let closed = WorkoutSession(title: "Closed by the wrist")
        closed.endedAt = .now
        context.insert(closed)
        store.save(leftover, for: closed.id)
        store.save(leftover, for: UUID())
        store.defaults.set(Data([1, 2, 3]), forKey: LoggerMemoryStore.keyPrefix + "not-a-session")

        // A session that is still open keeps its own.
        let (open, rows) = makeSession(context)
        store.save(LoggerMemory(carries: [LoggerMemory.Carried(setID: rows[0].id, rows: [
            LoggerMemory.Carry(rowID: rows[1].id, kg: 100, seconds: 0, carriedKg: 105, carriedSeconds: 0)])]),
                   for: open.id)

        let (mine, _) = makeSession(context)
        _ = relaunch(mine, context, store)
        precondition(store.storedSessionIDs == [open.id],
                     "Only a session still open keeps its memory: \(store.storedSessionIDs.count) keys")
        precondition(!store.defaults.dictionaryRepresentation().keys.contains { $0.hasSuffix("not-a-session") })
    }
}
