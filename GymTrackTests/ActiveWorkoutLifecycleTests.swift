import Foundation
import SwiftData
import Testing
@testable import GymTrack

// What this file protects: the life of an in-progress workout. It starts with
// one row per prescribed set, survives the app being reclaimed (a new logger
// over the same store picks up where the old one stopped), and ends in one of
// two ways. Finishing keeps what was lifted and drops what was not; discarding,
// which an empty Finish also is, leaves nothing behind at all.
//
// These run the real `ActiveWorkout` in the hosted app. The rests and starts a
// set's own lifecycle moves are in ActiveWorkoutRestAndStartTests, and the
// session rules that need no logger in EntityPersistenceTests.
//
// `WorkoutBench`, declared first, is shared with ActiveWorkoutLoggingTests and
// ActiveWorkoutRestAndStartTests.

/// One test's whole world: a store of its own, a logger memory of its own, and
/// the settings the logger reads put to known values and put back afterwards.
///
/// `ActiveWorkout` reads `AppSettings.shared` and writes `DroppedSetMemory.shared`
/// and, unless handed another, `UserDefaults.standard`. A test that left any of
/// them changed would turn the next one's result into a question of order, so
/// every test goes through `run`, which restores them even when it throws.
@MainActor
final class WorkoutBench {
    nonisolated static let bench = "barbell-bench-press"
    nonisolated static let row = "barbell-row"
    nonisolated static let plank = "plank-bodyweight"

    /// A Wednesday morning, months before any real clock reading. A moment this
    /// far back puts no rest in motion when it is passed to `complete`, which
    /// is what most tests want; the ones about rests pass a live moment.
    nonisolated static let t0 = TestClock.at("2026-03-11T10:00:00")

    let container: ModelContainer
    let context: ModelContext
    /// Where the logger keeps what it would lose to a relaunch.
    let memory: LoggerMemoryStore

    private let suites: [String]
    private let defaults: UserDefaults
    private var workouts: [ActiveWorkout] = []
    private var readers: [ModelContext] = []
    private let saved: (unit: WeightUnit, rpe: Bool, autoStart: Bool, rest: Int, health: Bool)

    private init(name: String) throws {
        let label = name.filter { $0.isLetter || $0.isNumber }
        container = try TestStore.container()
        context = ModelContext(container)
        defaults = TestClock.freshDefaults(label + ".memory")
        memory = LoggerMemoryStore(defaults: defaults)
        suites = [label + ".memory", label + ".dropped"]
        DroppedSetMemory.shared.replaceStore(with: TestClock.freshDefaults(label + ".dropped"))

        let settings = AppSettings.shared
        saved = (settings.weightUnit, settings.trackRPE, settings.restTimerAutoStart,
                 settings.defaultRestSeconds, settings.healthWriteWorkouts)
        settings.weightUnit = .kg
        settings.trackRPE = true
        settings.restTimerAutoStart = true
        settings.defaultRestSeconds = 90
        // Nothing here should reach Health, and `finish` would try.
        settings.healthWriteWorkouts = false
    }

    /// Runs `body` against a fresh bench and always puts the process back.
    static func run(_ name: String = #function, _ body: (WorkoutBench) throws -> Void) throws {
        let bench = try WorkoutBench(name: name)
        defer { bench.tearDown() }
        try body(bench)
    }

