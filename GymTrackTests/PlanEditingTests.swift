import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// What a routine offers on a given day, and what editing one does to it.
///
/// Days that "Add day" creates are pinned to no weekday. Before rotation, a
/// routine made only of them was never scheduled, and every day read as a rest
/// day. Editing has its own rules: deleting a slot keeps the order dense, and
/// deleting a routine never reaches the history trained from it.
///
/// Weekdays come from `TestClock`, so a pinned day lands on the same date
/// whatever the runner's zone. Pinning and scheduling by weekday alone are in
/// `EntityPersistenceTests`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct PlanEditingTests {

    private let today = TestClock.reference
    private let calendar = TestClock.calendar
    private var weekday: Int { calendar.component(.weekday, from: today) }
    private var otherWeekday: Int { weekday % 7 + 1 }

    /// Push, Pull and Legs in turn on no fixed day, then a rest day and a day
    /// "Add day" made and nobody filled.
    private struct Rotation {
        let context: ModelContext
        let plan: Plan
        let push: PlanDay
        let pull: PlanDay
        let legs: PlanDay
    }

    private func rotation() throws -> Rotation {
        let context = try TestStore.context()
        let plan = Plan(name: "PPL", isActive: true)
        context.insert(plan)
        let push = day("Push", in: plan, context: context)
        let pull = day("Pull", in: plan, context: context)
        let legs = day("Legs", in: plan, context: context)
        day("Rest", in: plan, isRest: true, context: context)
        day("New Day", in: plan, trained: false, context: context)
        try context.save()
        return Rotation(context: context, plan: plan, push: push, pull: pull, legs: legs)
    }

    @discardableResult
    private func day(_ name: String, in plan: Plan, weekday: Int? = nil, isRest: Bool = false,
                     trained: Bool = true, context: ModelContext) -> PlanDay {
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

    /// A session of `day`, finished `daysAgo` days before today. Nothing is
    /// logged on it unless `logged`.
    private func finished(_ day: PlanDay?, daysAgo: Int, logged: Bool = true,
                          in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: day?.name ?? "Freestyle", planDayID: day?.id,
                                     startedAt: today.addingTimeInterval(TimeInterval(-daysAgo * 86_400)))
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

    // MARK: - The rotation

    @Test func withNoHistoryTheRotationStartsAtTheFirstUnpinnedDay() throws {
        let fixture = try rotation()
        #expect(fixture.plan.day(for: today, calendar: calendar) == nil, "nothing is pinned to today")
        #expect(fixture.plan.nextDay(on: today, after: [], calendar: calendar)?.id == fixture.push.id)
    }

    @Test func theRotationFollowsTheLastDayTrainedAndWrapsPastRestAndEmptyDays() throws {
        let fixture = try rotation()
        let pullDone = finished(fixture.pull, daysAgo: 1, in: fixture.context)
        #expect(fixture.plan.nextDay(on: today, after: [pullDone], calendar: calendar)?.id == fixture.legs.id)

        let legsDone = finished(fixture.legs, daysAgo: 2, in: fixture.context)
        #expect(fixture.plan.nextDay(on: today, after: [legsDone], calendar: calendar)?.id == fixture.push.id)
    }

    @Test func anEmptyFreestyleForeignOrRunningSessionDoesNotMoveTheRotationOn() throws {
        let fixture = try rotation()
        let context = fixture.context
        let emptyLegs = finished(fixture.legs, daysAgo: 1, logged: false, in: context)
        let freestyle = finished(nil, daysAgo: 2, in: context)
        let otherPlan = WorkoutSession(title: "Elsewhere", planDayID: UUID(), startedAt: today)
        otherPlan.endedAt = today
        context.insert(otherPlan)
        let running = WorkoutSession(title: "Legs", planDayID: fixture.legs.id, startedAt: today)
        context.insert(running)
        let olderPull = finished(fixture.pull, daysAgo: 3, in: context)

        let history = [emptyLegs, freestyle, otherPlan, running, olderPull]
        #expect(fixture.plan.nextDay(on: today, after: history, calendar: calendar)?.id == fixture.legs.id)
    }

    @Test func aDayPinnedToTodayWinsAndOnePinnedElsewhereStillMovesTheRotationOn() throws {
        let fixture = try rotation()
        let pullDone = finished(fixture.pull, daysAgo: 1, in: fixture.context)
        let pinned = day("Pinned", in: fixture.plan, weekday: weekday, context: fixture.context)
        #expect(fixture.plan.nextDay(on: today, after: [pullDone], calendar: calendar)?.id == pinned.id)

        // Pinned elsewhere, it has a place in the order the rotation carries
        // on from, wrapping round to the first unpinned day.
        pinned.weekday = otherWeekday
        let pinnedDone = finished(pinned, daysAgo: 4, in: fixture.context)
        #expect(fixture.plan.nextDay(on: today, after: [pinnedDone], calendar: calendar)?.id == fixture.push.id)
    }

    /// Training late is still the night's training. Until 04:00 the next
    /// morning the day pinned to tonight's weekday is the one on offer, and
    /// from 04:00 the next weekday's is. `today` is Wednesday 11 March at noon.
    @Test func theSmallHoursStillOfferTheNightsPinnedDay() throws {
        let context = try TestStore.context()
        let fixed = Plan(name: "Fixed")
        context.insert(fixed)
        let tonight = day("Tonight", in: fixed, weekday: weekday, context: context)
        let tomorrow = day("Tomorrow", in: fixed, weekday: otherWeekday, context: context)

        for stamp in ["2026-03-12T00:00:00", "2026-03-12T00:30:00", "2026-03-12T03:59:59"] {
            let night = TestClock.at(stamp)
            #expect(fixed.day(for: night, calendar: calendar)?.id == tonight.id, "\(stamp)")
            #expect(fixed.nextDay(on: night, after: [], calendar: calendar)?.id == tonight.id, "\(stamp)")
        }
        let morning = TestClock.at("2026-03-12T04:00:00")
        #expect(fixed.day(for: morning, calendar: calendar)?.id == tomorrow.id)
        #expect(fixed.nextDay(on: morning, after: [], calendar: calendar)?.id == tomorrow.id)
    }

    @Test func aFullyPinnedPlanStillHasRestDays() throws {
        let context = try TestStore.context()
        let fixed = Plan(name: "Fixed")
        context.insert(fixed)
        day("Upper", in: fixed, weekday: otherWeekday, context: context)
        day("Unpinned rest", in: fixed, isRest: true, context: context)
        #expect(fixed.nextDay(on: today, after: [], calendar: calendar) == nil)

        let lower = day("Lower", in: fixed, weekday: weekday, context: context)
        #expect(fixed.nextDay(on: today, after: [], calendar: calendar)?.id == lower.id)
    }

    // MARK: - Slots

    private func addItem(_ name: String, to day: PlanDay, in context: ModelContext) {
        let item = PlanItem(catalogID: name, name: name, order: day.nextItemOrder, targetSets: 3,
                            targetRepsLow: 8, targetRepsHigh: 12)
        item.day = day
        context.insert(item)
    }

    private func dayOfFour(in context: ModelContext) throws -> PlanDay {
        let plan = Plan(name: "P")
        let day = PlanDay(name: "D", order: 0)
        day.plan = plan
        context.insert(plan)
        context.insert(day)
        for name in ["A", "B", "C", "D"] { addItem(name, to: day, in: context) }
        try context.save()
        return day
    }

    @Test func deletingSlotsAndAddingOneKeepsTheOrderDenseAndTheSequence() throws {
        let context = try TestStore.context()
        let day = try dayOfFour(in: context)

        // The first and then a middle one, saving in between as the editor does.
        day.removeItems([day.orderedItems[0]], in: context)
        try context.save()
        day.removeItems([day.orderedItems[1]], in: context)
        try context.save()
        addItem("E", to: day, in: context)
        try context.save()

        let orders = day.orderedItems.map(\.order)
        #expect(orders == Array(0..<orders.count), "orders repeat or skip: \(orders)")
        #expect(day.orderedItems.map(\.name) == ["B", "D", "E"])
    }

    @Test func aSlotAddedBeforeTheDeleteIsSavedSharesNoOrderWithALiveOne() throws {
        let context = try TestStore.context()
        let day = try dayOfFour(in: context)

        // The deleted row is still in the relationship until the next save.
        let doomed = day.orderedItems[0]
        day.removeItems([doomed], in: context)
        addItem("F", to: day, in: context)

        let live = day.orderedItems.filter { $0 !== doomed }
        #expect(Set(live.map(\.order)).count == live.count, "two live items share an order: \(live.map(\.order))")
    }

    // MARK: - Deleting a routine

    /// Two blank routines, the first active and holding a day with a finished
    /// session's history.
    private struct Routines {
        let first: Plan
        let second: Plan
        let day: PlanDay
    }

    private func routines(in context: ModelContext) throws -> Routines {
        let first = Plan.blank(in: context, makeActive: true)
        first.createdAt = Date(timeIntervalSince1970: 1)
        let second = Plan.blank(in: context, makeActive: false)
        second.createdAt = Date(timeIntervalSince1970: 2)
        let day = PlanDay(name: "Push", order: 0)
        day.plan = first
        context.insert(day)
        addItem("bench", to: day, in: context)

        let finished = WorkoutSession(title: "Push", planDayID: day.id, planName: "My Routine",
                                      startedAt: today.addingTimeInterval(-86_400))
        finished.endedAt = finished.startedAt.addingTimeInterval(3600)
        context.insert(finished)
        let set = SetLog(catalogID: "bench", exerciseName: "Bench", exerciseOrder: 0, setIndex: 0,
                         weightKg: 60, reps: 8)
        set.session = finished
        context.insert(set)
        try context.save()
        return Routines(first: first, second: second, day: day)
    }

    @Test func aRoutineWithAnOpenSessionCannotBeDeleted() throws {
        let context = try TestStore.context()
        let fixture = try routines(in: context)
        let open = WorkoutSession(title: "Push", planDayID: fixture.day.id, planName: "My Routine", startedAt: today)
        context.insert(open)
        try context.save()

        #expect(!Plan.remove(fixture.first, among: [fixture.first, fixture.second], openSessions: [open], in: context))
        #expect(fixture.first.modelContext != nil)
        #expect(fixture.first.isActive)
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 2)
    }

    @Test func deletingTheActiveRoutineHandsActiveOnAndLeavesItsHistory() throws {
        let context = try TestStore.context()
        let fixture = try routines(in: context)
        // A session from it that has since been finished no longer blocks.
        let closed = WorkoutSession(title: "Push", planDayID: fixture.day.id, planName: "My Routine", startedAt: today)
        closed.endedAt = today.addingTimeInterval(3600)
        context.insert(closed)
        try context.save()

        #expect(Plan.remove(fixture.first, among: [fixture.first, fixture.second], openSessions: [], in: context))
        try context.save()

        #expect(fixture.second.isActive, "the next routine takes over as active")
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 1)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.count == 2, "history is untouched")

        // The last routine can go too, leaving no plan at all.
        #expect(Plan.remove(fixture.second, among: [fixture.second], openSessions: [], in: context))
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 0)
    }
}
