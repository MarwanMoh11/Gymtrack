import Foundation
import WidgetKit

/// Keeps the Home Screen and Lock Screen widgets in step with the app.
///
/// The widgets run in their own process and can't reach SwiftData, so the app
/// restamps a small snapshot into the shared container whenever the numbers
/// behind it move — the same arrangement the watch already has, and for the
/// same reason: one owner of the data, everything else drawing a mirror.
@MainActor
enum WidgetPublisher {

    /// The last thing written, so a save that changed nothing a widget draws
    /// doesn't spend a timeline reload. WidgetKit gives an app a budget of
    /// those per day, and a long session logs a lot of sets.
    private static var lastWritten: GymTrackSnapshot?

    /// Rebuilds the whole snapshot: today's prescription, the streak, the week,
    /// and whatever session is running.
    static func publish(plans: [Plan], sessions: [WorkoutSession], running: ActiveWorkout?) {
        let finished = sessions.filter { !$0.isActive }
        let plan = plans.first(where: \.isActive) ?? plans.first
        let today = plan?.day(for: .now)
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .distantPast
        let thisWeek = finished.filter { $0.startedAt >= weekStart }

        write(GymTrackSnapshot(
            hasPlan: plan != nil,
            todayTitle: today?.name,
            todayExerciseCount: today?.items.count ?? 0,
            todaySetCount: today?.totalSets ?? 0,
            todayMuscles: today?.targetedMuscles.prefix(3).map(\.name) ?? [],
            streak: TrainingStats.streak(from: finished).current,
            sessionsThisWeek: thisWeek.count,
            weekVolumeKg: TrainingStats.totalVolume(thisWeek),
            unit: AppSettings.shared.weightUnit,
            session: state(of: running)
        ))
    }

    /// Rewrites only the running-session part, for the many small changes
    /// inside a workout. Rebuilding the streak and the week on every logged set
    /// would mean walking the whole history from the logger.
    static func updateSession(_ running: ActiveWorkout?) {
        guard var snapshot = lastWritten ?? SharedStore.readSnapshot() else { return }
        snapshot.session = state(of: running)
        write(snapshot)
    }

    private static func state(of running: ActiveWorkout?) -> GymTrackSnapshot.Running? {
        guard let running, running.session.isActive else { return nil }
        return GymTrackSnapshot.Running(
            title: running.session.title,
            startedAt: running.session.startedAt,
            completedSets: running.completedCount,
            totalSets: running.totalCount,
            exercise: running.currentGroup?.name ?? "Freestyle",
            target: running.nextTargetLabel,
            restEndsAt: running.restTimer.endsAt
        )
    }

    private static func write(_ snapshot: GymTrackSnapshot) {
        // `updatedAt` moves on every call by definition, so it's held level for
        // the comparison — what matters is whether anything drawable changed.
        var candidate = snapshot
        if let lastWritten {
            candidate.updatedAt = lastWritten.updatedAt
            guard candidate != lastWritten else { return }
        }
        candidate.updatedAt = .now
        lastWritten = candidate
        SharedStore.write(candidate)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
