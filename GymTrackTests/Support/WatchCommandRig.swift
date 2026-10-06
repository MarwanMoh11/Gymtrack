import Foundation
import SwiftData
@testable import GymTrack

/// One in-memory store wired to the real `WatchCommandCenter.shared`, as iOS
/// hands it a watch message after waking the app with no view hierarchy, with
/// every process-wide singleton the center reaches pointed at throwaway state
/// and put back afterwards. A test goes through `run`, which puts everything
/// back even when the test throws.
///
/// The center's Health calls go to `health`, so a session finished here asks
/// a recorder rather than the simulator's Health store.
@MainActor
final class WatchCommandRig {
    /// Containers outlive their test on purpose. A finish starts a task that
    /// goes on reading its session for up to twelve seconds, and a model read
    /// after its container is gone traps.
    private static var retained: [ModelContainer] = []

    private static let repairKeys = ["implausibleStartsRepaired", "overtakenStartsRepaired"]

    let container: ModelContainer
    let center = WatchCommandCenter.shared
    /// The suite `DroppedSetMemory` and the center's logger memory are kept in.
    let defaults: UserDefaults
    /// The logger memory the center reads, for a test's own `ActiveWorkout`.
    let loggerMemory: LoggerMemoryStore
    /// What the center asked of Health.
    let health = HealthRecorder()

    /// An hour ago, to the whole second. `WorkoutSession.isStale` reads the wall
    /// clock, so a fixed date in the past would have every command retire the
    /// session it was meant to act on. Everything the tests stamp is an offset
    /// from this, so each stamp is in the past, as a wrist's always is.
    let started: Date

    private var suites: [String]
    private var loggers: [ActiveWorkout] = []
    private var readers: [ModelContext] = []
    private let savedHealth: WatchCommandCenter.HealthCalls
    private let savedRepairFlags: [String: Any?]
    private let savedUnit = AppSettings.shared.weightUnit
    private let savedTrackRPE = AppSettings.shared.trackRPE

    var context: ModelContext { container.mainContext }

    private init(_ name: String) throws {
        container = try TestStore.container()
        Self.retained.append(container)
        defaults = TestClock.freshDefaults(name)
        suites = [name]
        loggerMemory = LoggerMemoryStore(defaults: defaults)
        started = Date(timeIntervalSince1970: (Date.now.timeIntervalSince1970 - 3600).rounded(.down))
        savedHealth = center.health
        savedRepairFlags = Dictionary(uniqueKeysWithValues: Self.repairKeys.map {
            ($0, UserDefaults.standard.object(forKey: $0))
        })
        DroppedSetMemory.shared.replaceStore(with: defaults)
        center.loggerMemory = loggerMemory
        center.uiHandler = nil
        center.health = health.calls
        center.configure(container: container)
    }

    /// Runs `body` against a fresh rig and always puts the process back.
    static func run(_ name: String = #function,
                    _ body: @MainActor (WatchCommandRig) throws -> Void) throws {
        let rig = try WatchCommandRig(name)
        defer { rig.tearDown() }
        try body(rig)
    }

    /// `run`, for a test that waits on what a command set off.
    static func run(_ name: String = #function,
                    _ body: @MainActor (WatchCommandRig) async throws -> Void) async throws {
        let rig = try WatchCommandRig(name)
        defer { rig.tearDown() }
        try await body(rig)
    }

    private func tearDown() {
        for logger in loggers { logger.restTimer.stop() }
        loggers = []
        center.uiHandler = nil
        center.loggerMemory = .standard
        center.health = savedHealth
        WatchBridge.shared.commandHandler = nil
        WatchBridge.shared.update(session: nil, ended: nil)
        DroppedSetMemory.shared.replaceStore(with: .standard)
        LoadScaleBook.shared.clearAll()
        AppSettings.shared.weightUnit = savedUnit
        AppSettings.shared.trackRPE = savedTrackRPE
        for (key, value) in savedRepairFlags {
            if let value { UserDefaults.standard.set(value, forKey: key) }
            else { UserDefaults.standard.removeObject(forKey: key) }
        }
        for suite in suites { UserDefaults().removePersistentDomain(forName: "GymTrackTests." + suite) }
    }

    // MARK: Moments

    /// `seconds` after the session `seed` opens by default.
    func at(_ seconds: TimeInterval) -> Date { started.addingTimeInterval(seconds) }

    /// `seconds` before the rig was set up, to the whole second, for a test
    /// that counts back from the moment it runs rather than on from a start.
    func ago(_ seconds: TimeInterval) -> Date { started.addingTimeInterval(3600 - seconds) }

    // MARK: Building

    /// An open session with no rows, started an hour ago unless told otherwise.
    func session(_ title: String = "Push", startedAt: Date? = nil) -> WorkoutSession {
        let session = WorkoutSession(title: title, startedAt: startedAt ?? started)
        context.insert(session)
        return session
    }

