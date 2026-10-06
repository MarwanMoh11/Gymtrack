import Foundation
import SwiftData

/// Run with scripts/test-calendar-week-stats.sh; no simulator is needed.
///
/// Covers the pure halves of STATS-09 (Today says done only for its scheduled
/// day), STATS-10 (one calendar week, a grid that honours the first weekday),
/// STATS-11 (weigh-ins spaced by date, and a span for the change) and the
/// day-count behind `ProgressDashboardView.dayLabel`. Every date is built in a
/// named zone, and the weeks that hold a clock change are the ones asked about.
///
/// What no test here reaches, because the views cannot be built without a
/// simulator: `TodayView` handing `activePlan` to `completedToday`, the
/// "THIS WEEK" labels, the grid's weekday letters, and the body-weight card
/// drawing its line and caption from these numbers.
@main
@MainActor
struct CalendarWeekStatsTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message())")
    }

    static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        scheduledDayOnly(context)
        rotationDayOnly(context)
        springForwardDay(context)
        calendarWeek(context)
        gridColumns()
        dayCounts()
        weighInSpacing()
        changeSpans()
        if failures > 0 {
            print("\(failures) check(s) failed")
            exit(1)
        }
        print("Done-for-today, calendar week, grid, day count and weigh-in checks passed")
    }

    // MARK: - Fixtures

    static func calendar(_ zone: String, firstWeekday: Int) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    static func at(_ calendar: Calendar, _ month: Int, _ day: Int,
                   _ hour: Int = 12, _ minute: Int = 0, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    /// A finished session, with one logged set unless `logged` is false.
    @MainActor
    static func session(_ day: PlanDay?, from start: Date, lasting seconds: TimeInterval = 3600,
                        logged: Bool = true, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: day?.name ?? "Freestyle", planDayID: day?.id, startedAt: start)
        session.endedAt = start.addingTimeInterval(seconds)
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

    @MainActor
    static func day(_ name: String, in plan: Plan, weekday: Int?, context: ModelContext) -> PlanDay {
        let day = PlanDay(name: name, order: plan.days.count, weekday: weekday)
        context.insert(day)
        day.plan = plan
        let item = PlanItem(catalogID: "plank", name: "Plank", order: 0)
        context.insert(item)
        item.day = day
        return day
    }

    @MainActor
    static func plan(_ context: ModelContext) -> Plan {
        let plan = Plan(name: "Test plan", isActive: true)
        context.insert(plan)
        return plan
    }

    // MARK: - STATS-09

    /// Legs is pinned to Wednesday. Only a session of the plan started today
    /// may turn the card into "done", and Legs wins when it was trained.
    @MainActor
    static func scheduledDayOnly(_ context: ModelContext) {
        let cairo = calendar("Africa/Cairo", firstWeekday: 2)
        let now = at(cairo, 4, 22, 18)                           // Wednesday
        let plan = plan(context)
        let legs = day("Legs", in: plan, weekday: 4, context: context)
        let push = day("Push", in: plan, weekday: 5, context: context)

        func done(_ sessions: [WorkoutSession]) -> WorkoutSession? {
            TrainingStats.completedToday(in: sessions, plan: plan, calendar: cairo, now: now)
        }

        expect(done([]) == nil, "no session yet must leave the scheduled day on the card")

        let freestyle = session(nil, from: at(cairo, 4, 22, 8), in: context)
        expect(done([freestyle]) == nil, "a freestyle session must not hide today's scheduled Legs")

        let otherDay = session(push, from: at(cairo, 4, 22, 9), in: context)
        expect(done([otherDay]) === otherDay, "a plan day swapped in for Legs is today's workout")

        let lastNight = session(legs, from: at(cairo, 4, 21, 23, 10), lasting: 90 * 60, in: context)
        expect(done([lastNight]) == nil, "the tail of a session that started yesterday must not count as today's")

        let empty = session(legs, from: at(cairo, 4, 22, 10), logged: false, in: context)
        expect(done([empty]) == nil, "a Legs session closed with nothing logged is not a day trained")

        let active = WorkoutSession(title: "Legs", planDayID: legs.id, startedAt: at(cairo, 4, 22, 17))
        context.insert(active)
        expect(done([active]) == nil, "a session still in progress is not done")

        let trained = session(legs, from: at(cairo, 4, 22, 11), in: context)
        expect(done([trained]) === trained, "a Legs session today is today's workout")

        let laterFreestyle = session(nil, from: at(cairo, 4, 22, 15), in: context)
        expect(done([freestyle, laterFreestyle, trained, otherDay]) === trained,
               "the scheduled day's session wins over a later freestyle one")

        // Nothing is scheduled on a Saturday: whatever was trained is the day's workout.
        let saturday = at(cairo, 4, 25, 18)
        let restDayFreestyle = session(nil, from: at(cairo, 4, 25, 9), in: context)
        expect(TrainingStats.completedToday(in: [restDayFreestyle], plan: plan,
                                            calendar: cairo, now: saturday) === restDayFreestyle,
               "with nothing scheduled, a freestyle session is the day's workout")
        expect(TrainingStats.completedToday(in: [restDayFreestyle], plan: nil,
                                            calendar: cairo, now: saturday) === restDayFreestyle,
               "with no plan, a freestyle session is the day's workout")
    }

    /// An unpinned rotation moves on as soon as its day is trained, so the
    /// finished day has to be matched against what the card offered before it.
    @MainActor
    static func rotationDayOnly(_ context: ModelContext) {
        let cairo = calendar("Africa/Cairo", firstWeekday: 2)
        let now = at(cairo, 4, 22, 18)
        let plan = plan(context)
        let push = day("Push", in: plan, weekday: nil, context: context)
        let pull = day("Pull", in: plan, weekday: nil, context: context)
        let legs = day("Legs", in: plan, weekday: nil, context: context)
        let yesterdayPush = session(push, from: at(cairo, 4, 21, 18), in: context)

        func done(_ today: [WorkoutSession]) -> WorkoutSession? {
            TrainingStats.completedToday(in: [yesterdayPush] + today, plan: plan, calendar: cairo, now: now)
        }

        expect(plan.nextDay(on: now, after: [yesterdayPush], calendar: cairo)?.id == pull.id, "fixture: Pull is next")

        let freestyle = session(nil, from: at(cairo, 4, 22, 9), in: context)
        expect(done([freestyle]) == nil, "a freestyle session must not hide the rotation's Pull")

        let skippedAhead = session(legs, from: at(cairo, 4, 22, 10), in: context)
        expect(done([skippedAhead]) === skippedAhead, "Legs trained when Pull was offered is today's workout")

        let pulled = session(pull, from: at(cairo, 4, 22, 11), in: context)
        expect(done([pulled]) === pulled,
               "Pull trained today is done, though the rotation has since moved on to Legs")
        expect(done([pulled, skippedAhead]) === pulled, "the offered day wins over a swapped one")
        expect(plan.nextDay(on: now, after: [yesterdayPush, pulled], calendar: cairo)?.id == legs.id,
               "fixture: the rotation moved on")
    }

    /// Cairo skips 00:00 to 01:00 on Friday 24 April 2026, so that day starts
    /// at 01:00. A session at 23:50 the night before is not that day's.
    @MainActor
    static func springForwardDay(_ context: ModelContext) {
        let cairo = calendar("Africa/Cairo", firstWeekday: 2)
        let now = at(cairo, 4, 24, 18)
        let plan = plan(context)
        let friday = day("Friday", in: plan, weekday: 6, context: context)

        let thursdayNight = session(friday, from: at(cairo, 4, 23, 23, 50), lasting: 2 * 3600, in: context)
        expect(TrainingStats.completedToday(in: [thursdayNight], plan: plan, calendar: cairo, now: now) == nil,
               "a session begun before the short day started is not that day's")

        let firstHour = session(friday, from: at(cairo, 4, 24, 1, 10), in: context)
        expect(TrainingStats.completedToday(in: [thursdayNight, firstHour], plan: plan,
                                            calendar: cairo, now: now) === firstHour,
               "a session in the first hour of the short day is that day's")
    }

    // MARK: - STATS-10

    /// The review's Monday: trained Thursday, Friday and Sunday. Seven days
    /// back holds all three, and each locale's own week holds what it holds.
    @MainActor
    static func calendarWeek(_ context: ModelContext) {
        func trained(_ calendar: Calendar, on day: Int) -> WorkoutSession {
            session(nil, from: at(calendar, 4, day, 18), in: context)
        }

        for (firstWeekday, expected, name) in [(2, 0, "Monday-first"), (7, 1, "Saturday-first"),
                                               (1, 1, "Sunday-first")] {
            let cairo = calendar("Africa/Cairo", firstWeekday: firstWeekday)
            let monday = at(cairo, 4, 20, 10)
            let sessions = [trained(cairo, on: 16), trained(cairo, on: 17), trained(cairo, on: 19)]
            let thisWeek = TrainingStats.sessionsThisWeek(sessions, calendar: cairo, now: monday)
            expect(thisWeek.count == expected,
                   "\(name) week on Monday: expected \(expected), got \(thisWeek.count)")
        }

        // The week holding the spring-forward Friday is 167 hours long. Its
        // first and last hours and the night before it are the edges.
        let cairo = calendar("Africa/Cairo", firstWeekday: 2)
        let lateSunday = at(cairo, 4, 26, 20)
        let week = TrainingStats.weekInterval(containing: lateSunday, calendar: cairo)
        expect(week.start == cairo.startOfDay(for: at(cairo, 4, 20)), "week starts on Monday 00:00")
        expect(week.end == cairo.startOfDay(for: at(cairo, 4, 27)), "week ends at the next Monday 00:00")
        expect(week.duration == 167 * 3600, "the spring-forward week is 167 hours, got \(week.duration / 3600)")
        let edges = [session(nil, from: at(cairo, 4, 19, 23, 30), in: context),       // last week
                     session(nil, from: at(cairo, 4, 20, 0, 30), in: context),        // first hour
                     session(nil, from: at(cairo, 4, 24, 1, 15), in: context),        // first hour of the short day
                     session(nil, from: at(cairo, 4, 26, 23, 30), in: context),       // last hour
                     session(nil, from: at(cairo, 4, 27, 0, 30), in: context),         // next week
                     session(nil, from: at(cairo, 4, 21, 9), logged: false, in: context)]
        let counted = TrainingStats.sessionsThisWeek(edges, calendar: cairo, now: lateSunday)
        expect(counted.count == 3, "the DST week holds its three edge sessions, got \(counted.count)")

        // The clocks go back on Thursday 29 October: that day is 25 hours.
        let autumn = TrainingStats.weekInterval(containing: at(cairo, 10, 28), calendar: cairo)
        expect(autumn.duration == 169 * 3600, "the fall-back week is 169 hours, got \(autumn.duration / 3600)")
    }

    /// Columns open on the calendar's first weekday, today lands in the last
    /// one, and every cell is the key a session on that day is bucketed under.
    static func gridColumns() {
        let cairoMonday = calendar("Africa/Cairo", firstWeekday: 2)
        let wednesday = at(cairoMonday, 4, 22)
        expect(TrainingStats.gridStart(weeks: 4, calendar: cairoMonday, now: wednesday)
               == cairoMonday.startOfDay(for: at(cairoMonday, 3, 30)),
               "Monday-first grid opens on Monday 30 March")

        let cairoSunday = calendar("Africa/Cairo", firstWeekday: 1)
        expect(TrainingStats.gridStart(weeks: 4, calendar: cairoSunday, now: wednesday)
               == cairoSunday.startOfDay(for: at(cairoSunday, 3, 29)),
               "Sunday-first grid still opens on Sunday 29 March")

        let cairoSaturday = calendar("Africa/Cairo", firstWeekday: 7)
        let springFriday = at(cairoSaturday, 4, 24, 12)
        let start = TrainingStats.gridStart(weeks: 3, calendar: cairoSaturday, now: springFriday)
        expect(start == cairoSaturday.startOfDay(for: at(cairoSaturday, 4, 4)),
               "Saturday-first grid opens on Saturday 4 April")
        for offset in 0..<21 {
            let cell = TrainingStats.startOfDay(offset, from: start, calendar: cairoSaturday)
            let session = at(cairoSaturday, 4, 4 + offset, 13)
            expect(cell == cairoSaturday.startOfDay(for: session), "cell \(offset) matches its day's key")
        }
        let todayCell = TrainingStats.startOfDay(20, from: start, calendar: cairoSaturday)
        expect(todayCell == cairoSaturday.startOfDay(for: springFriday), "today is the last cell of the grid")

        expect(TrainingStats.gridWeekdayIndices(calendar: cairoSunday) == [0, 1, 2, 3, 4, 5, 6],
               "Sunday-first rows")
        expect(TrainingStats.gridWeekdayIndices(calendar: cairoMonday) == [1, 2, 3, 4, 5, 6, 0],
               "Monday-first rows")
        expect(TrainingStats.gridWeekdayIndices(calendar: cairoSaturday) == [6, 0, 1, 2, 3, 4, 5],
               "Saturday-first rows")
    }

    // MARK: - dayLabel

    static func dayCounts() {
        for zone in ["Africa/Cairo", "Asia/Beirut", "UTC"] {
            let calendar = calendar(zone, firstWeekday: 1)
            // Cairo and Beirut skip midnight; UTC never changes.
            let springStart = zone == "Africa/Cairo" ? (4, 24) : zone == "Asia/Beirut" ? (3, 29) : (3, 29)
            let spring = at(calendar, springStart.0, springStart.1, 12)
            let next = calendar.date(byAdding: .day, value: 1, to: spring)!
            let after = calendar.date(byAdding: .day, value: 2, to: spring)!
            expect(TrainingStats.dayCount(from: spring, to: next, calendar: calendar) == 1,
                   "\(zone): a session on the short day is yesterday the day after")
            expect(TrainingStats.dayCount(from: spring, to: after, calendar: calendar) == 2,
                   "\(zone): and two days ago the day after that")
            expect(TrainingStats.dayCount(from: spring, to: spring, calendar: calendar) == 0,
                   "\(zone): the same day is zero")
            let evening = at(calendar, springStart.0, springStart.1, 23, 59)
            let early = calendar.date(byAdding: .minute, value: 2, to: evening)!
            expect(TrainingStats.dayCount(from: evening, to: early, calendar: calendar) == 1,
                   "\(zone): 23:59 to 00:01 is one day")
        }

        let cairo = calendar("Africa/Cairo", firstWeekday: 1)
        let thursday = at(cairo, 10, 29, 12)                     // 25 hours long
        expect(TrainingStats.dayCount(from: thursday, to: at(cairo, 10, 30, 12), calendar: cairo) == 1,
               "the long day is one day")
        expect(TrainingStats.dayCount(from: at(cairo, 4, 19), to: at(cairo, 4, 26), calendar: cairo) == 7,
               "a week across the spring change is seven days")
    }

    // MARK: - STATS-11

    static func weighInSpacing() {
        let cairo = calendar("Africa/Cairo", firstWeekday: 2)
        let start = at(cairo, 3, 1, 8)
        // Seven weigh-ins on seven days, then one ten weeks on.
        var dates = (0..<7).map { cairo.date(byAdding: .day, value: $0, to: start)! }
        dates.append(cairo.date(byAdding: .day, value: 70, to: start)!)
        let positions = TrainingStats.weighInPositions(dates, calendar: cairo)
        expect(positions.count == dates.count, "one position per weigh-in")
        expect(positions.first == 0 && positions.last == 1, "the ends sit at the ends")
        expect(abs(positions[6] - 6.0 / 70.0) < 1e-9, "the seventh weigh-in is 6/70 along, got \(positions[6])")
        expect(abs(positions[1] - 1.0 / 70.0) < 1e-9, "the second weigh-in is 1/70 along")
        expect(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 }, "positions never go backwards")

        // Two days apart across the spring change, with one between: exactly the middle.
        let across = [at(cairo, 4, 23, 12), at(cairo, 4, 24, 12), at(cairo, 4, 25, 12)]
        expect(TrainingStats.weighInPositions(across, calendar: cairo) == [0, 0.5, 1],
               "a daylight-saving hour must not move the middle weigh-in")

        let sameDay = [at(cairo, 4, 23, 7), at(cairo, 4, 23, 19)]
        expect(TrainingStats.weighInPositions(sameDay, calendar: cairo) == [0.5, 0.5],
               "weigh-ins with no day between them share one centred position")
        expect(TrainingStats.weighInPositions([], calendar: cairo).isEmpty, "no weigh-ins, no positions")
    }

    static func changeSpans() {
        let english = Locale(identifier: "en_US")
        func span(_ days: Int) -> String? { TrainingStats.changeSpan(days: days, locale: english) }
        expect(span(0) == nil, "under a day is no period")
        expect(span(-3) == nil, "a negative span is no period")
        expect(span(1) == "1 day", "one day, got \(span(1) ?? "nil")")
        expect(span(9) == "9 days", "nine days, got \(span(9) ?? "nil")")
        expect(span(13) == "13 days", "thirteen days, got \(span(13) ?? "nil")")
        expect(span(14) == "2 weeks", "fourteen days, got \(span(14) ?? "nil")")
        expect(span(42) == "6 weeks", "six weeks, got \(span(42) ?? "nil")")
        expect(span(45) == "6 weeks", "forty-five days rounds down, got \(span(45) ?? "nil")")
        expect(span(46) == "7 weeks", "forty-six days rounds up, got \(span(46) ?? "nil")")
        expect(span(84) == "12 weeks", "the whole window, got \(span(84) ?? "nil")")
    }
}
