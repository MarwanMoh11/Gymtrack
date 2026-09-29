// The stubs of `ActiveWorkoutStructureStubs.swift`, except that the Watch
// bridge, the Live Activity and Health record what they were told, so
// `SessionLifecycleTests` can check how a session ended everywhere it is
// heard. Keep the two in step when either gains a stub.
import Foundation
import SwiftData

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

@MainActor final class HealthKitService {
    static let shared = HealthKitService()
    /// Sessions a Health workout was asked for, in order.
    var savedSessionIDs: [UUID] = []
    func startWatchApp() {}
    func saveWorkout(for session: WorkoutSession) async -> UUID? {
        savedSessionIDs.append(session.id)
        return nil
    }
    func backfillVitals(for session: WorkoutSession) async {}
    func acceptWatchWorkout(_ id: UUID, for session: WorkoutSession, context: ModelContext) {}
    @discardableResult
    func discardOrphanWorkout(_ workoutID: UUID, sessionID: UUID) -> Bool { false }
}

@MainActor final class WatchBridge {
    static let shared = WatchBridge()
    var commandHandler: ((WatchCommand) -> Void)?
    var liveMetrics: WatchWorkoutMetrics?
    func activate() {}
    /// Every end the phone told the wrist about, in order.
    var ends: [WatchSessionEnd] = []
    func update(session: WatchSessionSnapshot?, ended: WatchSessionEnd? = nil) {
        if session == nil, let ended { ends.append(ended) }
    }
    func update(idle: WatchIdleSnapshot) {}
    func notePhoneHealthWorkout(_ id: UUID, for sessionID: UUID) {}
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
    var endCount = 0
    func end(with state: WorkoutActivity.ContentState?) { endCount += 1 }
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
