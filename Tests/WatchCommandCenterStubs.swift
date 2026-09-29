import Foundation
import SwiftData

// Everything WatchCommandCenter and ActiveWorkout lean on that a test does not
// need to run, except WatchSessionRecovery, which the script compiles for real:
// a stub of it hid the overlap check from every headless test.

extension WatchTracking {
    init(_ mode: TrackingMode) {
        switch mode {
        case .weightReps: self = .weightReps
        case .bodyweightReps: self = .bodyweightReps
        case .duration: self = .duration
        }
    }
}

/// Defaults are the ones AppSettings registers for a fresh install, so a test
/// runs the way a new user does. A test that needs rest auto-start off, or the
/// wrist launch off, sets it itself.
final class AppSettings {
    static let shared = AppSettings()
    var weightUnit: WeightUnit = .kg
    var trackRPE = true
    var restTimerAutoStart = true
    var defaultRestSeconds = 90
    var watchAutoLaunch = true
}

@MainActor final class RestTimer {
    var endsAt: Date?
    var startedAt: Date?
    var totalSeconds = 0
    var onChange: (() -> Void)?
    var isRunning: Bool { endsAt != nil }
    func start(seconds: Int) {}
    func add(seconds: Int) {}
    func restore(endingAt: Date, totalSeconds: Int) {}
    func stop() {}
}

extension WorkoutSession {
    func writeNote(_ text: String, about catalogID: String, named name: String, in context: ModelContext) {}
    func toggleNoteTag(_ tag: NoteTag, about catalogID: String, named name: String, in context: ModelContext) {}
    func pruneEmptyNotes(in context: ModelContext) {}
    func dropNote(about catalogID: String, in context: ModelContext) {}
}

@MainActor enum Haptics {
    static func celebrate() {}
    static func log() {}
    static func tick() {}
    static func start() {}
    static func success() {}
}

@MainActor enum WidgetPublisher {
    static func updateSession(_ workout: ActiveWorkout?) {}
    static func publish(plans: [Plan], sessions: [WorkoutSession], running: ActiveWorkout?) {}
    /// The running session the headless path described to the widgets, in order.
    static var headlessPublishes: [UUID?] = []
    static func publishHeadless(running: WorkoutSession?) { headlessPublishes.append(running?.id) }
}

/// Records what the headless Health write asked of it, and lets a test
/// delete the session while `saveWorkout` is suspended, as an erase from the
/// screen would.
@MainActor final class HealthKitService {
    static let shared = HealthKitService()
    var duringSave: ((WorkoutSession) -> Void)?
    var workoutToWrite: UUID?
    private(set) var saveCalls = 0
    private(set) var backfillCalls = 0
    func startWatchApp() {}
    func saveWorkout(for session: WorkoutSession) async -> UUID? {
        saveCalls += 1
        duringSave?(session)
        await Task.yield()
        return workoutToWrite
    }
    func backfillVitals(for session: WorkoutSession) async { backfillCalls += 1 }
    func acceptWatchWorkout(_ id: UUID, for session: WorkoutSession, context: ModelContext) {
        session.healthWorkoutID = id
    }
    /// Workouts the command center handed over as belonging to no session.
    private(set) var orphanWorkouts: [UUID] = []
    @discardableResult
    func discardOrphanWorkout(_ workoutID: UUID, sessionID: UUID) -> Bool {
        orphanWorkouts.append(workoutID)
        return true
    }
}

@MainActor final class WatchBridge {
    static let shared = WatchBridge()
    var commandHandler: ((WatchCommand) -> Void)?
    var liveMetrics: WatchWorkoutMetrics?
    func activate() {}
    func update(session: WatchSessionSnapshot?, ended: WatchSessionEnd? = nil) {}
    func update(idle: WatchIdleSnapshot) {}
    private(set) var notedPhoneWorkouts: [UUID] = []
    func notePhoneHealthWorkout(_ id: UUID, for sessionID: UUID) { notedPhoneWorkouts.append(id) }
    func clearMetrics() { liveMetrics = nil }
    func resend() {}
}

enum WorkoutActivity {
    struct ContentState {
        init(startedAt: Date, completedSets: Int, totalSets: Int, currentExercise: String,
             currentSetNumber: Int, currentSetTotal: Int, currentTarget: String, upNext: String,
             restEndsAt: Date?, restStartedAt: Date?, volumeLabel: String,
             elapsedLabel: String, elapsedShort: String) {}
    }
}

@MainActor final class WorkoutLiveActivity {
    static let shared = WorkoutLiveActivity()
    func end(with state: WorkoutActivity.ContentState?) {}
    func sync(sessionID: UUID, title: String, planName: String, state: WorkoutActivity.ContentState) {}
    static func state(for session: WorkoutSession, restEndsAt: Date? = nil,
                      restStartedAt: Date? = nil) -> WorkoutActivity.ContentState {
        WorkoutActivity.ContentState(startedAt: session.startedAt, completedSets: 0, totalSets: 0,
                                     currentExercise: "", currentSetNumber: 0, currentSetTotal: 0,
                                     currentTarget: "", upNext: "", restEndsAt: restEndsAt,
                                     restStartedAt: restStartedAt, volumeLabel: "",
                                     elapsedLabel: "", elapsedShort: "")
    }
}

enum WatchMirrorBuilder {
    @MainActor static func idle(plans: [Plan], sessions: [WorkoutSession]) -> WatchIdleSnapshot { .empty }
}
