import Foundation
import SwiftData

/// Run with scripts/test-exercise-removal.sh; no simulator is needed.
///
/// The logger's counts and the way an exercise added by mistake comes back out:
/// the header, tick bar and cards counted drop rows as sets while every other
/// surface counted efforts (LOG-08), and `removeExercise` had no caller and no
/// rule about what it could take (LOG-15). The view changes for LOG-11 and
/// LIB-07 (no menu over the steppers, no sheet for a deleted exercise) are
/// not testable here and are covered by reading.
@main
struct ExerciseRemovalTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        try dropRowsAreNotSets(context)
        try onlyAnUnloggedAddedExerciseCanGo(context)
        try removalLeavesNothingBehind(context)
        try removalRefusesWhatItMayNotTake(context)
        deletedExerciseHasNoCatalogEntry()
        print("Exercise removal tests passed")
    }

    @MainActor @discardableResult
    static func row(_ id: String, order: Int, index: Int, in session: WorkoutSession,
                    context: ModelContext, loggedAt: Date? = nil,
                    continuation: Bool = false) -> SetLog {
        let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: order, setIndex: index,
                         weightKg: 60, reps: 8, seconds: 0,
                         targetRepsLow: 0, targetRepsHigh: 0, tracking: .weightReps)
        if let loggedAt {
            set.isCompleted = true
            set.completedAt = loggedAt
        }
        if continuation { set.continuesPreviousSet = true }
        set.session = session
        context.insert(set)
        return set
    }

    static func exercise(_ id: String) -> CatalogExercise {
        CatalogExercise(id: id, name: id, category: "strength", muscleGroups: [], equipment: [],
                        details: nil, difficulty: nil, tracking: .weightReps)
    }

    // MARK: LOG-08

    /// Three sets with one drop after set 2 is four rows and three efforts. The
    /// summary and the dock say three; the logger used to say four.
    @MainActor static func dropRowsAreNotSets(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-1_800)
        let session = WorkoutSession(title: "Drops", startedAt: t0)
        context.insert(session)
        let a1 = row("A-count", order: 0, index: 0, in: session, context: context)
        let a2 = row("A-count", order: 0, index: 1, in: session, context: context)
        let drop = row("A-count", order: 0, index: 2, in: session, context: context, continuation: true)
        let a3 = row("A-count", order: 0, index: 3, in: session, context: context)
        let b1 = row("B-count", order: 1, index: 0, in: session, context: context)
        try context.save()

        let workout = ActiveWorkout(session: session, context: context, history: [])
        precondition(workout.totalCount == 4 && session.sets.count == 5,
                     "Four efforts across five rows; the row count is what the header used to print")
        precondition(workout.completedCount == 0)

        workout.complete(a1, restSeconds: nil, at: t0.addingTimeInterval(60))
        workout.complete(a2, restSeconds: nil, at: t0.addingTimeInterval(240))
        workout.complete(drop, restSeconds: nil, at: t0.addingTimeInterval(300))
        let group = workout.groups[0]
        precondition(session.sets.filter(\.isCompleted).count == 3, "Three rows are logged")
        precondition(workout.completedCount == 2,
                     "The drop belongs to set 2 and adds nothing of its own")
        precondition(workout.loggedEffortCount(in: group) == 2 && group.effortCount == 3,
                     "The card and the queue read 2/3, the number its row badges already show")
        precondition(workout.completedCount == session.effortSets.count,
                     "The logger's count is the summary's count at every point of the session")

        workout.complete(a3, restSeconds: nil, at: t0.addingTimeInterval(500))
        workout.complete(b1, restSeconds: nil, at: t0.addingTimeInterval(700))
        precondition(workout.completedCount == 4 && workout.totalCount == 4)
        precondition(workout.completedCount == session.effortSets.count)
    }

    // MARK: LOG-15

    /// A planned exercise stays even when nothing is logged on it, because
    /// leaving it unlogged already says it was skipped. A freestyle one, or one
    /// added on top of a plan, can go until a set is logged on it, and undoing
    /// that set gives it back.
    @MainActor static func onlyAnUnloggedAddedExerciseCanGo(_ context: ModelContext) throws {
        let plan = Plan(name: "Removal")
        let day = PlanDay(name: "Day", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        let planned = PlanItem(catalogID: "planned-removal", name: "planned-removal", order: 0,
                               targetSets: 2, targetRepsLow: 8, targetRepsHigh: 8, targetWeightKg: 40)
        planned.day = day
        context.insert(planned)
        let session = SessionFactory.build(day: day, plan: plan, context: context, history: [])
        try context.save()

        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.addExercise(exercise("mistake-removal"), sets: 3)
        let plannedGroup = workout.groups.first { $0.catalogID == "planned-removal" }!
        let addedGroup = workout.groups.first { $0.catalogID == "mistake-removal" }!

        precondition(!workout.canRemove(plannedGroup),
                     "A planned exercise is skipped by leaving it, not removed")
        precondition(workout.canRemove(addedGroup), "Added on the day, nothing logged")

        workout.complete(addedGroup.sets[0], restSeconds: nil)
        precondition(!workout.canRemove(workout.groups.first { $0.catalogID == "mistake-removal" }!),
                     "A logged set is data; undoing it is what says the lifter means it")
        workout.uncomplete(addedGroup.sets[0])
        precondition(workout.canRemove(workout.groups.first { $0.catalogID == "mistake-removal" }!),
                     "An undone set leaves the exercise as if nothing had been logged")

        let staleCopy = addedGroup
        workout.complete(addedGroup.sets[1], restSeconds: nil)
        precondition(!workout.canRemove(staleCopy),
                     "A card drawn before the log still can't be removed after it")
        workout.uncomplete(addedGroup.sets[1])

        // Adding the planned lift again lands on its own card, which stays planned.
        workout.addExercise(exercise("planned-removal"), sets: 1)
        precondition(!workout.canRemove(workout.groups.first { $0.catalogID == "planned-removal" }!))

        let freestyle = ActiveWorkout.startFreestyle(context: context, history: [])
        freestyle.addExercise(exercise("free-removal"), sets: 2)
        precondition(freestyle.canRemove(freestyle.groups[0]),
                     "Nothing in a freestyle session was planned")
    }

    @MainActor static func removalLeavesNothingBehind(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-900)
        let session = WorkoutSession(title: "Remove", startedAt: t0)
        context.insert(session)
        row("keep-removal", order: 0, index: 0, in: session, context: context, loggedAt: t0)
        row("keep-removal", order: 0, index: 1, in: session, context: context)
        let workout = ActiveWorkout(session: session, context: context, history: [])
        workout.addExercise(exercise("wrong-removal"), sets: 3)
        precondition(workout.openFromQueue("wrong-removal") == false)
        precondition(session.preferredExerciseID == "wrong-removal")
        precondition(workout.currentGroup?.catalogID == "wrong-removal")

        workout.removeExercise(workout.groups.first { $0.catalogID == "wrong-removal" }!)

        precondition(session.sets.allSatisfy { $0.catalogID != "wrong-removal" },
                     "Every row of the removed exercise is gone")
        let remaining = try context.fetch(FetchDescriptor<SetLog>()).filter { $0.session?.id == session.id }
        precondition(remaining.count == 2 && remaining.allSatisfy { $0.catalogID == "keep-removal" },
                     "Nothing outside the removed exercise is touched, logged rows above all")
        precondition(session.preferredExerciseID == nil,
                     "No pick is left naming an exercise that is gone")
        precondition(workout.currentGroup?.catalogID == "keep-removal",
                     "The working position, and so the wrist and the Lock Screen, are back on the lift in progress")
        precondition(workout.totalCount == 2)

        // Adding the same lift again starts clean rather than on the old pick.
        workout.addExercise(exercise("wrong-removal"), sets: 1)
        precondition(workout.currentGroup?.catalogID == "keep-removal",
                     "A removed pick does not come back when the lift is re-added")
    }

    @MainActor static func removalRefusesWhatItMayNotTake(_ context: ModelContext) throws {
        let t0 = Date.now.addingTimeInterval(-600)
        let session = WorkoutSession(title: "Refuse", startedAt: t0)
        context.insert(session)
        row("done-refuse", order: 0, index: 0, in: session, context: context, loggedAt: t0)
        row("done-refuse", order: 0, index: 1, in: session, context: context)
        let workout = ActiveWorkout(session: session, context: context, history: [])

        workout.removeExercise(workout.groups[0])
        precondition(session.sets.count == 2 && session.sets.contains(where: \.isCompleted),
                     "A card with a logged set is never removed, even when asked directly")

        // A set logged after the card was drawn: the copy still lists no logged row.
        let fresh = ActiveWorkout.startFreestyle(context: context, history: [])
        fresh.addExercise(exercise("late-refuse"), sets: 2)
        let stale = fresh.groups[0]
        stale.sets[0].isCompleted = true
        stale.sets[0].completedAt = t0
        fresh.removeExercise(stale)
        precondition(fresh.session.sets.count == 2, "A set logged from the wrist since the card was drawn is kept")
    }

    // MARK: LIB-07

    /// What the logger's scale sheet and info sheet are built from. When it is
    /// nil the caption and the info button must not offer a sheet, which the
    /// view does by reading this same value.
    static func deletedExerciseHasNoCatalogEntry() {
        let gone = SetLog(catalogID: "custom-deleted-removal", exerciseName: "Iso Row",
                          exerciseOrder: 0, setIndex: 0)
        precondition(gone.catalog == nil, "A deleted custom exercise resolves to nothing")
        let known = SetLog(catalogID: ExerciseCatalog.shared.all[0].id, exerciseName: "Known",
                           exerciseOrder: 0, setIndex: 0)
        precondition(known.catalog != nil)
    }
}
