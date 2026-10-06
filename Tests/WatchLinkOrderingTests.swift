import Foundation
import SwiftData

/// Run with scripts/test-watch-link-ordering.sh; no simulator is needed.
///
/// The wrist talks to the phone over two channels that keep no order between
/// them, and a live message can arrive twice. These check that the phone ends
/// up with the record the lifter made whatever order the commands land in: a
/// repeated log changes nothing, an undo answers only the log it names, a
/// Finish ends the session when it was tapped, and a live heart-rate reading
/// never writes over a finished session's totals.
@main
struct WatchLinkOrderingTests {

    /// `WatchCommand` and `WatchFinishBatch` as a watch or phone built before
    /// these changes has them: no stamp on an undo, no end on a batch.
    struct LegacyFinishBatch: Codable {
        var sessionID: UUID
        var logs: [WatchPendingLog]
        var undos: Set<UUID>
        var starts: [UUID: Date]
        var cancels: Set<UUID>
        var ratings: [WatchSetRating]
    }

    enum LegacyCommand: Codable {
        case logSet(id: UUID, weightKg: Double, reps: Int, seconds: Int, at: Date?)
        case undoSet(id: UUID)
        case finishSession(LegacyFinishBatch, metrics: WatchWorkoutMetrics?)
    }

    @MainActor static func main() throws {
        let suite = "com.marwanmohamed.gymtrack.tests.watch-link-ordering"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        DroppedSetMemory.shared.replaceStore(with: defaults)

        try checkWireFormat()
        try checkDuplicateLogs()
        try checkStampedUndos()
        try checkFinishMoment()
        try checkLateMetrics()
        print("Watch link ordering, undo stamps, finish moment and late metrics checks passed")
    }

    // MARK: - Harness

    static func makeStore() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Three sets of one exercise, nothing logged, in a running session.
    @MainActor static func runningSession(in context: ModelContext,
                                          startedAt start: Date = .now.addingTimeInterval(-3600))
        throws -> (session: WorkoutSession, sets: [SetLog]) {
        let session = WorkoutSession(title: "Ordering")
        session.startedAt = start
        context.insert(session)
        let sets = (0..<3).map { index in
            let set = SetLog(catalogID: "bench", exerciseName: "Bench", exerciseOrder: 0, setIndex: index,
                             weightKg: 60, reps: 8, targetRepsLow: 6, targetRepsHigh: 10)
            set.session = session
            context.insert(set)
            return set
        }
        try context.save()
        return (session, sets)
    }

    static func stored(_ id: UUID, in container: ModelContainer) -> SetLog? {
        let rows = (try? ModelContext(container).fetch(FetchDescriptor<SetLog>())) ?? []
        return rows.first { $0.id == id }
    }

    static func storedSession(_ id: UUID, in container: ModelContainer) -> WorkoutSession? {
        let sessions = (try? ModelContext(container).fetch(FetchDescriptor<WorkoutSession>())) ?? []
        return sessions.first { $0.id == id }
    }

    static func log(_ id: UUID, weightKg: Double = 60, at moment: Date?) -> WatchCommand {
        .logSet(id: id, weightKg: weightKg, reps: 8, seconds: 0, at: moment)
    }

    static func same(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 0.001
    }

    // MARK: - Wire format, both directions

