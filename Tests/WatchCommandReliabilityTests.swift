import Foundation
import SwiftData

/// Run with scripts/test-watch-command-reliability.sh.
@main
struct WatchCommandReliabilityTests {
    @MainActor
    static func main() throws {
        let sessionID = UUID()
        let firstID = UUID()
        let undoneID = UUID()
        let moment = Date(timeIntervalSince1970: 1_790_079_000)
        var pending = WatchPendingActions()
        pending.adopt(sessionID)
        pending.logs[firstID] = WatchPendingLog(setID: firstID, weightKg: 55,
                                                 reps: 8, seconds: 0, completedAt: moment)
        pending.logs[undoneID] = WatchPendingLog(setID: undoneID, weightKg: 40,
                                                  reps: 6, seconds: 0, completedAt: moment)
        pending.logs.removeValue(forKey: undoneID)
        pending.undos.insert(undoneID)
        pending.starts[firstID] = moment.addingTimeInterval(-25)
        pending.focus = "squat"

        pending = try JSONDecoder().decode(WatchPendingActions.self, from: JSONEncoder().encode(pending))
        precondition(pending.sessionID == sessionID && pending.logs[firstID]?.reps == 8)
        precondition(pending.undos.contains(undoneID) && pending.focus == "squat")
        let batch = pending.finishBatch(for: sessionID, ratings: [])
        precondition(batch.logs.count == 1 && batch.undos == [undoneID],
                     "Finish must include the log and preserve the later undo")

        let command = WatchCommand.finishSession(batch, metrics: nil)
        let decoded = WatchCommand.fromWatchPayload(command.watchPayload(key: WatchLink.commandKey),
                                                    key: WatchLink.commandKey)
        guard case .finishSession(let received, _) = decoded else { fatalError("Finish did not decode") }
        precondition(received.sessionID == sessionID && received.logs.count == 1)
        let discard = WatchCommand.discardSession(id: sessionID)
        guard case .discardSession(let discardID) = WatchCommand.fromWatchPayload(
            discard.watchPayload(key: WatchLink.commandKey), key: WatchLink.commandKey
        ) else { fatalError("Discard did not decode") }
        precondition(discardID == sessionID)

        let legacyFinish = try JSONDecoder().decode(
            WatchCommand.self, from: Data("{\"finish\":{\"metrics\":null}}".utf8)
        )
        guard case .finish(nil) = legacyFinish else { fatalError("Legacy Finish did not decode") }

        var oldMetrics = WatchWorkoutMetrics.empty
        oldMetrics.sessionID = sessionID
        oldMetrics.averageHeartRate = 140
        var nextMetrics = WatchWorkoutMetrics.empty
        nextMetrics.sessionID = UUID()
        nextMetrics.activeEnergyKcal = 85
        let merged = oldMetrics.merging(nextMetrics)
        precondition(merged.sessionID == nextMetrics.sessionID && merged.averageHeartRate == nil,
                     "Previous-session heart rate cannot enter a new workout")
        precondition(merged.activeEnergyKcal == 85)

        let ended = WatchSessionEnd(sessionID: sessionID, reason: .discarded)
        let endMirror = WatchMirror(revision: 1, sentAt: moment, idle: .empty,
                                    session: nil, healthEnabled: true, endedSession: ended)
        let decodedMirror = WatchMirror.fromWatchPayload(
            endMirror.watchPayload(key: WatchLink.mirrorKey), key: WatchLink.mirrorKey
        )
        precondition(decodedMirror?.endedSession?.reason == .discarded,
                     "The watch must receive a distinct discard reason")

        for finishFirst in [false, true] {
            let container = try ModelContainer(
                for: WorkoutSession.self, SetLog.self, ExerciseNote.self,
                configurations: ModelConfiguration(isStoredInMemoryOnly: true)
            )
            let context = ModelContext(container)
            let session = WorkoutSession(title: "Test", startedAt: moment.addingTimeInterval(-300))
            session.id = sessionID
            context.insert(session)
            let logged = SetLog(catalogID: "squat", exerciseName: "Squat",
                                exerciseOrder: 0, setIndex: 0, tracking: .weightReps)
            logged.id = firstID
            logged.session = session
            context.insert(logged)
            let undone = SetLog(catalogID: "squat", exerciseName: "Squat",
                                exerciseOrder: 0, setIndex: 1, tracking: .weightReps)
            undone.id = undoneID
            undone.session = session
            undone.isCompleted = true
            undone.completedAt = moment
            context.insert(undone)
            let untouched = SetLog(catalogID: "squat", exerciseName: "Squat",
                                   exerciseOrder: 0, setIndex: 2, tracking: .weightReps)
            untouched.session = session
            context.insert(untouched)
            try context.save()

            if !finishFirst {
                // The queued set arrived before the live Finish.
                logged.weightKg = 55
                logged.reps = 8
                logged.isCompleted = true
                logged.completedAt = moment
            }
            precondition(session.applyWatchFinish(batch))
            session.close(at: moment.addingTimeInterval(10), in: context)
            try context.save()

            let remaining = try context.fetch(FetchDescriptor<SetLog>())
            precondition(remaining.count == 1 && remaining[0].id == firstID,
                         "Finish must retain the logged set and erase undo/untouched rows")
            precondition(remaining[0].weightKg == 55 && remaining[0].reps == 8)
            precondition(remaining[0].startedAt == moment.addingTimeInterval(-25))
            precondition(!session.applyWatchFinish(batch), "A repeated Finish cannot alter a closed session")
            let afterRetry = try context.fetch(FetchDescriptor<SetLog>())
            precondition(afterRetry.count == 1,
                         "A late queued log must not recreate a deleted row")
        }

        var next = pending
        next.adopt(UUID())
        precondition(next.logs.isEmpty && next.undos.isEmpty && next.focus == nil,
                     "A new workout cannot inherit pending actions")
        try checkStaleSessions()
        print("Watch lifecycle identity, queued log/undo ordering, persistence, retry and stale-session checks passed")
    }