    /// One row of `session`, unlogged. Catalog IDs are made up so the real
    /// catalog's machines and tracking modes cannot change what a set is.
    @discardableResult
    func addRow(_ catalogID: String = "test-bench", order: Int = 0, index: Int,
                weightKg: Double = 60, reps: Int = 8, seconds: Int = 0, low: Int = 6, high: Int = 10,
                tracking: TrackingMode = .weightReps, to session: WorkoutSession) -> SetLog {
        let set = SetLog(catalogID: catalogID, exerciseName: catalogID, exerciseOrder: order,
                         setIndex: index, weightKg: weightKg, reps: reps, seconds: seconds,
                         targetRepsLow: low, targetRepsHigh: high, tracking: tracking)
        set.session = session
        context.insert(set)
        return set
    }

    /// An open session of unlogged, prescribed sets: 60 kg for 8, as a plan
    /// would have filled them in.
    @discardableResult
    func seed(exercises: [String] = ["test-bench"], setsEach: Int = 3,
              startedAt: Date? = nil) throws -> (session: WorkoutSession, sets: [SetLog]) {
        let session = self.session(startedAt: startedAt)
        var sets: [SetLog] = []
        for (order, catalogID) in exercises.enumerated() {
            for index in 0..<setsEach {
                sets.append(addRow(catalogID, order: order, index: index, high: 8, to: session))
            }
        }
        try context.save()
        return (session, sets)
    }

    /// A logger over `session`, as the screen would hold one, keeping its
    /// memory where the center reads it. Its rest timer is stopped on the way
    /// out.
    func logger(for session: WorkoutSession, history: [WorkoutSession] = []) -> ActiveWorkout {
        let logger = ActiveWorkout(session: session, context: context, history: history, memory: loggerMemory)
        loggers.append(logger)
        return logger
    }

    /// A suite of its own, emptied first and removed on the way out.
    func freshDefaults(_ label: String) -> UserDefaults {
        let name = suites[0] + "." + label
        suites.append(name)
        return TestClock.freshDefaults(name)
    }

    // MARK: Reading

    func sessions() -> [WorkoutSession] {
        (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
    }

    func allSets() -> [SetLog] {
        (try? context.fetch(FetchDescriptor<SetLog>())) ?? []
    }

    /// A second context, which sees only what was saved. Kept alive here
    /// because a model does not outlive its context.
    func reader() -> ModelContext {
        let reader = ModelContext(container)
        readers.append(reader)
        return reader
    }

    /// The row as the store holds it, so a change the center made and never
    /// saved does not count.
    func stored(_ id: UUID) -> SetLog? {
        let rows = (try? reader().fetch(FetchDescriptor<SetLog>(predicate: #Predicate { $0.id == id }))) ?? []
        return rows.first
    }

    // MARK: Driving

    func log(_ set: SetLog, weight: Double = 62.5, reps: Int = 6, at seconds: TimeInterval) -> WatchCommand {
        .logSet(id: set.id, weightKg: weight, reps: reps, seconds: 0, at: at(seconds))
    }

    func send(_ command: WatchCommand) { center.handle(command) }

    /// A set as the logger leaves it once logged, written by hand because the
    /// app's own helper for a wrist log is private to the app.
    func complete(_ set: SetLog, at moment: Date) {
        set.isCompleted = true
        set.completedAt = moment
    }
}

/// Stands in for Health behind `WatchCommandCenter.health`, and keeps what the
/// center asked of it.
@MainActor
final class HealthRecorder {
    /// The phone workout `saveWorkout` reports writing; none unless set.
    var workoutToWrite: UUID?
    /// Runs while the save is under way, for a test that deletes the session
    /// then, as an erase from the screen would.
    var duringSave: ((WorkoutSession) -> Void)?
    private(set) var saves = 0
    private(set) var backfills = 0
    /// Workouts handed over as belonging to no session, in order.
    private(set) var orphanWorkouts: [UUID] = []
    /// Phone workouts the watch was to be told about, in order.
    private(set) var notedPhoneWorkouts: [UUID] = []

    var calls: WatchCommandCenter.HealthCalls {
        WatchCommandCenter.HealthCalls(
            saveWorkout: { session in
                self.saves += 1
                self.duringSave?(session)
                // Health's own write suspends, and the session can go meanwhile.
                await Task.yield()
                return self.workoutToWrite
            },
            backfillVitals: { _ in self.backfills += 1 },
            discardOrphanWorkout: { workoutID, _ in self.orphanWorkouts.append(workoutID) },
            notePhoneWorkout: { workoutID, _ in self.notedPhoneWorkouts.append(workoutID) }
        )
    }
}
