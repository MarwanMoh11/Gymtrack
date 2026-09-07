import Foundation
import SwiftData
import SwiftUI

/// Drives an in-progress session. The session and its sets are SwiftData
/// objects written as you go, so force-quitting mid-workout loses nothing —
/// the app finds the unfinished session on next launch and offers to resume.
@Observable
@MainActor
final class ActiveWorkout {
    private(set) var session: WorkoutSession
    let restTimer = RestTimer()

    /// Index of the exercise the logger is focused on.
    var focusedExerciseIndex: Int = 0

    /// Set IDs that just earned a PR, so the UI can celebrate once.
    private(set) var recentPRs: Set<UUID> = []

    private let context: ModelContext
    private var history: [WorkoutSession]

    /// The plan prescriptions behind this session, keyed by exercise. Resolved
    /// once — the logging view asks for these on every card render.
    private var prescriptions: [String: PlanItem] = [:]

    /// Last session's sets per exercise, likewise resolved once.
    private var lastPerformances: [String: [SetLog]] = [:]

    init(session: WorkoutSession, context: ModelContext, history: [WorkoutSession]) {
        self.session = session
        self.context = context
        self.history = history.filter { $0.id != session.id }

        if let dayID = session.planDayID,
           let day = (try? context.fetch(FetchDescriptor<PlanDay>()))?.first(where: { $0.id == dayID }) {
            prescriptions = Dictionary(day.items.map { ($0.catalogID, $0) }, uniquingKeysWith: { first, _ in first })
        }
        for catalogID in Set(session.sets.map(\.catalogID)) {
            lastPerformances[catalogID] = TrainingStats.lastPerformance(
                of: catalogID, in: self.history, excluding: session.id
            )
        }
    }

    // MARK: - Creating a session

    /// Starts a session from a plan day, pre-building every prescribed set with
    /// the load carried over from last time.
    static func start(day: PlanDay, plan: Plan?, context: ModelContext, history: [WorkoutSession]) -> ActiveWorkout {
        let session = WorkoutSession(title: day.name, planDayID: day.id, planName: plan?.name ?? "")
        context.insert(session)

        for (exerciseIndex, item) in day.orderedItems.enumerated() {
            let last = TrainingStats.lastPerformance(of: item.catalogID, in: history)
            let suggestion = TrainingStats.suggestion(for: item, lastSets: last)
            let startingWeight = last.isEmpty ? item.targetWeightKg : suggestion.weightKg

            for setIndex in 0..<max(1, item.targetSets) {
                let previous = setIndex < last.count ? last[setIndex] : last.last
                let set = SetLog(
                    catalogID: item.catalogID,
                    exerciseName: item.name,
                    exerciseOrder: exerciseIndex,
                    setIndex: setIndex,
                    weightKg: startingWeight,
                    reps: previous?.reps ?? item.targetRepsLow,
                    seconds: item.targetSeconds,
                    targetRepsLow: item.targetRepsLow,
                    targetRepsHigh: item.targetRepsHigh
                )
                set.session = session
                context.insert(set)
            }
        }

        try? context.save()
        return ActiveWorkout(session: session, context: context, history: history)
    }

    /// Starts an empty session the user fills in as they go.
    static func startFreestyle(context: ModelContext, history: [WorkoutSession]) -> ActiveWorkout {
        let session = WorkoutSession(title: "Freestyle Session")
        context.insert(session)
        try? context.save()
        return ActiveWorkout(session: session, context: context, history: history)
    }

    // MARK: - Derived state

    var groups: [SessionExerciseGroup] { session.exerciseGroups }

    var completedCount: Int { session.sets.filter(\.isCompleted).count }
    var totalCount: Int { session.sets.count }

