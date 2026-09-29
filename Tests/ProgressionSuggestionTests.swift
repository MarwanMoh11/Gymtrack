import Foundation
import SwiftData

/// Run with scripts/test-progression-suggestion.sh; no simulator is needed.
///
/// What the double progression may conclude from last time, and what the
/// logger opens at because of it.
@main
struct ProgressionSuggestionTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        try partialSessions(context)
        try resetReps(context)
        try bodyweightLibrary(context)
        try missingRange(context)
        print("Progression suggestion tests passed")
    }

    static func sets(_ id: String, _ work: [(Double, Int)], tracking: TrackingMode? = .weightReps,
                     feel: SetFeel? = nil) -> [SetLog] {
        work.enumerated().map { index, pair in
            let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: index,
                             weightKg: pair.0, reps: pair.1, targetRepsLow: 8, targetRepsHigh: 12,
                             tracking: tracking)
            set.isCompleted = true
            set.rpe = feel.map { Double($0.rawValue) }
            return set
        }
    }

    /// STATS-02: only a last time that did the prescribed work moves the load.
    @MainActor static func partialSessions(_ context: ModelContext) throws {
        let item = PlanItem(catalogID: "progress-test", name: "Press", order: 0,
                            targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)
        context.insert(item)

        let finishedEarly = TrainingStats.suggestion(for: item, lastSets: sets("progress-test", [(60, 12)]))
        precondition(finishedEarly.action == .repeatLoad && finishedEarly.weightKg == 60
                     && finishedEarly.reps == 8,
                     "One set at the top of the range is not a session cleared")

        let dropped = TrainingStats.suggestion(
            for: item, lastSets: sets("progress-test", [(60, 12), (60, 12), (57.5, 12)]))
        precondition(dropped.action == .repeatLoad && dropped.weightKg == 60,
                     "Two of three sets at the load has not beaten the load")

        let heavy = PlanItem(catalogID: "progress-test", name: "Press", order: 0,
                             targetSets: 3, targetRepsLow: 6, targetRepsHigh: 8)
        context.insert(heavy)
        let technique = TrainingStats.suggestion(for: heavy, lastSets: sets("progress-test", [(40, 20)]))
        precondition(technique.action != .increaseWeight && technique.weightKg == 40,
                     "A light technique set must not be read as the working range met")

        let cleared = TrainingStats.suggestion(
            for: item, lastSets: sets("progress-test", [(60, 12), (60, 12), (60, 12)]))
        precondition(cleared.action == .increaseWeight && cleared.weightKg > 60,
                     "A session that did the prescribed work still climbs")
    }

    /// GT-012's residue: whenever the load is held or taken down, the sets
    /// open at the prescription rather than last time's short count.
    @MainActor static func resetReps(_ context: ModelContext) throws {
        func opening(after work: [(Double, Int)], feel: SetFeel?) -> [SetLog] {
            let plan = Plan(name: "Reset")
            let day = PlanDay(name: "Day", order: 0)
            day.plan = plan
            let item = PlanItem(catalogID: "progress-test", name: "Press", order: 0,
                                targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)
            item.day = day
            let past = WorkoutSession(title: "Last", startedAt: .now.addingTimeInterval(-86_400))
            past.endedAt = past.startedAt.addingTimeInterval(3_600)
            context.insert(plan)
            context.insert(day)
            context.insert(item)
            context.insert(past)
            for set in sets("progress-test", work, feel: feel) {
                set.session = past
                context.insert(set)
            }
            return SessionFactory.build(day: day, plan: plan, context: context, history: [past])
                .exerciseGroups[0].sets
        }

        let deload = opening(after: [(60, 4), (60, 4), (60, 4)], feel: .hard)
        precondition(deload.allSatisfy { $0.weightKg < 60 && $0.reps == 8 },
                     "A deload opens at the bottom of the range, not at last time's 4")

        let easyShort = opening(after: [(60, 5), (60, 5), (60, 5)], feel: .easy)
        precondition(easyShort.allSatisfy { $0.weightKg == 60 && $0.reps == 8 },
                     "A held load opens at the bottom of the range, not at last time's 5")

        let partial = opening(after: [(60, 12)], feel: nil)
        precondition(partial.allSatisfy { $0.weightKg == 60 && $0.reps == 8 },
                     "A partial session holds the load and opens at the prescription")
    }

    /// LIB-02: bodyweight movements the library filed under strength.
    @MainActor static func bodyweightLibrary(_ context: ModelContext) throws {
        for id in ["chest-dip", "hyper-extension", "tibialis-raise", "ghd-back-extension"] {
            precondition(ExerciseCatalog.shared.exercise(id: id)?.tracking == .bodyweightReps,
                         "\(id) is done at bodyweight")
        }
        for id in ["wrist-roller", "walking-lunge-weighted-vest"] {
            precondition(ExerciseCatalog.shared.exercise(id: id)?.tracking == .weightReps,
                         "\(id) carries a real load")
        }

        // Rows logged before the fix keep the mode they were logged in.
        let dip = PlanItem(catalogID: "chest-dip", name: "Chest Dip", order: 0,
                           targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)
        context.insert(dip)
        let snapshotted = sets("chest-dip", [(0, 12), (0, 12), (0, 12)], tracking: .weightReps)
        precondition(snapshotted.allSatisfy { $0.tracking == .weightReps })
        let dipNext = TrainingStats.suggestion(for: dip, lastSets: snapshotted)
        precondition(dipNext.action != .increaseWeight && dipNext.weightKg == 0,
                     "A clean bodyweight session must not climb to an invented load")

        let unloaded = PlanItem(catalogID: "progress-test", name: "Press", order: 0,
                                targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)
        context.insert(unloaded)
        let zero = TrainingStats.suggestion(
            for: unloaded, lastSets: sets("progress-test", [(0, 12), (0, 12), (0, 12)], feel: .easy))
        precondition(zero.action != .increaseWeight && zero.weightKg == 0,
                     "No mode may climb a rung from a load that was never recorded")
    }

    /// LIB-04: a reps slot on 0-0 has no prescription, not a range met.
    @MainActor static func missingRange(_ context: ModelContext) throws {
        let item = PlanItem(catalogID: "progress-test", name: "Sled Drag", order: 0,
                            targetSets: 3, targetRepsLow: 0, targetRepsHigh: 0)
        context.insert(item)
        let next = TrainingStats.suggestion(
            for: item, lastSets: sets("progress-test", [(60, 10), (60, 10), (60, 10)]))
        precondition(next.action != .increaseWeight && next.weightKg == 60 && next.reps == 10,
                     "A slot with no range holds the load and the reps that were done")
    }
}