    private func tearDown() {
        for workout in workouts { workout.restTimer.stop() }
        // `start` and `startFreestyle` cannot be handed a memory, so they used
        // the real one; whatever a test left under it is swept here.
        for session in (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? [] {
            LoggerMemoryStore.standard.forget(session.id)
        }
        DroppedSetMemory.shared.replaceStore(with: .standard)
        let settings = AppSettings.shared
        settings.weightUnit = saved.unit
        settings.trackRPE = saved.rpe
        settings.restTimerAutoStart = saved.autoStart
        settings.defaultRestSeconds = saved.rest
        settings.healthWriteWorkouts = saved.health
        for suite in suites { UserDefaults().removePersistentDomain(forName: "GymTrackTests." + suite) }
    }

    // MARK: Builders

    /// One slot of a plan day.
    struct Slot {
        var catalogID: String
        var sets = 3
        var low = 8
        var high = 12
        var kg = 0.0
    }

    func planDay(named name: String, planName: String = "Strength", slots: [Slot]) -> (plan: Plan, day: PlanDay) {
        let plan = Plan(name: planName, isActive: true)
        context.insert(plan)
        let day = PlanDay(name: name, order: 0)
        day.plan = plan
        context.insert(day)
        for (index, slot) in slots.enumerated() {
            let item = PlanItem(catalogID: slot.catalogID, name: slot.catalogID, order: index,
                                targetSets: slot.sets, targetRepsLow: slot.low,
                                targetRepsHigh: slot.high, targetWeightKg: slot.kg)
            item.day = day
            context.insert(item)
        }
        try? context.save()
        return (plan, day)
    }

    /// An open session with no rows yet, started at an explicit moment.
    func session(title: String = "Push", startedAt: Date = WorkoutBench.t0) -> WorkoutSession {
        let session = WorkoutSession(title: title, startedAt: startedAt)
        context.insert(session)
        return session
    }

    /// Rows for one exercise, all still to do.
    @discardableResult
    func addRows(_ catalogID: String = WorkoutBench.bench, to session: WorkoutSession, count: Int,
                 order: Int = 0, weightKg: Double = 100, reps: Int = 8, low: Int = 8, high: Int = 10,
                 tracking: TrackingMode = .weightReps) -> [SetLog] {
        (0..<count).map { index in
            let set = SetLog(catalogID: catalogID, exerciseName: catalogID, exerciseOrder: order,
                             setIndex: index, weightKg: weightKg, reps: reps,
                             targetRepsLow: low, targetRepsHigh: high, tracking: tracking)
            set.session = session
            context.insert(set)
            return set
        }
    }

    /// The usual subject: four bench sets at 100 kg for 8 to 10, and a logger
    /// over them that remembers into this bench's own suite.
    func standard(startedAt: Date = WorkoutBench.t0) -> (session: WorkoutSession, rows: [SetLog], workout: ActiveWorkout) {
        let session = session(startedAt: startedAt)
        let rows = addRows(to: session, count: 4)
        return (session, rows, open(session))
    }

    /// A logger over a session, as the app builds one at launch or on Start.
    func open(_ session: WorkoutSession, history: [WorkoutSession] = [], in context: ModelContext? = nil) -> ActiveWorkout {
        track(ActiveWorkout(session: session, context: context ?? self.context, history: history, memory: memory))
    }

    /// Starts from a plan day through the real entry point, whose memory is
    /// the process-wide one; `tearDown` clears it.
    func start(day: PlanDay, plan: Plan?, history: [WorkoutSession] = []) -> ActiveWorkout {
        track(ActiveWorkout.start(day: day, plan: plan, context: context, history: history))
    }

    func startFreestyle() -> ActiveWorkout {
        track(ActiveWorkout.startFreestyle(context: context, history: []))
    }

    private func track(_ workout: ActiveWorkout) -> ActiveWorkout {
        workouts.append(workout)
        return workout
    }

    /// A finished session some days back, for the logger to read as history.
    func finishedSession(startedAt: Date, catalogID: String = WorkoutBench.bench,
                         lifts: [(kg: Double, reps: Int)]) -> WorkoutSession {
        let past = WorkoutSession(title: "Before", startedAt: startedAt)
        past.endedAt = startedAt.addingTimeInterval(3600)
        context.insert(past)
        for (index, lift) in lifts.enumerated() {
            let set = SetLog(catalogID: catalogID, exerciseName: catalogID, exerciseOrder: 0,
                             setIndex: index, weightKg: lift.kg, reps: lift.reps,
                             targetRepsLow: 6, targetRepsHigh: 8, tracking: .weightReps)
            set.isCompleted = true
            set.completedAt = startedAt.addingTimeInterval(600 + Double(index) * 120)
            set.session = past
            context.insert(set)
        }
        try? context.save()
        return past
    }

    // MARK: Reading back

    /// What a second context sees, which is what a relaunch sees: only what
    /// was saved. Kept alive here because a model does not outlive its context.
    func reader() -> ModelContext {
        let reader = ModelContext(container)
        readers.append(reader)
        return reader
    }

    func stored(_ set: SetLog) throws -> SetLog {
        let id = set.id
        return try #require(try reader().fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.id == id })).first)
    }

    func count<Model: PersistentModel>(_ type: Model.Type) throws -> Int {
        try context.fetchCount(FetchDescriptor<Model>())
    }

    func group(_ workout: ActiveWorkout, _ catalogID: String = WorkoutBench.bench) throws -> SessionExerciseGroup {
        try #require(workout.groups.first { $0.catalogID == catalogID })
    }
}

/// Counts how many times a notification arrived. A class because the observer
/// closure is `@Sendable` and cannot mutate a captured local.
private final class PostCounter: @unchecked Sendable {
    var count = 0
}

@MainActor @Suite(.serialized)
struct ActiveWorkoutLifecycleTests {

    // MARK: Starting

    @Test func startBuildsOneRowPerPrescribedSetInPlanOrder() throws {
        try WorkoutBench.run { bench in
            let (plan, day) = bench.planDay(named: "Push A", slots: [
                .init(catalogID: WorkoutBench.bench, sets: 3, low: 6, high: 8, kg: 80),
                .init(catalogID: WorkoutBench.row, sets: 2, low: 8, high: 12, kg: 60),
            ])
            let workout = bench.start(day: day, plan: plan)
            let session = workout.session

            #expect(session.endedAt == nil)
            #expect(session.title == "Push A")
            #expect(session.planName == plan.name)
            #expect(session.planDayID == day.id)
            #expect(session.plannedSlots?.count == 2)

            let rows = session.sets.sorted(by: SetLog.precedesInSession)
            #expect(rows.map(\.catalogID) == [WorkoutBench.bench, WorkoutBench.bench, WorkoutBench.bench,
                                              WorkoutBench.row, WorkoutBench.row])
            #expect(rows.map(\.exerciseOrder) == [0, 0, 0, 1, 1])
            #expect(rows.map(\.setIndex) == [0, 1, 2, 0, 1])
            #expect(rows.allSatisfy { !$0.isCompleted && $0.completedAt == nil })
            #expect(rows.prefix(3).allSatisfy { $0.targetRepsLow == 6 && $0.targetRepsHigh == 8 })

