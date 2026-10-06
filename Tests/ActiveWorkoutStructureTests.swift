import Foundation
import SwiftData

/// Run with scripts/test-active-workout-structure.sh; no simulator is needed.
@main
struct ActiveWorkoutStructureTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let plan = Plan(name: "Repeated slots")
        let day = PlanDay(name: "Strength", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)

        @discardableResult
        func item(_ id: String, order: Int, count: Int, load: Double, reps: Int) -> PlanItem {
            let row = PlanItem(catalogID: id, name: id, order: order,
                               targetSets: count, targetRepsLow: reps,
                               targetRepsHigh: reps, targetWeightKg: load)
            row.day = day
            context.insert(row)
            return row
        }
        let topSlot = item("repeat-test", order: 0, count: 2, load: 30, reps: 6)
        item("other-test", order: 1, count: 1, load: 20, reps: 8)
        let backOffSlot = item("repeat-test", order: 2, count: 3, load: 45, reps: 10)

        // Last week's run of the same day, folded into one exercise as every
        // session built since GT-011 is: a heavy pair, then a lighter three.
        let past = WorkoutSession(title: "Previous", startedAt: .now.addingTimeInterval(-86_400 * 7))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        context.insert(past)
        for (index, (load, reps)) in [(60.0, 6), (60, 6), (40, 10), (40, 10), (40, 10)].enumerated() {
            let pastSet = SetLog(catalogID: "repeat-test", exerciseName: "repeat-test",
                                 exerciseOrder: 0, setIndex: index, weightKg: load, reps: reps,
                                 targetRepsLow: reps, targetRepsHigh: reps, tracking: .weightReps)
            pastSet.isCompleted = true
            pastSet.completedAt = past.endedAt
            pastSet.session = past
            context.insert(pastSet)
        }

        let session = SessionFactory.build(day: day, plan: plan, context: context, history: [past])
        let initial = session.exerciseGroups
        let topNext = topSlot.loadScale.step(kg: 60, by: 1)
        let backOffNext = backOffSlot.loadScale.step(kg: 40, by: 1)
        precondition(initial.map(\.catalogID) == ["repeat-test", "other-test"])
        precondition(initial[0].sets.map(\.setIndex) == Array(0..<5))
        precondition(initial[0].sets.map(\.weightKg) == [topNext, topNext, backOffNext, backOffNext, backOffNext],
                     "Each repeated slot must progress from its own share of last time")
        precondition(initial[0].sets.map(\.reps) == [6, 6, 10, 10, 10])
        precondition(initial[0].sets.map(\.targetRepsLow) == [6, 6, 10, 10, 10])
        precondition(Set(initial[0].sets.map(\.exerciseOrder)).count == 1)

        let workout = ActiveWorkout(session: session, context: context, history: [past])
        let opener = workout.groups[0].sets[0]
        opener.weightKg = 70
        workout.complete(opener, restSeconds: nil)
        precondition(workout.groups[0].sets.map(\.weightKg) == [70, 70, backOffNext, backOffNext, backOffNext],
                     "The first log carries its load through its own slot and no further")
        let backOffOpener = workout.groups[0].sets[2]
        backOffOpener.weightKg = 50
        workout.complete(backOffOpener, restSeconds: nil)
        precondition(workout.groups[0].sets.map(\.weightKg) == [70, 70, 50, 50, 50],
                     "The back-off slot carries its own load, and never back into the top slot")
        let repeated = CatalogExercise(id: "repeat-test", name: "repeat-test", category: "strength",
                                       muscleGroups: [], equipment: [], details: nil,
                                       difficulty: nil, tracking: .weightReps)
        workout.addExercise(repeated, sets: 2)
        precondition(workout.groups[0].sets.map(\.setIndex) == Array(0..<7),
                     "Freestyle repeats must append to the same exercise")
        precondition(workout.groups[0].sets.suffix(2).allSatisfy { $0.weightKg == 50 && $0.reps == 10 },
                     "Added rows should inherit the current working set")
        workout.addSet(to: workout.groups[0])
        precondition(workout.groups[0].sets.map(\.setIndex) == Array(0..<8))
        workout.removeLastSet(from: workout.groups[0])
        precondition(workout.groups[0].sets.map(\.setIndex) == Array(0..<7))

        let first = workout.groups[0].sets[0]
        first.isCompleted = true
        workout.continueSet(first)
        precondition(workout.groups[0].sets.map(\.setIndex) == Array(0..<8))
        let continuation = workout.groups[0].sets[1]
        precondition(continuation.isContinuation)
        workout.removeContinuation(continuation)
        precondition(workout.groups[0].sets.map(\.setIndex) == Array(0..<7))

        let mirror = WatchSnapshotFactory.snapshot(for: session, rest: (nil, nil, 0),
                                                   restSeconds: { _ in 90 }, lastTimeLabel: { _ in nil })
        precondition(mirror.exercises.map(\.id) == ["repeat-test", "other-test"])
        precondition(mirror.exercises[0].sets.map(\.index) == Array(0..<7),
                     "The wrist must receive the same single ordered exercise")

        let rated = WorkoutSession(title: "Nudge undo")
        context.insert(rated)
        let source = SetLog(catalogID: "repeat-test", exerciseName: "repeat-test",
                            exerciseOrder: 0, setIndex: 0, weightKg: 40, reps: 12,
                            targetRepsLow: 8, targetRepsHigh: 12, tracking: .weightReps)
        source.isCompleted = true
        source.completedAt = .now
        source.session = rated
        context.insert(source)
        for index in 1...2 {
            let next = SetLog(catalogID: "repeat-test", exerciseName: "repeat-test",
                              exerciseOrder: 0, setIndex: index, weightKg: 40, reps: 8,
                              targetRepsLow: 8, targetRepsHigh: 12, tracking: .weightReps)
            next.session = rated
            context.insert(next)
        }
        let nudged = ActiveWorkout(session: rated, context: context, history: [])
        nudged.rate(source, feel: .easy)
        guard let firstOffer = nudged.pendingNudge(for: source.catalogID) else { preconditionFailure("Missing upward offer") }
        nudged.apply(firstOffer)
        source.reps = 5
        nudged.rate(source, feel: .allOut)
        guard let secondOffer = nudged.pendingNudge(for: source.catalogID) else { preconditionFailure("Missing downward offer") }
        nudged.apply(secondOffer)
        nudged.undoTakenNudge(nudged.takenNudge(for: source.catalogID)!)
        precondition(rated.sets.filter { !$0.isCompleted }.allSatisfy { $0.weightKg == 40 },
                     "Undo must restore the load from before either take")
        precondition(source.loadNudgeOutcome == nil)

        let legacy = WorkoutSession(title: "Old duplicate slots")
        context.insert(legacy)
        let oldFirst = SetLog(catalogID: "repeat-test", exerciseName: "repeat-test",
                              exerciseOrder: 0, setIndex: 0, weightKg: 30, reps: 6)
        let oldSecond = SetLog(catalogID: "repeat-test", exerciseName: "repeat-test",
                               exerciseOrder: 2, setIndex: 0, weightKg: 45, reps: 10)
        for set in [oldFirst, oldSecond] {
            set.isCompleted = true
            set.completedAt = .now
            set.session = legacy
            context.insert(set)
        }
        legacy.endedAt = .now
        precondition(legacy.exerciseGroups[0].sets.map(\.id) == [oldFirst.id, oldSecond.id])
        precondition(TrainingStats.history(for: "repeat-test", in: [legacy])[0].sets.map(\.id)
                     == [oldFirst.id, oldSecond.id])
        precondition(TrainingStats.lastPerformance(of: "repeat-test", in: [legacy]).map(\.id)
                     == [oldFirst.id, oldSecond.id])
        precondition(oldSecond.setIndex == 0, "Finished logs retain their original stored data")

        let closedContainer = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let closedContext = ModelContext(closedContainer)
        let closed = WorkoutSession(title: "Finished on the watch")
        closed.endedAt = .now
        let finalSet = SetLog(catalogID: "repeat-test", exerciseName: "repeat-test",
                              exerciseOrder: 0, setIndex: 0, weightKg: 55, reps: 8)
        finalSet.isCompleted = true
        finalSet.completedAt = .now
        finalSet.session = closed
        closedContext.insert(closed)
        closedContext.insert(finalSet)
        try closedContext.save()
        WatchCommandCenter.shared.configure(container: closedContainer)
        WatchCommandCenter.shared.handle(.undoSet(id: finalSet.id))
        WatchCommandCenter.shared.handle(.logSet(id: finalSet.id, weightKg: 20,
                                                 reps: 2, seconds: 0, at: .now))
        let storedSet = try ModelContext(closedContainer).fetch(FetchDescriptor<SetLog>()).first
        precondition(storedSet?.isCompleted == true && storedSet?.weightKg == 55 && storedSet?.reps == 8,
                     "Queued set commands cannot rewrite a closed Finish batch")

        try repeatedSlotHistoryChecks()
        print("Repeated slots, nudge undo, and closed-session watch commands passed")
    }

    /// A session built from a day, logged and finished, has to feed the next
    /// build of that day slot by slot, including when two slots share a range
    /// and only their set counts tell them apart.
    @MainActor static func repeatedSlotHistoryChecks() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let plan = Plan(name: "Same range")
        let day = PlanDay(name: "Volume", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        // What DayEditorView.add writes: 8-12 and no load, for both slots.
        var slots: [PlanItem] = []
        for (order, (id, count)) in [("repeat-test", 2), ("other-test", 1), ("repeat-test", 3)].enumerated() {
            let row = PlanItem(catalogID: id, name: id, order: order, targetSets: count)
            row.day = day
            context.insert(row)
            slots.append(row)
        }

        let first = SessionFactory.build(day: day, plan: plan, context: context, history: [])
        first.startedAt = .now.addingTimeInterval(-86_400 * 7)
        let workout = ActiveWorkout(session: first, context: context, history: [])
        let rows = workout.groups[0].sets
        precondition(rows.count == 5 && rows.allSatisfy { $0.weightKg == 0 })
        rows[0].weightKg = 60
        rows[0].reps = 12
        workout.complete(rows[0], restSeconds: nil)
        precondition(rows.map(\.weightKg) == [60, 60, 0, 0, 0],
                     "Slots sharing a range still end where the day's set count says")
        rows[2].weightKg = 40
        rows[2].reps = 12
        workout.complete(rows[2], restSeconds: nil)
        precondition(rows.map(\.weightKg) == [60, 60, 40, 40, 40])
        for row in rows where !row.isCompleted {
            row.reps = row.weightKg == 60 ? 12 : 9
            workout.complete(row, restSeconds: nil)
        }
        first.endedAt = .now.addingTimeInterval(-86_400 * 7 + 3_600)

        let next = SessionFactory.build(day: day, plan: plan, context: context, history: [first])
        let opened = next.exerciseGroups[0].sets
        let topNext = slots[0].loadScale.step(kg: 60, by: 1)
        precondition(opened.map(\.weightKg) == [topNext, topNext, 40, 40, 40],
                     "The cleared slot climbs; the slot short of its range holds its own load")
        precondition(opened.map(\.reps) == [8, 8, 12, 9, 9],
                     "The climb resets to the bottom of the range; the hold keeps last time's reps")
    }
}
