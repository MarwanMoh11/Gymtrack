import Foundation

/// The two neighbours `WidgetPublisher.swift` names that the snapshot test has
/// no reason to build for real: the logger it may be handed, and the Lock
/// Screen card it restamps. `snapshot(...)` is called with no logger, so
/// nothing here runs; the shapes only have to type-check.
@MainActor final class ActiveWorkout {
    var session: WorkoutSession
    var completedCount = 0
    var totalCount = 0
    var currentGroup: SessionExerciseGroup?
    var nextTargetLabel = ""
    let restTimer = StubRestTimer()

    init(session: WorkoutSession) { self.session = session }
}

final class StubRestTimer { var endsAt: Date? }

@MainActor final class WorkoutLiveActivity {
    static let shared = WorkoutLiveActivity()
    static func state(for session: WorkoutSession) -> Int { 0 }
    func sync(sessionID: UUID, title: String, planName: String, state: Int) {}
}