    var progress: Double {
        totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount)
    }

    var volumeKg: Double { session.totalVolumeKg }

    /// What the same exercise looked like last time, for the "last: …" hints.
    func lastPerformance(for catalogID: String) -> [SetLog] {
        lastPerformances[catalogID] ?? []
    }

    func planItem(for catalogID: String) -> PlanItem? { prescriptions[catalogID] }

    // MARK: - Logging

    /// Marks a set done, checks for a PR, and kicks off the rest timer.
    func complete(_ set: SetLog, restSeconds: Int?) {
        set.isCompleted = true
        set.completedAt = .now
        carryLoadForward(from: set)
        save()

        if TrainingStats.isPersonalRecord(set, in: history + [session]) {
            recentPRs.insert(set.id)
            Haptics.celebrate()
        } else {
            Haptics.log()
        }

        if AppSettings.shared.restTimerAutoStart {
            let seconds = restSeconds ?? AppSettings.shared.defaultRestSeconds
            restTimer.start(seconds: seconds)
        }
    }

    /// Mirrors the load just used onto the remaining sets of the same exercise.
    /// Without this you re-dial the weight for every set of every exercise.
    private func carryLoadForward(from set: SetLog) {
        for other in session.sets
        where other.catalogID == set.catalogID
            && !other.isCompleted
            && other.setIndex > set.setIndex {
            other.weightKg = set.weightKg
            if other.tracking == .duration { other.seconds = set.seconds }
        }
    }

    func uncomplete(_ set: SetLog) {
        set.isCompleted = false
        set.completedAt = nil
        recentPRs.remove(set.id)
        save()
        Haptics.tick()
    }

    func isPR(_ set: SetLog) -> Bool { recentPRs.contains(set.id) }

    // MARK: - Structure edits

    func addSet(to group: SessionExerciseGroup) {
        guard let template = group.sets.last else { return }
        let set = SetLog(
            catalogID: group.catalogID,
            exerciseName: group.name,
            exerciseOrder: group.order,
            setIndex: (group.sets.map(\.setIndex).max() ?? -1) + 1,
            weightKg: template.weightKg,
            reps: template.reps,
            seconds: template.seconds,
            targetRepsLow: template.targetRepsLow,
            targetRepsHigh: template.targetRepsHigh
        )
        set.session = session
        context.insert(set)
        save()
        Haptics.tick()
    }

    func removeLastSet(from group: SessionExerciseGroup) {
        guard group.sets.count > 1, let last = group.sets.last else { return }
        context.delete(last)
        save()
        Haptics.tick()
    }

    func addExercise(_ exercise: CatalogExercise, sets: Int = 3) {
        let order = (session.sets.map(\.exerciseOrder).max() ?? -1) + 1
        if lastPerformances[exercise.id] == nil {
            lastPerformances[exercise.id] = TrainingStats.lastPerformance(
                of: exercise.id, in: history, excluding: session.id
            )
        }
        let last = lastPerformance(for: exercise.id)
        for index in 0..<sets {
            let previous = index < last.count ? last[index] : last.last
            let set = SetLog(
                catalogID: exercise.id,
                exerciseName: exercise.name,
                exerciseOrder: order,
                setIndex: index,
                weightKg: previous?.weightKg ?? 0,
                reps: previous?.reps ?? 10,
                seconds: previous?.seconds ?? 45,
                targetRepsLow: 8,
                targetRepsHigh: 12
            )
            set.session = session
            context.insert(set)
        }
        save()
        Haptics.log()
    }

    func removeExercise(_ group: SessionExerciseGroup) {
        for set in group.sets { context.delete(set) }
        save()
    }

    // MARK: - Ending

    /// Drops any sets left unlogged and stamps the session finished.
    func finish() {
        for set in session.sets where !set.isCompleted {
            context.delete(set)
        }
        session.endedAt = .now
        restTimer.stop()
        save()
        Haptics.success()
    }

    func discard() {
        restTimer.stop()
        context.delete(session)
        save()
    }

    private func save() {
        do { try context.save() } catch {
            assertionFailure("Failed to save workout: \(error)")
        }
    }
}
