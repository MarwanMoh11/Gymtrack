import Foundation
import SwiftData

/// Run with scripts/test-watch-orphan-workout.sh; no simulator, watch or
/// Health access needed.
///
/// A watch workout ID for a session deleted in the meantime has nothing to
/// own it. The command center must hand it to the Health cleanup list, and
/// must not when a session still holds it.
@main
struct WatchOrphanWorkoutTests {
    @MainActor static func main() async throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        WatchCommandCenter.shared.configure(container: container)
        let health = HealthKitService.shared

        let gone = UUID(), workout = UUID()
        WatchCommandCenter.shared.handle(.metrics(WatchWorkoutMetrics(sessionID: gone, healthWorkoutID: workout)))
        precondition(health.orphanWorkouts == [workout], "a workout for a deleted session is queued for removal")

        WatchCommandCenter.shared.handle(.metrics(WatchWorkoutMetrics(sessionID: UUID(), currentHeartRate: 120)))
        precondition(health.orphanWorkouts == [workout], "a live reading for a missing session carries no workout to queue")

        let context = ModelContext(container)
        let session = WorkoutSession(title: "Push")
        context.insert(session)
        try context.save()
        session.endedAt = Date()
        try context.save()
        WatchCommandCenter.shared.handle(.metrics(WatchWorkoutMetrics(sessionID: session.id, healthWorkoutID: UUID())))
        precondition(health.orphanWorkouts == [workout], "a workout for a session that exists is not an orphan")
        print("Watch orphan workout: queued for a deleted session, kept for a live one")
    }
}