    static func checkWireFormat() throws {
        let id = UUID()
        let stamp = Date(timeIntervalSince1970: 1_790_000_000.123_4)

        // A new watch's undo reaches an old phone, which ignores the stamp.
        let newUndo = WatchCommand.undoSet(id: id, completedAt: stamp).watchPayload(key: WatchLink.commandKey)
        guard case .undoSet(let oldID)? = LegacyCommand.fromWatchPayload(newUndo, key: WatchLink.commandKey) else {
            preconditionFailure("An old phone must still read a stamped undo")
        }
        precondition(oldID == id)

        // An old watch's undo reaches a new phone, and carries no stamp.
        let oldUndo = LegacyCommand.undoSet(id: id).watchPayload(key: WatchLink.commandKey)
        guard case .undoSet(let newID, let completion)? = WatchCommand.fromWatchPayload(oldUndo, key: WatchLink.commandKey)
        else { preconditionFailure("A new phone must still read an unstamped undo") }
        precondition(newID == id && completion == nil)

        // The stamp survives the trip to the millisecond the match allows.
        guard case .undoSet(_, let roundTrip)? = WatchCommand.fromWatchPayload(newUndo, key: WatchLink.commandKey)
        else { preconditionFailure() }
        precondition(WatchCommand.isSameCompletion(roundTrip, as: stamp))
        precondition(!WatchCommand.isSameCompletion(roundTrip, as: stamp.addingTimeInterval(0.002)))

        // A new watch's Finish reaches an old phone, which ignores the end.
        let log = WatchPendingLog(setID: id, weightKg: 60, reps: 8, seconds: 0, completedAt: stamp)
        let batch = WatchFinishBatch(sessionID: UUID(), logs: [log], undos: [], starts: [:], cancels: [],
                                     ratings: [], endedAt: stamp)
        let newFinish = WatchCommand.finishSession(batch, metrics: nil).watchPayload(key: WatchLink.commandKey)
        guard case .finishSession(let oldBatch, _)? = LegacyCommand.fromWatchPayload(newFinish, key: WatchLink.commandKey)
        else { preconditionFailure("An old phone must still read a Finish with an end") }
        precondition(oldBatch.sessionID == batch.sessionID && oldBatch.logs == [log])

        // An old watch's Finish reaches a new phone, and carries no end.
        let legacy = LegacyFinishBatch(sessionID: batch.sessionID, logs: [log], undos: [id], starts: [:],
                                       cancels: [], ratings: [])
        let oldFinish = LegacyCommand.finishSession(legacy, metrics: nil).watchPayload(key: WatchLink.commandKey)
        guard case .finishSession(let newBatch, _)? = WatchCommand.fromWatchPayload(oldFinish, key: WatchLink.commandKey)
        else { preconditionFailure("A new phone must still read a Finish without an end") }
        precondition(newBatch.endedAt == nil && newBatch.undos == [id] && newBatch.logs == [log])

        guard case .finishSession(let roundBatch, _)? = WatchCommand.fromWatchPayload(newFinish, key: WatchLink.commandKey)
        else { preconditionFailure() }
        precondition(same(roundBatch.endedAt, stamp))
    }

    // MARK: - LINK-05: the same log twice

    @MainActor static func checkDuplicateLogs() throws {
        let t1 = Date.now.addingTimeInterval(-300)
        let t2 = Date.now.addingTimeInterval(-120)

        // The logger on screen.
        do {
            let store = try makeStore()
            let context = ModelContext(store)
            let (session, sets) = try runningSession(in: context)
            let workout = ActiveWorkout(session: session, context: context, history: [])
            precondition(workout.apply(log(sets[0].id, at: t1)))
            precondition(workout.apply(log(sets[1].id, weightKg: 62.5, at: t2)))
            precondition(workout.lastLoggedSetID == sets[1].id && sets[2].weightKg == 62.5)
            sets[2].weightKg = 70

            precondition(workout.apply(log(sets[0].id, at: t1)), "A repeated log is handled")
            precondition(workout.lastLoggedSetID == sets[1].id,
                         "A repeated log must not move the effort question back to its set")
            precondition(sets[2].weightKg == 70, "A repeated log must not re-dial a row the lifter changed")
            precondition(same(sets[0].completedAt, t1))
        }

        // The phone asleep.
        do {
            let store = try makeStore()
            let context = ModelContext(store)
            let (_, sets) = try runningSession(in: context)
            let ids = sets.map(\.id)
            let center = WatchCommandCenter.shared
            center.configure(container: store)
            center.handle(log(ids[0], at: t1))
            precondition(stored(ids[2], in: store)?.weightKg == 60)
            let redial = ModelContext(store)
            let third = try redial.fetch(FetchDescriptor<SetLog>()).first { $0.id == ids[2] }!
            third.weightKg = 70
            try redial.save()

            center.handle(log(ids[0], weightKg: 60, at: t1))
            precondition(stored(ids[2], in: store)?.weightKg == 70,
                         "A repeated headless log must not carry its load over a re-dialled row")
            precondition(same(stored(ids[0], in: store)?.completedAt, t1))
        }
    }

    // MARK: - LINK-05: an undo answers the log it names