    /// LINK-03: the twelve-hour rule every path now shares.
    @MainActor
    static func checkStaleSessions() throws {
        let container = try ModelContainer(
            for: WorkoutSession.self, SetLog.self, ExerciseNote.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let hour: TimeInterval = 3600

        func session(startedHoursAgo hours: Double, loggedAfter minutes: Double?) -> WorkoutSession {
            let session = WorkoutSession(title: "Stale", startedAt: Date.now.addingTimeInterval(-hours * hour))
            context.insert(session)
            if let minutes {
                let logged = SetLog(catalogID: "squat", exerciseName: "Squat",
                                    exerciseOrder: 0, setIndex: 0, tracking: .weightReps)
                logged.isCompleted = true
                logged.completedAt = session.startedAt.addingTimeInterval(minutes * 60)
                logged.session = session
                context.insert(logged)
            }
            let untouched = SetLog(catalogID: "squat", exerciseName: "Squat",
                                   exerciseOrder: 0, setIndex: 1, tracking: .weightReps)
            untouched.session = session
            context.insert(untouched)
            return session
        }

        let lifted = session(startedHoursAgo: 13, loggedAfter: 40)
        let empty = session(startedHoursAgo: 13, loggedAfter: nil)
        let recent = session(startedHoursAgo: 11, loggedAfter: 40)
        try context.save()
        let emptyID = empty.id
        let lastSet = lifted.startedAt.addingTimeInterval(40 * 60)

        precondition(lifted.isStale() && empty.isStale() && !recent.isStale())
        precondition(lifted.closeIfStale(in: context) && empty.closeIfStale(in: context))
        precondition(!recent.closeIfStale(in: context), "An eleven-hour session is still somebody's workout")
        try context.save()

        precondition(lifted.endedAt == lastSet,
                     "A stale session ends at its last set, not at the moment the app noticed")
        precondition(lifted.sets.count == 1 && lifted.sets[0].isCompleted,
                     "Closing a stale session drops the sets nobody lifted")
        let remaining = try context.fetch(FetchDescriptor<WorkoutSession>())
        precondition(!remaining.contains { $0.id == emptyID }, "A stale session with nothing logged is deleted")
        precondition(recent.isActive && recent.sets.count == 2, "A session under twelve hours is untouched")

        // A warm Finish of a session left open overnight: `close(in:)` is the
        // chokepoint every Finish goes through.
        let overnight = session(startedHoursAgo: 20, loggedAfter: 55)
        try context.save()
        overnight.close(in: context)
        precondition(overnight.endedAt == overnight.startedAt.addingTimeInterval(55 * 60),
                     "Finishing a stale session must not record the whole night")
        let fresh = session(startedHoursAgo: 1, loggedAfter: 30)
        let finishedAt = Date.now
        fresh.close(at: finishedAt, in: context)
        precondition(fresh.endedAt == finishedAt, "A normal Finish still ends now")
    }
}
