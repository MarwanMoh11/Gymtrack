import Foundation
import SwiftData

/// Run with scripts/test-training-stats-calendar.sh; no simulator is needed.
@main
struct TrainingStatsCalendarTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        try windowsAndBuckets(context)
        try daylightSaving(context)
        try emptySessions(context)
        print("Training window, weekly sessions, daylight saving and empty-session checks passed")
    }

    /// A finished session with one logged set, or with nothing logged.
    @MainActor
    static func session(at start: Date, logged: Bool = true, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: "Calendar test", startedAt: start)
        session.endedAt = start.addingTimeInterval(60)
        context.insert(session)
        if logged {
            let set = SetLog(catalogID: "plank", exerciseName: "Plank",
                             exerciseOrder: 0, setIndex: 0, seconds: 60, tracking: .duration)
            set.isCompleted = true
            set.completedAt = session.endedAt
            session.sets = [set]
        }
        return session
    }

    @MainActor
    static func windowsAndBuckets(_ context: ModelContext) throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)

        func finished(_ offset: Int, logged: Bool = true) -> WorkoutSession {
            session(at: calendar.date(byAdding: .day, value: offset, to: today)!, logged: logged, in: context)
        }

        let fourteenDaysAgo = finished(-14)
        let thirteenDaysAgo = finished(-13)
        let sevenDaysAgo = finished(-7)
        let sixDaysAgo = finished(-6)
        let currentDay = finished(0)
        let tomorrow = finished(1)
        let sessions = [fourteenDaysAgo, thirteenDaysAgo, sevenDaysAgo,
                        sixDaysAgo, currentDay, tomorrow]

        let current = TrainingStats.sessions(in: sessions, days: 7, calendar: calendar)
        precondition(Set(current.map(\.id)) == Set([sixDaysAgo.id, currentDay.id]),
                     "The seven-day total must match today's chart bucket and the previous six")
        let previous = TrainingStats.previousWindow(sessions, days: 7, calendar: calendar)
        precondition(Set(previous.map(\.id)) == Set([thirteenDaysAgo.id, sevenDaysAgo.id]),
                     "The preceding seven days must meet the current window without a gap")

        let weekly = TrainingStats.weeklySessionCounts(sessions, weeks: 2, calendar: calendar)
        precondition(weekly == [2, 2], "Today's session belongs to the newest weekly sparkline bucket")

        precondition(currentDay.totalVolumeKg == 0)
        let emptyYesterday = finished(-1, logged: false)
        let trained = TrainingStats.trainedDays(in: [currentDay, emptyYesterday], calendar: calendar)
        precondition(trained == Set([today]),
                     "A completed duration set counts as training; an empty session does not")
    }

    /// Egypt springs forward at midnight on the last Friday of April, so
    /// Friday 24 April 2026 starts at 01:00 and is 23 hours long. Stepping a
    /// day at a time with `date(byAdding:)` alone lands an hour off every key
    /// on one side of it.
    @MainActor
    static func daylightSaving(_ context: ModelContext) throws {
        var cairo = Calendar(identifier: .gregorian)
        cairo.timeZone = TimeZone(identifier: "Africa/Cairo")!

        func at(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            cairo.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
        }
        func dayKey(_ month: Int, _ day: Int) -> Date { cairo.startOfDay(for: at(month, day, 12)) }

        let friday = dayKey(4, 24)
        precondition(cairo.component(.hour, from: friday) == 1,
                     "This system's time zone data no longer has Cairo springing forward at midnight on 24 April 2026, so nothing below tests the transition")
        precondition(TrainingStats.startOfDay(1, from: dayKey(4, 23), calendar: cairo) == friday)
        precondition(TrainingStats.startOfDay(-1, from: friday, calendar: cairo) == dayKey(4, 23))
        precondition(TrainingStats.startOfDay(1, from: friday, calendar: cairo) == dayKey(4, 25))

        // A run straight through the transition, seen two days later.
        let run = (22...26).map { session(at: at(4, $0, 18), in: context) }
        let across = TrainingStats.streak(from: run, calendar: cairo, now: at(4, 26, 20))
        precondition(across.current == 5, "The current streak broke on the day the clocks changed: \(across.current)")
        precondition(across.longest == 5, "Best streak split at the day the clocks changed: \(across.longest)")

        // Seen on the Friday itself, before training.
        let before = (20...23).map { session(at: at(4, $0, 18), in: context) }
        let onFriday = at(4, 24, 12)
        let streak = TrainingStats.streak(from: before, calendar: cairo, now: onFriday)
        precondition(streak.current == 4, "On the transition day the streak read \(streak.current), not 4")

        let points = TrainingStats.daily(.sets, sessions: before, days: 7, calendar: cairo, now: onFriday)
        precondition(points.map(\.date) == (18...24).map { dayKey(4, $0) },
                     "Daily points must fall on the same keys sessions are bucketed under")
        precondition(points.filter { $0.value > 0 }.map(\.date) == (20...23).map { dayKey(4, $0) },
                     "Every trained day before the transition must show on the chart")

        // The first half hour of the window's first day, and the last half
        // hour before it. Both sit on the edge that lands an hour late.
        let windowStart = session(at: at(4, 18, 0, 30), in: context)
        let lastWeek = session(at: at(4, 17, 23, 30), in: context)
        let edges = [windowStart, lastWeek]
        let week = TrainingStats.sessions(in: edges, days: 7, calendar: cairo, now: onFriday)
        precondition(week.map(\.id) == [windowStart.id], "Saturday just after midnight belongs to this week's window")
        let previous = TrainingStats.previousWindow(edges, days: 7, calendar: cairo, now: onFriday)
        precondition(previous.map(\.id) == [lastWeek.id], "The previous window must end where this one starts")
        let buckets = TrainingStats.weeklySessionCounts(edges, weeks: 2, calendar: cairo, now: onFriday)
        precondition(buckets == [1, 1], "Weekly buckets split an hour late across the transition: \(buckets)")

        // Falling back, at the end of Thursday 29 October, gives a 25-hour day.
        let autumn = (28...31).map { session(at: at(10, $0, 18), in: context) }
        let fallBack = TrainingStats.streak(from: autumn, calendar: cairo, now: at(10, 31, 20))
        precondition(fallBack.current == 4 && fallBack.longest == 4, "A streak broke across the autumn change")
    }

    /// A session finished with nothing logged is a mis-tap, and counts toward
    /// nothing the calendar would call untrained.
    @MainActor
    static func emptySessions(_ context: ModelContext) throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func start(_ offset: Int) -> Date {
            calendar.date(byAdding: .hour, value: 12, to: TrainingStats.startOfDay(offset, from: today, calendar: calendar))!
        }

        let trained = session(at: start(-2), in: context)
        let empty = session(at: start(-1), logged: false, in: context)
        let sessions = [trained, empty]

        let streak = TrainingStats.streak(from: sessions, calendar: calendar)
        precondition(streak.current == 0, "An empty session yesterday kept the streak alive")
        precondition(streak.longest == 1, "An empty session lengthened the best streak")

        precondition(TrainingStats.sessions(in: sessions, days: 7, calendar: calendar).map(\.id) == [trained.id],
                     "An empty session counted as a session in the window")
        // A one-day window's previous window is yesterday, which held only
        // the empty session.
        precondition(TrainingStats.previousWindow(sessions, days: 1, calendar: calendar).isEmpty,
                     "An empty session counted in the previous window")
        precondition(TrainingStats.weeklySessionCounts(sessions, weeks: 1, calendar: calendar) == [1],
                     "An empty session counted in the weekly sessions")

        precondition(!TrainingStats.isTrained(empty))
        precondition(TrainingStats.isTrained(trained))
        let running = session(at: .now, in: context)
        running.endedAt = nil
        precondition(!TrainingStats.isTrained(running), "A session still running is not yet a day trained")
        let unlogged = session(at: start(-3), logged: false, in: context)
        let planned = SetLog(catalogID: "plank", exerciseName: "Plank",
                             exerciseOrder: 0, setIndex: 0, seconds: 60, tracking: .duration)
        unlogged.sets = [planned]
        precondition(!TrainingStats.isTrained(unlogged), "A planned row that was never logged is not training")
    }
}