    @MainActor static func checkStampedUndos() throws {
        let t1 = Date.now.addingTimeInterval(-300)
        let t2 = Date.now.addingTimeInterval(-240)
        let t3 = Date.now.addingTimeInterval(-180)

        // The logger on screen.
        do {
            let store = try makeStore()
            let context = ModelContext(store)
            let (session, sets) = try runningSession(in: context)
            let workout = ActiveWorkout(session: session, context: context, history: [])

            // A stale undo lands after the re-log it predates.
            precondition(workout.apply(log(sets[0].id, at: t2)))
            precondition(workout.apply(.undoSet(id: sets[0].id, completedAt: t1)))
            precondition(sets[0].isCompleted && same(sets[0].completedAt, t2),
                         "An undo naming another completion must leave the re-log alone")
            precondition(workout.apply(.undoSet(id: sets[0].id, completedAt: t2)))
            precondition(!sets[0].isCompleted, "An undo naming this completion takes it back")

            // An undo that overtook its log.
            precondition(workout.apply(.undoSet(id: sets[1].id, completedAt: t2)))
            precondition(workout.apply(log(sets[1].id, at: t2)))
            precondition(!sets[1].isCompleted && sets[1].completedAt == nil,
                         "A log its undo overtook must not put the set back")
            precondition(workout.apply(log(sets[1].id, at: t3)))
            precondition(sets[1].isCompleted, "Only the log the undo named is refused")

            // An older watch's undo, with no stamp, still takes back whatever is there.
            precondition(workout.apply(log(sets[2].id, at: t3)))
            precondition(workout.apply(.undoSet(id: sets[2].id)))
            precondition(!sets[2].isCompleted)
        }

        // The phone asleep.
        do {
            let store = try makeStore()
            let context = ModelContext(store)
            let (_, sets) = try runningSession(in: context)
            let ids = sets.map(\.id)
            let center = WatchCommandCenter.shared
            center.configure(container: store)

            center.handle(log(ids[0], at: t2))
            center.handle(.undoSet(id: ids[0], completedAt: t1))
            precondition(stored(ids[0], in: store)?.isCompleted == true,
                         "A stale headless undo must leave the re-log alone")

            center.handle(.undoSet(id: ids[1], completedAt: t2))
            center.handle(log(ids[1], at: t2))
            precondition(stored(ids[1], in: store)?.isCompleted == false,
                         "A headless log its undo overtook must not put the set back")

            // A repeated log after an undo that did land in order.
            center.handle(log(ids[2], at: t3))
            center.handle(.undoSet(id: ids[2], completedAt: t3))
            center.handle(log(ids[2], at: t3))
            precondition(stored(ids[2], in: store)?.isCompleted == false,
                         "A second copy of a log already taken back stays taken back")
        }
    }

    // MARK: - WATCH-03: a wrist Finish ends when it was tapped

    @MainActor static func checkFinishMoment() throws {
        let now = Date.now

        // The clamp itself.
        do {
            let context = ModelContext(try makeStore())
            let (session, sets) = try runningSession(in: context, startedAt: now.addingTimeInterval(-3600))
            sets[0].isCompleted = true
            sets[0].completedAt = now.addingTimeInterval(-1800)
            precondition(session.wristFinishMoment(nil, now: now) == now, "No stamp ends it on arrival")
            precondition(session.wristFinishMoment(now.addingTimeInterval(-1200), now: now)
                         == now.addingTimeInterval(-1200), "A stamp is the end")
            precondition(session.wristFinishMoment(now.addingTimeInterval(-2400), now: now)
                         == now.addingTimeInterval(-1800), "Never before the last set")
            precondition(session.wristFinishMoment(now.addingTimeInterval(20), now: now) == now,
                         "Never after now")
        }

        // Headless, as the phone in a locker hears it.
        do {
            let store = try makeStore()
            let context = ModelContext(store)
            let (session, sets) = try runningSession(in: context)
            sets[0].isCompleted = true
            sets[0].completedAt = Date.now.addingTimeInterval(-1800)
            try context.save()
            let tapped = Date.now.addingTimeInterval(-1200)
            let batch = WatchFinishBatch(sessionID: session.id, logs: [], undos: [], starts: [:],
                                         cancels: [], ratings: [], endedAt: tapped)
            let center = WatchCommandCenter.shared
            center.configure(container: store)
            center.handle(.finishSession(batch, metrics: nil))
            precondition(same(storedSession(session.id, in: store)?.endedAt, tapped),
                         "A queued wrist Finish ends the session when it was tapped, not when it landed")
        }

        // Headless, with a batch log after the tap's moment, and one with no end.
        do {
            let store = try makeStore()
            let context = ModelContext(store)
            let (session, sets) = try runningSession(in: context)
            let late = Date.now.addingTimeInterval(-600)
            let batch = WatchFinishBatch(
                sessionID: session.id,
                logs: [WatchPendingLog(setID: sets[0].id, weightKg: 60, reps: 8, seconds: 0, completedAt: late)],
                undos: [], starts: [:], cancels: [], ratings: [],
                endedAt: Date.now.addingTimeInterval(-900))
            let center = WatchCommandCenter.shared
            center.configure(container: store)
            center.handle(.finishSession(batch, metrics: nil))
            precondition(same(storedSession(session.id, in: store)?.endedAt, late),
                         "The batch's own logs count as the last set")

            let other = try makeStore()
            let otherContext = ModelContext(other)
            let (legacy, legacySets) = try runningSession(in: otherContext)
            // Logged on the phone, so the Finish has something to keep: with
            // nothing logged it is a Discard (STATS-05), which ends nothing.
            legacySets[0].isCompleted = true
            legacySets[0].completedAt = Date.now.addingTimeInterval(-1800)
            try otherContext.save()
            center.configure(container: other)
            let before = Date.now
            center.handle(.finishSession(WatchFinishBatch(sessionID: legacy.id, logs: [], undos: [], starts: [:],
                                                          cancels: [], ratings: []), metrics: nil))
            let ended = storedSession(legacy.id, in: other)?.endedAt
            precondition(ended.map { $0 >= before && $0 <= .now } == true,
                         "An older watch's Finish still ends the session on arrival")
        }

        // The logger on screen, through `finish(at:)`.
        do {
            let context = ModelContext(try makeStore())
            let (session, sets) = try runningSession(in: context)
            sets[0].isCompleted = true
            sets[0].completedAt = Date.now.addingTimeInterval(-1800)
            let workout = ActiveWorkout(session: session, context: context, history: [])
            let tapped = Date.now.addingTimeInterval(-1200)
            workout.finish(at: session.wristFinishMoment(tapped))
            precondition(same(session.endedAt, tapped))
        }

        // A stale session still ends at its last set, whatever the stamp.
        do {
            let context = ModelContext(try makeStore())
            let (session, sets) = try runningSession(in: context, startedAt: Date.now.addingTimeInterval(-13 * 3600))
            let lastSet = Date.now.addingTimeInterval(-12.5 * 3600)
            sets[0].isCompleted = true
            sets[0].completedAt = lastSet
            session.close(at: session.wristFinishMoment(Date.now.addingTimeInterval(-60)), in: context)
            precondition(same(session.endedAt, lastSet), "The twelve-hour rule still holds")
        }
    }

