import Foundation
import SwiftData

/// Run with scripts/test-widget-snapshot.sh; no simulator is needed.
///
/// STATS-09, widget half. `WidgetPublisher` decided the widgets' done card with
/// `TrainingStats.finishedToday`, which answers "did anything finish today".
/// A freestyle arm pump, or the tail of a session that started last night,
/// then put a victory card over a Leg Day the phone's Today card was still
/// offering. The builder is asked here for the snapshot itself, so the field a
/// widget reads is the one under test.
///
/// What no test here reaches: `write` reloading the timelines, and the widget
/// views drawing `finishedToday`.
@main
@MainActor
struct WidgetSnapshotTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message())")
    }

    static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        doneCardFollowsTheScheduledDay(context)
        fieldsSurvive(context)
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("widget snapshot: all checks passed")
    }

    /// The real clock and calendar, on purpose: the old rule asked
    /// `isDateInToday`, so only sessions that are really today can tell it
    /// from the plan-aware one. Every time is an offset from this morning, so
    /// the checks hold at any hour.
    static let cal = Calendar.current
    static let now = Date()
    static let midnight = cal.startOfDay(for: now)

    static func at(hours: Double) -> Date { midnight.addingTimeInterval(hours * 3600) }

    static func session(_ day: PlanDay?, from start: Date, lasting seconds: TimeInterval = 3600,
                        in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: day?.name ?? "Freestyle", planDayID: day?.id, startedAt: start)
        session.endedAt = start.addingTimeInterval(seconds)
        context.insert(session)
        let set = SetLog(catalogID: "plank", exerciseName: "Plank",
                         exerciseOrder: 0, setIndex: 0, seconds: 60, tracking: .duration)
        set.isCompleted = true
        set.completedAt = session.endedAt
        context.insert(set)
        set.session = session
        return session
    }

    static func plan(in context: ModelContext) -> (Plan, legs: PlanDay, push: PlanDay) {
        let plan = Plan(name: "Test plan", isActive: true)
        context.insert(plan)
        let weekday = cal.component(.weekday, from: now)
        func day(_ name: String, weekday: Int) -> PlanDay {
            let day = PlanDay(name: name, order: plan.days.count, weekday: weekday)
            context.insert(day)
            day.plan = plan
            let item = PlanItem(catalogID: "plank", name: "Plank", order: 0)
            context.insert(item)
            item.day = day
            return day
        }
        return (plan, day("Legs", weekday: weekday), day("Push", weekday: weekday % 7 + 1))
    }

    static func snapshot(_ plan: Plan, _ sessions: [WorkoutSession]) -> GymTrackSnapshot {
        WidgetPublisher.snapshot(plans: [plan], sessions: sessions, running: nil, calendar: cal, now: now)
    }

    /// Legs is pinned to today's weekday. Only a session of the plan that
    /// started today may put the widget on its done card.
    static func doneCardFollowsTheScheduledDay(_ context: ModelContext) {
        let (plan, legs, push) = plan(in: context)

        expect(snapshot(plan, []).finishedToday == nil,
               "no session yet must leave the scheduled day on the widget")

        let freestyle = session(nil, from: at(hours: 0.1), in: context)
        expect(snapshot(plan, [freestyle]).finishedToday == nil,
               "a freestyle session must not hide today's Legs behind the done card")

        let lastNight = session(legs, from: at(hours: -0.8), lasting: 90 * 60, in: context)
        expect(snapshot(plan, [lastNight]).finishedToday == nil,
               "the tail of a session that started yesterday must not count as today's")

        let swapped = session(push, from: at(hours: 0.2), in: context)
        expect(snapshot(plan, [swapped]).finishedToday?.title == "Push",
               "a plan day swapped in for Legs is today's workout")

        let trained = session(legs, from: at(hours: 0.3), in: context)
        expect(snapshot(plan, [freestyle, swapped, trained]).finishedToday?.title == "Legs",
               "the scheduled day wins when it was trained")
    }

    /// The card still carries what the widgets draw: the set count, the
    /// volume, the end time, and the rest of the snapshot is untouched.
    static func fieldsSurvive(_ context: ModelContext) {
        let (plan, legs, _) = plan(in: context)
        let trained = session(legs, from: at(hours: 0.3), lasting: 45 * 60, in: context)
        let snapshot = snapshot(plan, [trained])
        let finished = snapshot.finishedToday
        expect(finished?.sets == trained.effortSets.count, "the done card keeps its set count")
        expect(finished?.volumeKg == trained.totalVolumeKg, "the done card keeps its volume")
        expect(finished?.endedAt == trained.endedAt, "the done card keeps its end time")
        expect(snapshot.hasPlan, "the plan is still reported")
        expect(snapshot.day == midnight, "the snapshot is stamped with the day asked about")
        expect(snapshot.session == nil, "no logger means no running session")
    }
}
