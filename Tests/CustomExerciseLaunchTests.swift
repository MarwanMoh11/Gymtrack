import Foundation
import SwiftData

/// Run with scripts/test-custom-exercise-launch.sh; no simulator is needed.
///
/// A workout started from the watch while the phone app is terminated is built
/// on a background launch, where no view runs. These checks start from an
/// empty custom catalog, which is exactly what that launch sees before
/// `GymTrackApp.configureServices` loads the store.
@main
struct CustomExerciseLaunchTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let hold = CustomExerciseRecord(name: "Farmer Hold", muscles: [], equipment: [],
                                        tracking: .duration)
        let press = CustomExerciseRecord(name: "Gym Press", muscles: [], equipment: ["Machine"],
                                         tracking: .weightReps)
        context.insert(hold)
        context.insert(press)
        context.insert(HiddenExerciseRecord(catalogID: "hidden-test"))

        let plan = Plan(name: "Custom")
        let day = PlanDay(name: "Monday", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        // A slot added before slots kept a snapshot: only the catalog can say
        // this one is timed.
        let slot = PlanItem(catalogID: hold.id, name: hold.name, order: 0, targetSets: 3,
                            targetRepsLow: 0, targetRepsHigh: 0, targetSeconds: 40)
        slot.day = day
        context.insert(slot)
        try context.save()

        func trackings(_ day: PlanDay) -> [TrackingMode] {
            SessionFactory.build(day: day, plan: plan, context: context, history: [])
                .exerciseGroups.flatMap(\.sets).map(\.tracking)
        }

        // The failure, reproduced: nothing has read the store yet.
        ExerciseCatalog.shared.setCustom([])
        ExerciseCatalog.shared.setHidden([])
        precondition(trackings(day) == [.weightReps, .weightReps, .weightReps],
                     "Without the launch load a custom timed slot is built as weight × reps")
        precondition(LoadScaleBook.shared.scale(for: press.id) == LoadScaleBook.derived(for: nil))

        // What configureServices runs, from a fresh context as it does there.
        ExerciseCatalog.shared.loadLibrary(from: ModelContext(container))
        precondition(trackings(day) == [.duration, .duration, .duration],
                     "The launch load must let a headless start build timed rows")
        precondition(ExerciseCatalog.shared.isHidden("hidden-test"),
                     "The launch load must bring the hidden list with it, as RootView does")
        precondition(LoadScaleBook.shared.scale(for: press.id)
                         == LoadScaleBook.derived(for: press.asCatalogExercise),
                     "A custom machine must step on its own ladder from the wrist")
        precondition(LoadScaleBook.derived(for: press.asCatalogExercise) != LoadScaleBook.derived(for: nil))

        try defenceChecks(container: container, hold: hold)
        print("Custom exercise launch tests passed")
    }

    /// The snapshot a new custom slot keeps, and that a tracking edit carries
    /// forward, so a catalog miss can never fall back to weight × reps.
    @MainActor static func defenceChecks(container: ModelContainer, hold: CustomExerciseRecord) throws {
        let context = ModelContext(container)
        let custom = hold.asCatalogExercise
        precondition(custom.slotTrackingSnapshot == TrackingMode.duration.rawValue,
                     "A new custom slot must keep its own record of how it is measured")
        let bundled = ExerciseCatalog.shared.builtIn.first { $0.tracking == .duration }!
        precondition(bundled.slotTrackingSnapshot == nil,
                     "A bundled exercise always resolves and must not gain a plan key in the export")

        let plan = Plan(name: "Snapshotted")
        let day = PlanDay(name: "Tuesday", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        let snapshotted = PlanItem(catalogID: custom.id, name: custom.name, order: 0, targetSets: 2,
                                   targetRepsLow: 0, targetRepsHigh: 0, targetSeconds: 40)
        snapshotted.trackingRaw = custom.slotTrackingSnapshot
        snapshotted.day = day
        context.insert(snapshotted)
        let other = Plan(name: "Old slot")
        let otherDay = PlanDay(name: "Wednesday", order: 0)
        otherDay.plan = other
        context.insert(other)
        context.insert(otherDay)
        let unsnapshotted = PlanItem(catalogID: custom.id, name: custom.name, order: 0)
        unsnapshotted.day = otherDay
        context.insert(unsnapshotted)
        try context.save()

        ExerciseCatalog.shared.setCustom([])
        let rows = SessionFactory.build(day: day, plan: plan, context: context, history: [])
            .exerciseGroups.flatMap(\.sets)
        precondition(rows.map(\.tracking) == [.duration, .duration],
                     "A snapshotted custom slot must stay timed when the catalog misses")

        try context.retrackPlanSlots(of: custom.id, to: .bodyweightReps)
        precondition(snapshotted.trackingRaw == TrackingMode.bodyweightReps.rawValue,
                     "A tracking edit must carry onto the slot's snapshot")
        precondition(unsnapshotted.trackingRaw == nil,
                     "A slot with no snapshot keeps following the catalog and gains no key")
        precondition(snapshotted.targetRepsLow == 8 && snapshotted.targetRepsHigh == 12,
                     "A slot added while timed must gain the range a new reps slot starts on")

        // A range the lifter chose is theirs, whichever way the tracking moves.
        unsnapshotted.targetRepsLow = 5
        unsnapshotted.targetRepsHigh = 5
        try context.retrackPlanSlots(of: custom.id, to: .weightReps)
        precondition(unsnapshotted.targetRepsLow == 5 && unsnapshotted.targetRepsHigh == 5,
                     "A range that was set must survive a tracking edit")
        try context.retrackPlanSlots(of: custom.id, to: .duration)
        precondition(snapshotted.targetRepsLow == 8 && snapshotted.trackingRaw == TrackingMode.duration.rawValue,
                     "Moving to a timed mode leaves the range alone, so a move back finds it intact")
    }
}