    // MARK: - LINK-04: live readings stay live

    @MainActor static func checkLateMetrics() throws {
        let store = try makeStore()
        let context = ModelContext(store)
        let (session, sets) = try runningSession(in: context)
        sets[0].isCompleted = true
        sets[0].completedAt = Date.now.addingTimeInterval(-600)
        try context.save()
        let id = session.id
        let center = WatchCommandCenter.shared
        center.configure(container: store)

        // A live reading reaches a running session, even with the phone asleep.
        center.handle(.metrics(WatchWorkoutMetrics(sessionID: id, currentHeartRate: 120, averageHeartRate: 118,
                                                   maxHeartRate: 150, activeEnergyKcal: 200)))
        precondition(storedSession(id, in: store)?.averageHeartRate == 118)

        // The wrist's Finish carries the totals, with or without a Health workout.
        let finals = WatchWorkoutMetrics(sessionID: id, averageHeartRate: 142, maxHeartRate: 178,
                                         activeEnergyKcal: 410)
        center.handle(.finishSession(WatchFinishBatch(sessionID: id, logs: [], undos: [], starts: [:],
                                                      cancels: [], ratings: []), metrics: finals))
        let closed = storedSession(id, in: store)
        precondition(closed?.isActive == false && closed?.averageHeartRate == 142)

        // A live reading from before the close, landing after it, is turned away.
        let stale = WatchWorkoutMetrics(sessionID: id, currentHeartRate: 110, averageHeartRate: 128,
                                        maxHeartRate: 161, activeEnergyKcal: 190)
        center.handle(.metrics(stale))
        let kept = storedSession(id, in: store)
        precondition(kept?.averageHeartRate == 142 && kept?.maxHeartRate == 178 && kept?.activeEnergyKcal == 410,
                     "A live reading must never write over a finished session's totals")
        precondition(kept.map { !$0.takeWatchMetrics(stale, final: false) } == true)

        // The watch's hand-over of its Health workout still lands.
        var handover = finals
        handover.averageHeartRate = 143
        handover.healthWorkoutID = UUID()
        precondition(handover.isHandover && !stale.isHandover)
        center.handle(.metrics(handover))
        precondition(storedSession(id, in: store)?.averageHeartRate == 143,
                     "The final report carrying the Health workout still applies to a closed session")
    }
}