            // On disk before the first set is logged, or a relaunch finds nothing.
            let read1 = try bench.count(WorkoutSession.self)
            #expect(read1 == 1)
            let read2 = try bench.count(SetLog.self)
            #expect(read2 == 5)
        }
    }

    @Test func startCarriesLastSessionsLoadOntoTheNewSets() throws {
        try WorkoutBench.run { bench in
            // One set of the three prescribed was done last time, which is what
            // makes the answer independent of the progression's thresholds: the
            // load is repeated, never moved.
            let history = bench.finishedSession(startedAt: WorkoutBench.t0.addingTimeInterval(-7 * 86_400),
                                                lifts: [(kg: 60, reps: 7)])
            let (plan, day) = bench.planDay(named: "Push A", slots: [
                .init(catalogID: WorkoutBench.bench, sets: 3, low: 6, high: 8, kg: 40),
                .init(catalogID: WorkoutBench.row, sets: 2, low: 8, high: 12, kg: 50),
            ])
            let workout = bench.start(day: day, plan: plan, history: [history])

            let benchRows = workout.session.sets.filter { $0.catalogID == WorkoutBench.bench }
            #expect(benchRows.count == 3)
            #expect(benchRows.allSatisfy { $0.weightKg == 60 })

            // Nothing to carry for the row: it opens at what the plan names,
            // pulled onto the machine's ladder.
            let rowScale = LoadScaleBook.shared.scale(for: WorkoutBench.row)
            let rowRows = workout.session.sets.filter { $0.catalogID == WorkoutBench.row }
            #expect(rowRows.allSatisfy { $0.weightKg == rowScale.snap(kg: 50) })
        }
    }

    @Test func startFreestyleOpensAnEmptySessionAndAddExerciseNumbersItsRows() throws {
        try WorkoutBench.run { bench in
            let workout = bench.startFreestyle()
            #expect(workout.session.title == "Freestyle Session")
            #expect(workout.session.sets.isEmpty)
            #expect(workout.session.planDayID == nil)
            #expect(workout.session.endedAt == nil)

            let press = try #require(ExerciseCatalog.shared.exercise(id: WorkoutBench.bench))
            let row = try #require(ExerciseCatalog.shared.exercise(id: WorkoutBench.row))
            workout.addExercise(press, sets: 3)
            workout.addExercise(row, sets: 2)

            let rows = workout.session.sets.sorted(by: SetLog.precedesInSession)
            #expect(rows.map(\.exerciseOrder) == [0, 0, 0, 1, 1])
            #expect(rows.map(\.setIndex) == [0, 1, 2, 0, 1])

            // The same movement added again joins its card rather than opening
            // a second one, and carries on from its last index.
            workout.addExercise(press, sets: 2)
            #expect(workout.groups.count == 2)
            let benchIndexes = workout.session.sets.filter { $0.catalogID == WorkoutBench.bench }
                .map(\.setIndex).sorted()
            #expect(benchIndexes == [0, 1, 2, 3, 4])
        }
    }

    // MARK: Resuming

    @Test func aNewLoggerOverTheSameStoreResumesWhereTheLastOneStopped() throws {
        try WorkoutBench.run { bench in
            let (session, rows, first) = bench.standard()
            rows[0].reps = 10
            first.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))
            first.rate(rows[0], feel: .easy)
            let offer = try #require(first.pendingNudge(for: WorkoutBench.bench))

            let resumed = bench.open(session)
            #expect(session.endedAt == nil)
            #expect(resumed.completedCount == 1)
            #expect(resumed.totalCount == 4)
            #expect(resumed.nextSet?.id == rows[1].id)
            // The offer lived only in the logger; it comes back from the memory.
            #expect(resumed.pendingNudge(for: WorkoutBench.bench)?.toKg == offer.toKg)
        }
    }

    @Test func aContextOpenedAfterTheRelaunchSeesOnlyWhatWasSaved() throws {
        try WorkoutBench.run { bench in
            let (_, rows, first) = bench.standard()
            first.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))
            first.complete(rows[1], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(240))

            // What the launch does: look for a session with no end in a context
            // of its own, and hand it to a new logger.
            let reader = bench.reader()
            let open = try reader.fetch(FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.endedAt == nil }))
            let adopted = try #require(open.first)
            #expect(open.count == 1)
            let resumed = bench.open(adopted, in: reader)
            #expect(resumed.completedCount == 2)
            #expect(resumed.nextSet?.setIndex == 2)

            // And it is a working logger, not a read-only view: the next log
            // lands in the store the first one wrote to.
            let third = try #require(resumed.nextSet)
            resumed.complete(third, restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(420))
            let loggedNow = try bench.context.fetch(FetchDescriptor<SetLog>(
                predicate: #Predicate { $0.isCompleted }))
            #expect(loggedNow.count == 3)
        }
    }

    // MARK: Finishing

    @Test func finishClosesTheSessionAtTheGivenMomentAndAnnouncesItOnce() throws {
        try WorkoutBench.run { bench in
            let (session, rows, workout) = bench.standard()
            workout.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))

            let posts = PostCounter()
            let token = NotificationCenter.default.addObserver(
                forName: .gymTrackWorkoutFinished, object: nil, queue: nil) { _ in posts.count += 1 }
            defer { NotificationCenter.default.removeObserver(token) }

            let end = WorkoutBench.t0.addingTimeInterval(1_800)
            #expect(workout.finish(at: end))
            #expect(session.endedAt == end)
            #expect(session.isActive == false)
            #expect(posts.count == 1)
            #expect(!workout.restTimer.isRunning)
            // So a watch still recording keeps its workout rather than throwing it away.
            #expect(WatchBridge.shared.mirrorState.endedSession
                    == WatchSessionEnd(sessionID: session.id, reason: .finished))
        }
    }

    @Test func finishKeepsWhatWasLiftedAndDropsTheRestIntoMemory() throws {
        try WorkoutBench.run { bench in
            let (session, rows, workout) = bench.standard()
            workout.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))
            workout.complete(rows[1], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(240))

            #expect(workout.finish(at: WorkoutBench.t0.addingTimeInterval(900)))

            #expect(Set(session.sets.map(\.id)) == [rows[0].id, rows[1].id])
            let read3 = try bench.count(SetLog.self)
            #expect(read3 == 2)
            // A set that was never done is not data, but the wrist may still
            // be about to log it, so the row is kept aside for a week.
            #expect(DroppedSetMemory.shared.row(for: rows[2].id) != nil)
            #expect(DroppedSetMemory.shared.row(for: rows[0].id) == nil)
        }
    }

    @Test func finishWithNothingLoggedDiscardsTheSessionAndSaysSo() throws {
        try WorkoutBench.run { bench in
            let (session, _, workout) = bench.standard()
            let id = session.id

            let posts = PostCounter()
            let token = NotificationCenter.default.addObserver(
                forName: .gymTrackWorkoutFinished, object: nil, queue: nil) { _ in posts.count += 1 }
            defer { NotificationCenter.default.removeObserver(token) }

            #expect(workout.finish(at: WorkoutBench.t0.addingTimeInterval(600)) == false)
            let read4 = try bench.count(WorkoutSession.self)
            #expect(read4 == 0)
            let read5 = try bench.count(SetLog.self)
            #expect(read5 == 0)
            #expect(posts.count == 0)
            #expect(!bench.memory.storedSessionIDs.contains(id))
            // The wrist hears it as the Discard it is.
            #expect(WatchBridge.shared.mirrorState.endedSession == WatchSessionEnd(sessionID: id, reason: .discarded))
        }
    }

    @Test func finishForgetsWhatTheLoggerKeptForARelaunch() throws {
        try WorkoutBench.run { bench in
            let (session, rows, workout) = bench.standard()
            rows[0].reps = 10
            workout.complete(rows[0], restSeconds: nil, at: WorkoutBench.t0.addingTimeInterval(60))
            workout.rate(rows[0], feel: .easy)
            #expect(bench.memory.storedSessionIDs == [session.id])

            #expect(workout.finish(at: WorkoutBench.t0.addingTimeInterval(900)))
            #expect(bench.memory.storedSessionIDs.isEmpty)

            // And a logger built over the finished session clears a key that
            // outlived it, which is what the wrist's Finish while the app slept
            // leaves behind.
            let carry = LoggerMemory.Carry(rowID: rows[1].id, kg: 100, seconds: 0, carriedKg: 105, carriedSeconds: 0)
            bench.memory.save(LoggerMemory(carries: [.init(setID: rows[0].id, rows: [carry])]), for: session.id)
            #expect(bench.memory.storedSessionIDs == [session.id])
            _ = bench.open(session)
            #expect(bench.memory.storedSessionIDs.isEmpty)
        }
    }

    // MARK: Discarding

    @Test func discardLeavesNoSessionNoSetsAndNoMemory() throws {
        try WorkoutBench.run { bench in
            let (session, rows, workout) = bench.standard()
            rows[0].reps = 10
            workout.complete(rows[0], restSeconds: 60, at: .now)
            workout.rate(rows[0], feel: .easy)
            let id = session.id
            #expect(workout.restTimer.isRunning)
            #expect(bench.memory.storedSessionIDs == [id])

            let posts = PostCounter()
            let token = NotificationCenter.default.addObserver(
                forName: .gymTrackWorkoutFinished, object: nil, queue: nil) { _ in posts.count += 1 }
            defer { NotificationCenter.default.removeObserver(token) }

            workout.discard()

            let read6 = try bench.count(WorkoutSession.self)
            #expect(read6 == 0)
            let read7 = try bench.count(SetLog.self)
            #expect(read7 == 0)
            #expect(bench.memory.storedSessionIDs.isEmpty)
            #expect(!workout.restTimer.isRunning)
            // A discard is not a finished workout, and must not read as one.
            #expect(posts.count == 0)
        }
    }

    // MARK: Empty and stale sessions

    @Test func anEmptyWorkoutHasNothingToDoAndNothingToCount() throws {
        try WorkoutBench.run { bench in
            let workout = bench.startFreestyle()
            #expect(workout.groups.isEmpty)
            #expect(workout.nextSet == nil)
            #expect(workout.currentGroup == nil)
            #expect(workout.completedCount == 0)
            #expect(workout.totalCount == 0)
            #expect(workout.progress == 0)
            #expect(workout.volumeKg == 0)

            // Adding an exercise with no sets adds no rows, rather than a card
            // that can never be finished.
            let press = try #require(ExerciseCatalog.shared.exercise(id: WorkoutBench.bench))
            workout.addExercise(press, sets: 0)
            #expect(workout.session.sets.isEmpty)

            #expect(workout.finish(at: WorkoutBench.t0) == false)
            let read8 = try bench.count(WorkoutSession.self)
            #expect(read8 == 0)
        }
    }

    @Test func aStaleSessionWithSetsIsClosedAtItsLastSetNotResumed() throws {
        try WorkoutBench.run { bench in
            let session = bench.session(startedAt: WorkoutBench.t0)
            let rows = bench.addRows(to: session, count: 3)
            rows[0].isCompleted = true
            rows[0].completedAt = WorkoutBench.t0.addingTimeInterval(600)
            rows[1].isCompleted = true
            rows[1].completedAt = WorkoutBench.t0.addingTimeInterval(1_500)

            #expect(session.closeIfStale(in: bench.context))
            // Saving is left to the caller, which knows what else it has to tell.
            try bench.context.save()
            #expect(session.endedAt == WorkoutBench.t0.addingTimeInterval(1_500))
            #expect(Set(session.sets.map(\.id)) == [rows[0].id, rows[1].id])
        }
    }

    @Test func aStaleSessionWithNothingLoggedIsDeletedNotKept() throws {
        try WorkoutBench.run { bench in
            let session = bench.session(startedAt: WorkoutBench.t0)
            bench.addRows(to: session, count: 3)

            #expect(session.closeIfStale(in: bench.context))
            try bench.context.save()
            let read9 = try bench.count(WorkoutSession.self)
            #expect(read9 == 0)
        }
    }

    @Test(arguments: [(offset: 43_200.0, stale: false), (offset: 43_201.0, stale: true)])
    func aSessionIsStaleOnlyPastTwelveHours(offset: Double, stale: Bool) throws {
        try WorkoutBench.run { bench in
            let (session, rows, workout) = bench.standard()
            let lastSet = WorkoutBench.t0.addingTimeInterval(1_800)
            workout.complete(rows[0], restSeconds: nil, at: lastSet)

            let tap = WorkoutBench.t0.addingTimeInterval(offset)
            #expect(session.isStale(at: tap) == stale)
            #expect(workout.finish(at: tap))
            // Past the limit the Finish is somebody finding yesterday's
            // session: it ends where the lifting did, not where the tap fell.
            #expect(session.endedAt == (stale ? lastSet : tap))
        }
    }

    @Test func aSessionLeftOvernightEndsAtItsLastSetWithAnHonestLength() throws {
        try WorkoutBench.run { bench in
            let start = TestClock.at("2026-03-10T22:00:00")
            let (session, rows, workout) = bench.standard(startedAt: start)
            let lastSet = TestClock.at("2026-03-10T22:40:00")
            workout.complete(rows[0], restSeconds: nil, at: lastSet)

            #expect(workout.finish(at: TestClock.at("2026-03-11T14:00:00")))
            #expect(session.endedAt == lastSet)
            #expect(session.duration == 40 * 60)
        }
    }

    @Test(arguments: ["UTC", "Africa/Cairo", "Pacific/Kiritimati"])
    func aSessionCrossingMidnightStaysOneSessionInEveryZone(zone: String) throws {
        try WorkoutBench.run { bench in
            let calendar = TestClock.calendar(in: zone)
            let start = TestClock.at("2026-03-10T23:40:00", in: zone)
            let beforeMidnight = TestClock.at("2026-03-10T23:50:00", in: zone)
            let afterMidnight = TestClock.at("2026-03-11T00:20:00", in: zone)
            let tap = TestClock.at("2026-03-11T00:35:00", in: zone)
            // The case only means something if the wall clock changed day.
            #expect(!calendar.isDate(start, inSameDayAs: afterMidnight))

            let (session, rows, workout) = bench.standard(startedAt: start)
            workout.complete(rows[0], restSeconds: nil, at: beforeMidnight)
            workout.complete(rows[1], restSeconds: nil, at: afterMidnight)
            #expect(workout.finish(at: tap))

            // Midnight is not an event to a workout: one session, started on
            // the day it began, ended when Finish was tapped, with both lifts.
            #expect(session.startedAt == start)
            #expect(session.endedAt == tap)
            #expect(session.duration == 55 * 60)
            #expect(session.sets.compactMap(\.completedAt).sorted() == [beforeMidnight, afterMidnight])
            let read10 = try bench.count(WorkoutSession.self)
            #expect(read10 == 1)
        }
    }

    // MARK: What a relaunch brings back

    private func at(_ seconds: Double) -> Date { WorkoutBench.t0.addingTimeInterval(seconds) }

    /// An easy top-of-range opener on the standard four, which offers a rung
    /// for the three sets still to do.
    private func offerAfterEasyOpener(_ workout: ActiveWorkout, _ opener: SetLog) throws -> ActiveWorkout.LoadNudge {
        opener.reps = 10
        workout.complete(opener, restSeconds: nil, at: at(60))
        workout.rate(opener, feel: .easy)
        let offer = try #require(workout.pendingNudge(for: WorkoutBench.bench))
        try #require(offer.setCount == 3)
        return offer
    }

    @Test func aStandingOfferAndTheUndoOfItsDeclineSurviveARelaunch() throws {
        try WorkoutBench.run { bench in
            let (session, rows, first) = bench.standard()
            let offer = try offerAfterEasyOpener(first, rows[0])
            #expect(bench.memory.storedSessionIDs == [session.id])

            let second = bench.open(session)
            #expect(second.pendingNudge(for: WorkoutBench.bench) == offer)
            // Bringing an offer back files nothing.
            #expect(rows[0].loadNudgeOutcome == nil)

            // Lifted at the weight it stood at, not the rung: a decline.
            second.complete(rows[1], restSeconds: nil, at: at(240))
            #expect(rows[0].loadNudgeOutcome == .declined)
            #expect(second.pendingNudge(for: WorkoutBench.bench) == nil)

            let third = bench.open(session)
            third.uncomplete(rows[1])
            #expect(rows[0].loadNudgeOutcome == nil)
            #expect(rows[0].loadNudgeToKg == nil)
            #expect(third.pendingNudge(for: WorkoutBench.bench) == offer)
        }
    }

    @Test func aTakenOfferAndItsUndoSurviveARelaunch() throws {
        try WorkoutBench.run { bench in
            let (session, rows, first) = bench.standard()
            let offer = try offerAfterEasyOpener(first, rows[0])
            first.apply(offer)
            #expect(rows[1...].allSatisfy { $0.weightKg == offer.toKg })
            #expect(rows[0].loadNudgeOutcome == .taken)

            let second = bench.open(session)
            #expect(second.pendingNudge(for: WorkoutBench.bench) == nil)
            let take = try #require(second.takenNudge(for: WorkoutBench.bench))
            #expect(take.nudge == offer)
            #expect(take.previousKg.count == 3)

            second.undoTakenNudge(take)
            #expect(rows[1...].allSatisfy { $0.weightKg == 100 })
            #expect(rows[0].loadNudgeOutcome == nil)
            #expect(second.pendingNudge(for: WorkoutBench.bench) == offer)
        }
    }

    @Test func aTakeSettledByLoggingCanBeReopenedAfterARelaunch() throws {
        try WorkoutBench.run { bench in
            let (session, rows, first) = bench.standard()
            let offer = try offerAfterEasyOpener(first, rows[0])
            first.apply(offer)
            // Lifting a moved set closes the undo.
            first.complete(rows[1], restSeconds: nil, at: at(240))
            #expect(first.takenNudge(for: WorkoutBench.bench) == nil)

            let second = bench.open(session)
            #expect(second.takenNudge(for: WorkoutBench.bench) == nil)
            second.uncomplete(rows[1])
            let reopened = try #require(second.takenNudge(for: WorkoutBench.bench))
            second.undoTakenNudge(reopened)

            // The set that was logged and taken back included.
            #expect(rows[1...].allSatisfy { $0.weightKg == 100 })
        }
    }

    @Test func aLoadCarriedDownTheCardIsPutBackByAnUndoAfterARelaunch() throws {
        try WorkoutBench.run { bench in
            let (session, rows, first) = bench.standard()
            rows[0].weightKg = 105
            first.complete(rows[0], restSeconds: nil, at: at(60))
            #expect(rows[1...].allSatisfy { $0.weightKg == 105 })

            let second = bench.open(session)
            second.uncomplete(rows[0])
            #expect(rows[1...].allSatisfy { $0.weightKg == 100 })

            // A row typed over since stays as typed, as it does without a relaunch.
            rows[0].weightKg = 105
            second.complete(rows[0], restSeconds: nil, at: at(120))
            rows[2].weightKg = 110
            let third = bench.open(session)
            third.uncomplete(rows[0])
            #expect(rows.dropFirst().map(\.weightKg) == [100, 110, 100])
        }
    }

    @Test func anOfferAboutASetTakenBackBehindTheLoggersBackIsDroppedAtRelaunch() throws {
        try WorkoutBench.run { bench in
            let (session, rows, first) = bench.standard()
            _ = try offerAfterEasyOpener(first, rows[0])
            rows[0].unlog()

            let second = bench.open(session)
            #expect(second.pendingNudge(for: WorkoutBench.bench) == nil)
            // And what was dropped is not kept.
            #expect(bench.memory.storedSessionIDs.isEmpty)
        }
    }

    @Test func anOfferTheRecordAlreadyAnsweredIsDroppedAtRelaunch() throws {
        try WorkoutBench.run { bench in
            let (session, rows, first) = bench.standard()
            let offer = try offerAfterEasyOpener(first, rows[0])
            rows[0].recordLoadNudge(.declined, toKg: offer.toKg)

            let second = bench.open(session)
            #expect(second.pendingNudge(for: WorkoutBench.bench) == nil)
        }
    }

    @Test func aTakeWithNothingLeftToMoveIsDroppedAtRelaunch() throws {
        try WorkoutBench.run { bench in
            let (session, rows, first) = bench.standard()
            first.apply(try offerAfterEasyOpener(first, rows[0]))
            for row in rows[1...] {
                row.isCompleted = true
                row.completedAt = at(300)
            }

            let second = bench.open(session)
            #expect(second.takenNudge(for: WorkoutBench.bench) == nil)
        }
    }

    /// A lifter who ignores the offers and the undo can't tell the memory
    /// shipped: no offer and no carry means no key.
    @Test func aLoggerWithNothingToRememberStoresNoKey() throws {
        try WorkoutBench.run { bench in
            let (_, rows, workout) = bench.standard()
            workout.complete(rows[0], restSeconds: nil, at: at(60))
            workout.rate(rows[0], feel: .solid)

            #expect(bench.memory.storedSessionIDs.isEmpty)
        }
    }

    /// A settled edit can save after the end, and must not write the memory back.
    @Test func aSaveThatLandsAfterTheFinishWritesNoMemoryBack() throws {
        try WorkoutBench.run { bench in
            let (session, rows, workout) = bench.standard()
            rows[0].weightKg = 105
            _ = try offerAfterEasyOpener(workout, rows[0])
            #expect(bench.memory.storedSessionIDs == [session.id])
            #expect(workout.finish(at: at(900)))
            #expect(bench.memory.storedSessionIDs.isEmpty)

            workout.clearRating(rows[0])

            #expect(bench.memory.storedSessionIDs.isEmpty)
        }
    }

    /// An empty Finish is a Discard underneath, and leaves no key either.
    @Test func anEmptyFinishClearsTheMemoryItsSessionHeld() throws {
        try WorkoutBench.run { bench in
            let (session, rows, workout) = bench.standard()
            let offer = LoggerMemory.Offer(setID: rows[0].id, fromIndex: 0, catalogID: WorkoutBench.bench,
                                           fromKg: 100, toKg: 105, setCount: 3, feel: SetFeel.easy.rawValue)
            bench.memory.save(LoggerMemory(offers: [offer]), for: session.id)
            #expect(bench.memory.storedSessionIDs == [session.id])

            #expect(workout.finish(at: at(900)) == false)

            #expect(bench.memory.storedSessionIDs.isEmpty)
        }
    }

    @Test func startingALoggerSweepsTheMemoryOfEverySessionNoLongerOpen() throws {
        try WorkoutBench.run { bench in
            let leftover = LoggerMemory(carries: [LoggerMemory.Carried(setID: UUID(), rows: [
                LoggerMemory.Carry(rowID: UUID(), kg: 100, seconds: 0, carriedKg: 105, carriedSeconds: 0)])])
            // A session the wrist closed while the app was suspended, so no
            // logger was there to clear its own; a key that names no session;
            // and one that is not a session ID at all.
            let closed = bench.session(title: "Closed by the wrist")
            closed.endedAt = at(3_600)
            bench.memory.save(leftover, for: closed.id)
            bench.memory.save(leftover, for: UUID())
            bench.memory.defaults.set(Data([1, 2, 3]), forKey: LoggerMemoryStore.keyPrefix + "not-a-session")
            // A session still open keeps its own.
            let stillOpen = bench.session(startedAt: at(7_200))
            let rows = bench.addRows(to: stillOpen, count: 4)
            bench.memory.save(LoggerMemory(carries: [LoggerMemory.Carried(setID: rows[0].id, rows: [
                LoggerMemory.Carry(rowID: rows[1].id, kg: 100, seconds: 0, carriedKg: 105, carriedSeconds: 0)])]),
                              for: stillOpen.id)

            let mine = bench.session(startedAt: at(7_300))
            bench.addRows(to: mine, count: 4)
            _ = bench.open(mine)

            #expect(bench.memory.storedSessionIDs == [stillOpen.id])
            #expect(!bench.memory.defaults.dictionaryRepresentation().keys.contains { $0.hasSuffix("not-a-session") })
        }
    }

    // MARK: A past session deleted mid-workout

    /// A mistyped 500 kg bench deleted from History behind a minimised logger
    /// must stop being the "last time" hint and the record to beat (SESS-08).
    @Test func aPastSessionDeletedMidWorkoutStopsBeingTheHintAndTheRecordToBeat() throws {
        try WorkoutBench.run { bench in
            let older = bench.finishedSession(startedAt: at(-14 * 86_400),
                                              lifts: [(kg: 60, reps: 5), (kg: 60, reps: 5), (kg: 60, reps: 5)])
            let typo = bench.finishedSession(startedAt: at(-7 * 86_400),
                                             lifts: [(kg: 500, reps: 5), (kg: 500, reps: 5), (kg: 500, reps: 5)])
            let session = bench.session()
            let rows = bench.addRows(to: session, count: 4)
            let workout = bench.open(session, history: [older, typo])
            #expect(workout.lastPerformance(for: WorkoutBench.bench).first?.weightKg == 500)

            // The first set logged builds the record baseline, 500 kg in it.
            rows[0].weightKg = 40
            rows[0].reps = 5
            workout.complete(rows[0], restSeconds: nil, at: at(60))
            #expect(!workout.isPR(rows[0]))

            bench.context.delete(typo)
            try bench.context.save()
            #expect(typo.modelContext == nil)

            #expect(workout.lastPerformance(for: WorkoutBench.bench).first?.weightKg == 60)
            rows[1].weightKg = 100
            rows[1].reps = 5
            workout.complete(rows[1], restSeconds: nil, at: at(240))
            #expect(workout.isPR(rows[1]))
        }
    }

    // MARK: A day that repeats a movement

    /// Made up, so the real catalog's machines can't change what a slot is.
    private static let repeated = "repeat-test"
    private static let other = "other-test"

    /// A heavy pair and a lighter three of one movement with another exercise
    /// between them, and last week's run of the day folded into one exercise,
    /// as every session built since GT-011 is.
    private func repeatedDay(_ bench: WorkoutBench)
        -> (session: WorkoutSession, top: PlanItem, backOff: PlanItem, past: WorkoutSession) {
        let (plan, day) = bench.planDay(named: "Strength", slots: [
            .init(catalogID: Self.repeated, sets: 2, low: 6, high: 6, kg: 30),
            .init(catalogID: Self.other, sets: 1, low: 8, high: 8, kg: 20),
            .init(catalogID: Self.repeated, sets: 3, low: 10, high: 10, kg: 45),
        ])
        let past = WorkoutSession(title: "Previous", startedAt: at(-7 * 86_400))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        bench.context.insert(past)
        let lifts: [(kg: Double, reps: Int)] = [(60, 6), (60, 6), (40, 10), (40, 10), (40, 10)]
        for (index, lift) in lifts.enumerated() {
            let set = SetLog(catalogID: Self.repeated, exerciseName: Self.repeated, exerciseOrder: 0,
                             setIndex: index, weightKg: lift.kg, reps: lift.reps,
                             targetRepsLow: lift.reps, targetRepsHigh: lift.reps, tracking: .weightReps)
            set.isCompleted = true
            set.completedAt = past.endedAt
            set.session = past
            bench.context.insert(set)
        }
        let items = day.orderedItems
        let session = SessionFactory.build(day: day, plan: plan, context: bench.context, history: [past])
        return (session, items[0], items[2], past)
    }

    @Test func aDayThatRepeatsAMovementOpensOneExerciseWhoseSlotsProgressFromTheirOwnShare() throws {
        try WorkoutBench.run { bench in
            let (session, top, backOff, _) = repeatedDay(bench)
            let topNext = top.loadScale.step(kg: 60, by: 1)
            let backOffNext = backOff.loadScale.step(kg: 40, by: 1)

            let groups = session.exerciseGroups
            #expect(groups.map(\.catalogID) == [Self.repeated, Self.other])
            let sets = try #require(groups.first).sets
            #expect(sets.map(\.setIndex) == Array(0..<5))
            #expect(sets.map(\.weightKg) == [topNext, topNext, backOffNext, backOffNext, backOffNext])
            #expect(sets.map(\.reps) == [6, 6, 10, 10, 10])
            #expect(sets.map(\.targetRepsLow) == [6, 6, 10, 10, 10])
            #expect(Set(sets.map(\.exerciseOrder)).count == 1)
        }
    }

    @Test func aLogCarriesItsLoadToTheEndOfItsOwnSlotAndNoFurther() throws {
        try WorkoutBench.run { bench in
            let (session, _, backOff, past) = repeatedDay(bench)
            let backOffNext = backOff.loadScale.step(kg: 40, by: 1)
            let workout = bench.open(session, history: [past])
            let sets = try bench.group(workout, Self.repeated).sets

            sets[0].weightKg = 70
            workout.complete(sets[0], restSeconds: nil, at: at(60))
            #expect(sets.map(\.weightKg) == [70, 70, backOffNext, backOffNext, backOffNext])

            sets[2].weightKg = 50
            workout.complete(sets[2], restSeconds: nil, at: at(300))
            // And never back up into the top slot.
            #expect(sets.map(\.weightKg) == [70, 70, 50, 50, 50])
        }
    }

    @Test func addingAndRemovingRowsOfARepeatedMovementKeepsItOneOrderedExerciseOnBothScreens() throws {
        try WorkoutBench.run { bench in
            let (session, _, _, past) = repeatedDay(bench)
            let workout = bench.open(session, history: [past])
            let sets = try bench.group(workout, Self.repeated).sets
            sets[0].weightKg = 70
            workout.complete(sets[0], restSeconds: nil, at: at(60))
            sets[2].weightKg = 50
            workout.complete(sets[2], restSeconds: nil, at: at(300))
            @MainActor func indexes() -> [Int] { session.exerciseGroups.first?.sets.map(\.setIndex) ?? [] }

            // Freestyle repeats join the same exercise, modelled on the working set.
            let repeated = CatalogExercise(id: Self.repeated, name: Self.repeated, category: "strength",
                                           muscleGroups: [], equipment: [], details: nil,
                                           difficulty: nil, tracking: .weightReps)
            workout.addExercise(repeated, sets: 2)
            #expect(indexes() == Array(0..<7))
            let added = try bench.group(workout, Self.repeated).sets.suffix(2)
            #expect(added.allSatisfy { $0.weightKg == 50 && $0.reps == 10 })

            workout.addSet(to: try bench.group(workout, Self.repeated))
            #expect(indexes() == Array(0..<8))
            workout.removeLastSet(from: try bench.group(workout, Self.repeated))
            #expect(indexes() == Array(0..<7))

            workout.continueSet(sets[0])
            #expect(indexes() == Array(0..<8))
            let continuation = try bench.group(workout, Self.repeated).sets[1]
            #expect(continuation.isContinuation)
            workout.removeContinuation(continuation)
            #expect(indexes() == Array(0..<7))

            // The wrist receives the same single ordered exercise.
            let mirror = WatchSnapshotFactory.snapshot(for: session, rest: (nil, nil, 0),
                                                       restSeconds: { _ in 90 }, lastTimeLabel: { _ in nil })
            #expect(mirror.exercises.map(\.id) == [Self.repeated, Self.other])
            #expect(mirror.exercises.first?.sets.map(\.index) == Array(0..<7))
        }
    }

    /// Two takes in a row are one undoable choice: the undo goes back past
    /// the first take, not to the rung between them.
    @Test func undoingASecondTakePutsBackTheLoadFromBeforeEitherTake() throws {
        try WorkoutBench.run { bench in
            let session = bench.session(title: "Nudge undo")
            let rows = bench.addRows(to: session, count: 3, weightKg: 40, reps: 8, low: 8, high: 12)
            let source = rows[0]
            source.reps = 12
            source.isCompleted = true
            source.completedAt = at(60)
            let workout = bench.open(session)

            workout.rate(source, feel: .easy)
            workout.apply(try #require(workout.pendingNudge(for: WorkoutBench.bench)))
            source.reps = 5
            workout.rate(source, feel: .allOut)
            let down = try #require(workout.pendingNudge(for: WorkoutBench.bench))
            workout.apply(down)
            #expect(rows.dropFirst().allSatisfy { $0.weightKg == down.toKg })

            workout.undoTakenNudge(try #require(workout.takenNudge(for: WorkoutBench.bench)))

            #expect(rows.filter { !$0.isCompleted }.allSatisfy { $0.weightKg == 40 })
            #expect(source.loadNudgeOutcome == nil)
        }
    }

    @Test func aFinishedSessionStoredWithDuplicateSlotsReadsAsOneExerciseAndKeepsItsRows() throws {
        try WorkoutBench.run { bench in
            let legacy = bench.session(title: "Old duplicate slots")
            let oldFirst = SetLog(catalogID: Self.repeated, exerciseName: Self.repeated,
                                  exerciseOrder: 0, setIndex: 0, weightKg: 30, reps: 6)
            let oldSecond = SetLog(catalogID: Self.repeated, exerciseName: Self.repeated,
                                   exerciseOrder: 2, setIndex: 0, weightKg: 45, reps: 10)
            for set in [oldFirst, oldSecond] {
                set.isCompleted = true
                set.completedAt = at(600)
                set.session = legacy
                bench.context.insert(set)
            }
            legacy.endedAt = at(3_600)
            let both = [oldFirst.id, oldSecond.id]

            #expect(legacy.exerciseGroups.first?.sets.map(\.id) == both)
            #expect(TrainingStats.history(for: Self.repeated, in: [legacy]).first?.sets.map(\.id) == both)
            #expect(TrainingStats.lastPerformance(of: Self.repeated, in: [legacy]).map(\.id) == both)
            // Reading them as one exercise rewrites nothing that was stored.
            #expect(oldSecond.setIndex == 0)
        }
    }

    /// Two slots with the same range, as the day editor writes them, told
    /// apart only by the day's set counts.
    @Test func slotsSharingARangeEachFeedTheNextBuildFromTheirOwnSets() throws {
        try WorkoutBench.run { bench in
            let (plan, day) = bench.planDay(named: "Volume", slots: [
                .init(catalogID: Self.repeated, sets: 2), .init(catalogID: Self.other, sets: 1),
                .init(catalogID: Self.repeated, sets: 3),
            ])
            let top = try #require(day.orderedItems.first)
            let lastWeek = at(-7 * 86_400)
            let first = SessionFactory.build(day: day, plan: plan, context: bench.context, history: [])
            first.startedAt = lastWeek
            let workout = bench.open(first)
            let rows = try bench.group(workout, Self.repeated).sets
            #expect(rows.count == 5)
            #expect(rows.allSatisfy { $0.weightKg == 0 })

            rows[0].weightKg = 60
            rows[0].reps = 12
            workout.complete(rows[0], restSeconds: nil, at: lastWeek.addingTimeInterval(300))
            #expect(rows.map(\.weightKg) == [60, 60, 0, 0, 0])
            rows[2].weightKg = 40
            rows[2].reps = 12
            workout.complete(rows[2], restSeconds: nil, at: lastWeek.addingTimeInterval(600))
            #expect(rows.map(\.weightKg) == [60, 60, 40, 40, 40])
            for (offset, row) in rows.enumerated() where !row.isCompleted {
                row.reps = row.weightKg == 60 ? 12 : 9
                workout.complete(row, restSeconds: nil, at: lastWeek.addingTimeInterval(900 + Double(offset) * 120))
            }
            first.endedAt = lastWeek.addingTimeInterval(3_600)

            let next = SessionFactory.build(day: day, plan: plan, context: bench.context, history: [first])
            let opened = try #require(next.exerciseGroups.first { $0.catalogID == Self.repeated }).sets
            let topNext = top.loadScale.step(kg: 60, by: 1)
            // The cleared slot climbs; the one short of its range holds its own load.
            #expect(opened.map(\.weightKg) == [topNext, topNext, 40, 40, 40])
            // The climb starts again at the bottom of the range; the hold keeps last time's reps.
            #expect(opened.map(\.reps) == [8, 8, 12, 9, 9])
        }
    }
}
