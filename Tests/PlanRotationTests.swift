import Foundation
import SwiftData

/// Run with scripts/test-plan-rotation.sh; no simulator is needed.
///
/// Days that "Add day" creates are pinned to no weekday. Before rotation, a
/// routine made only of them was never scheduled, and every day read as a
/// rest day.
@main
struct PlanRotationTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let calendar = Calendar.current
        let today = Date.now
        let weekday = calendar.component(.weekday, from: today)
        let otherWeekday = weekday % 7 + 1

        func makeDay(_ name: String, in plan: Plan, weekday: Int? = nil,
                     isRest: Bool = false, trained: Bool = true) -> PlanDay {
            let day = PlanDay(name: name, order: plan.days.count, weekday: weekday, isRest: isRest)
            context.insert(day)
            day.plan = plan
            if trained {
                let item = PlanItem(catalogID: "plank", name: "Plank", order: 0)
                context.insert(item)
                item.day = day
            }
            return day
        }

        var hoursAgo = 0
        func finished(_ day: PlanDay?, logged: Bool = true) -> WorkoutSession {
            hoursAgo -= 24
            let session = WorkoutSession(title: day?.name ?? "Freestyle", planDayID: day?.id,
                                         startedAt: today.addingTimeInterval(TimeInterval(hoursAgo * 3600)))
            session.endedAt = session.startedAt.addingTimeInterval(3600)
            context.insert(session)
            if logged {
                let set = SetLog(catalogID: "plank", exerciseName: "Plank",
                                 exerciseOrder: 0, setIndex: 0, seconds: 60, tracking: .duration)
                set.isCompleted = true
                set.completedAt = session.endedAt
                context.insert(set)
                set.session = session
            }
            return session
        }

        let plan = Plan(name: "PPL", isActive: true)
        context.insert(plan)
        let push = makeDay("Push", in: plan)
        let pull = makeDay("Pull", in: plan)
        let legs = makeDay("Legs", in: plan)
        _ = makeDay("Rest", in: plan, isRest: true)
        _ = makeDay("New Day", in: plan, trained: false)
        try context.save()

        precondition(plan.day(for: today) == nil, "The fixture must have nothing pinned to today")
        precondition(plan.nextDay(on: today, after: [], calendar: calendar)?.id == push.id,
                     "With no history the rotation starts at the first unpinned day")

        // Sessions are created newest first: each call is a day older.
        let pullDone = finished(pull)
        precondition(plan.nextDay(on: today, after: [pullDone], calendar: calendar)?.id == legs.id,
                     "After Pull comes Legs")

        let legsDone = finished(legs)
        precondition(plan.nextDay(on: today, after: [legsDone], calendar: calendar)?.id == push.id,
                     "After the last training day the rotation wraps, past the rest and empty days, to the first")

        // Newer sessions that say nothing about the rotation are passed over.
        hoursAgo = 0
        let emptyLegs = finished(legs, logged: false)
        let freestyle = finished(nil)
        let otherPlan = WorkoutSession(title: "Elsewhere", planDayID: UUID(), startedAt: today)
        otherPlan.endedAt = today
        context.insert(otherPlan)
        let running = WorkoutSession(title: "Legs", planDayID: legs.id, startedAt: today)
        context.insert(running)
        let olderPull = finished(pull)
        let history = [emptyLegs, freestyle, otherPlan, running, olderPull]
        precondition(plan.nextDay(on: today, after: history, calendar: calendar)?.id == legs.id,
                     "An empty, freestyle, foreign or running session must not move the rotation on")

        // A day pinned to this weekday wins over the rotation. One pinned to
        // another weekday still moves the rotation on past its place.
        let pinned = makeDay("Pinned", in: plan, weekday: weekday)
        precondition(plan.nextDay(on: today, after: [pullDone], calendar: calendar)?.id == pinned.id,
                     "A day pinned to today's weekday wins")
        pinned.weekday = otherWeekday
        let pinnedDone = finished(pinned)
        precondition(plan.nextDay(on: today, after: [pinnedDone], calendar: calendar)?.id == push.id,
                     "After a pinned day the rotation carries on with the next unpinned one, wrapping round")

        // A weekday outside 1...7 is how a store written before Restore
        // checked it reads, and it counts as unpinned.
        pinned.weekday = 9
        precondition(plan.nextDay(on: today, after: [pullDone], calendar: calendar)?.id == legs.id)
        precondition(plan.nextDay(on: today, after: [legsDone], calendar: calendar)?.id == pinned.id,
                     "An out-of-range weekday rotates like an unpinned day")

        // Everything pinned, and nothing to today: that is a rest day.
        let fixed = Plan(name: "Fixed")
        context.insert(fixed)
        _ = makeDay("Upper", in: fixed, weekday: otherWeekday)
        _ = makeDay("Unpinned rest", in: fixed, isRest: true)
        precondition(fixed.nextDay(on: today, after: [], calendar: calendar) == nil,
                     "A fully pinned plan still has rest days")
        let lower = makeDay("Lower", in: fixed, weekday: weekday)
        precondition(fixed.nextDay(on: today, after: [], calendar: calendar)?.id == lower.id)

        print("Plan rotation checks passed")
    }
}
