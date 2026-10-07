import Testing
import Foundation
import SwiftData
@testable import GymTrack

/// Protects the numbers behind Today and Progress: streaks, calendar weeks,
/// windows, day counts, volume, personal records and the Lifts card's tags
/// over finished sessions, including the days that are 23 or 25 hours long and
/// the sessions that straddle midnight in a zone other than the runner's.
///
/// Every date comes from `TestClock`, so a Mac set to Cairo runs the same
/// checks as CI in UTC. The progression suggestion has its own file, and the
/// Progress tab's cache is in `ProgressHistoryTests`.
@MainActor @Suite(.serialized)
struct TrainingStatsTests {

    /// One set to be logged, spelled out only where a test cares.
    fileprivate struct Work {
        var id = "barbell-bench-press"
        var kg: Double = 0
        var reps = 0
        var seconds = 0
        var tracking: TrackingMode? = .weightReps
        var drop = false
        var logged = true
        var at: Date?
    }

    /// An in-memory store that builds finished sessions from `Work`.
    @MainActor fileprivate final class Rig {
        let container: ModelContainer
        let context: ModelContext

        init() throws {
            container = try TestStore.container()
            context = ModelContext(container)
        }

        @discardableResult
        func session(_ start: Date, finished: Bool = true, lasting: TimeInterval = 3_600,
                     of day: PlanDay? = nil, _ work: [Work]) -> WorkoutSession {
            let session = WorkoutSession(title: day?.name ?? "Test", planDayID: day?.id, startedAt: start)
            if finished { session.endedAt = start.addingTimeInterval(lasting) }
            context.insert(session)
            for (index, item) in work.enumerated() {
                let set = SetLog(catalogID: item.id, exerciseName: item.id, exerciseOrder: 0, setIndex: index,
                                 weightKg: item.kg, reps: item.reps, seconds: item.seconds, tracking: item.tracking)
                if item.logged {
                    set.isCompleted = true
                    set.completedAt = item.at ?? start.addingTimeInterval(Double(index + 1) * 60)
                }
                if item.drop { set.continuesPreviousSet = true }
                set.session = session
                context.insert(set)
            }
            return session
        }

        /// A finished session with one working set, which is all a streak needs.
        @discardableResult
        func trained(_ stamp: String, in zone: String = "UTC") -> WorkoutSession {
            session(TestClock.at(stamp, in: zone), [Work(kg: 100, reps: 5)])
        }

        func plan() -> Plan {
            let plan = Plan(name: "Test plan", isActive: true)
            context.insert(plan)
            return plan
        }

        /// A training day with one slot, pinned to `weekday` or in the rotation.
        func day(_ name: String, in plan: Plan, weekday: Int?) -> PlanDay {
            let day = PlanDay(name: name, order: plan.days.count, weekday: weekday)
            context.insert(day)
            day.plan = plan
            let item = PlanItem(catalogID: "plank", name: "Plank", order: 0)
            context.insert(item)
            item.day = day
            return day
        }
    }

    private let utc = TestClock.calendar
    /// A Wednesday at noon UTC.
    private let now = TestClock.reference

    /// One logged hold: a day trained, with no weight to add to the volume.
    private static let hold = Work(id: "plank", seconds: 60, tracking: .duration)

    /// Egypt springs forward at midnight on the last Friday of April, so Friday
    /// 24 April 2026 starts at 01:00 and is 23 hours long, and falls back at the
    /// end of Thursday 29 October, which is 25 hours long.
    private let cairo = TestClock.calendar(in: "Africa/Cairo")

    private func inCairo(_ stamp: String) -> Date { TestClock.at(stamp, in: "Africa/Cairo") }

    /// The key Cairo files a session on `date` under.
    private func cairoDay(_ date: String) -> Date { cairo.startOfDay(for: inCairo("\(date)T12:00:00")) }

    private func cairoCalendar(firstWeekday: Int) -> Calendar {
        var calendar = cairo
        calendar.firstWeekday = firstWeekday
        return calendar
    }

    /// Stops a test whose time zone data no longer springs `zone` forward at
    /// midnight on `date`, since nothing after it would then test the change.
    private func requireMidnightSpringForward(on date: String, in zone: String) throws {
        let calendar = TestClock.calendar(in: zone)
        let start = calendar.startOfDay(for: TestClock.at("\(date)T12:00:00", in: zone))
        try #require(calendar.component(.hour, from: start) == 1,
                     "\(zone) no longer springs forward at midnight on \(date), so nothing here tests the change")
    }

    // MARK: - Streaks

    @Test func noHistoryIsNoStreak() {
        let streak = TrainingStats.streak(from: [], calendar: utc, now: now)
        #expect(streak.current == 0)
        #expect(streak.longest == 0)
    }

    @Test func oneSessionTodayIsAStreakOfOne() throws {
        let rig = try Rig()
        let sessions = [rig.trained("2026-03-11T07:00:00")]
        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: now)
        #expect(streak.current == 1)
        #expect(streak.longest == 1)
    }

    @Test func todayNotTrainedYetDoesNotBreakYesterdaysStreak() throws {
        let rig = try Rig()
        let sessions = [rig.trained("2026-03-09T09:00:00"), rig.trained("2026-03-10T09:00:00")]
        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: now)
        #expect(streak.current == 2)
        #expect(streak.longest == 2)
    }

    @Test func missingYesterdayEndsTheCurrentStreakButKeepsTheLongest() throws {
        let rig = try Rig()
        let sessions = ["2026-03-07T09:00:00", "2026-03-08T09:00:00", "2026-03-09T09:00:00"].map { rig.trained($0) }
        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: now)
        #expect(streak.current == 0)
        #expect(streak.longest == 3)
    }

    @Test func aDayCountsOnceAndMisTapsDoNotCount() throws {
        let rig = try Rig()
        let sessions = [
            rig.trained("2026-03-09T09:00:00"),
            rig.trained("2026-03-09T18:00:00"),
            // Finish pressed with nothing logged: a mis-tap, not a day trained.
            rig.session(TestClock.at("2026-03-10T08:00:00"), [Work(kg: 100, reps: 5, logged: false)]),
            // Still running: not finished, so not yet a day trained.
            rig.session(TestClock.at("2026-03-10T09:00:00"), finished: false, [Work(kg: 100, reps: 5)]),
        ]
        let days = TrainingStats.trainedDays(in: sessions, calendar: utc)
        #expect(days == [TestClock.at("2026-03-09T00:00:00")])
        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: TestClock.at("2026-03-10T12:00:00"))
        #expect(streak.current == 1)
        #expect(streak.longest == 1)
    }

    /// A session at 23:59 and the next at 00:01 are on consecutive local days in
    /// every zone below, and on the same UTC day in all of them.
    @Test(arguments: ["America/New_York", "Africa/Cairo", "Pacific/Kiritimati"])
    func sessionsEitherSideOfLocalMidnightAreTwoDaysInThatZoneAndOneInUTC(zone: String) throws {
        let rig = try Rig()
        let sessions = [rig.trained("2026-03-09T23:59:00", in: zone), rig.trained("2026-03-10T00:01:00", in: zone)]
        let morning = TestClock.at("2026-03-10T09:00:00", in: zone)

        let local = TrainingStats.streak(from: sessions, calendar: TestClock.calendar(in: zone), now: morning)
        #expect(local.current == 2)
        #expect(local.longest == 2)

        let utcDays = TrainingStats.trainedDays(in: sessions, calendar: utc)
        #expect(utcDays.count == 1)
        #expect(TrainingStats.streak(from: sessions, calendar: utc, now: morning).current == 1)
    }

    struct StreakCase: Sendable, CustomTestStringConvertible {
        let zone: String
        let stamps: [String]
        let now: String
        let current: Int
        var testDescription: String { "\(zone) \(stamps.first ?? "")" }
    }

    /// The days the clocks change are not 24 hours long, and a streak that ran
    /// through one used to split in two there.
    @Test(arguments: [
        StreakCase(zone: "America/New_York",
                   stamps: ["2026-03-07T20:00:00", "2026-03-08T12:00:00", "2026-03-09T08:00:00"],
                   now: "2026-03-09T18:00:00", current: 3),
        StreakCase(zone: "America/New_York",
                   stamps: ["2026-10-31T22:00:00", "2026-11-01T00:30:00", "2026-11-01T23:30:00", "2026-11-02T08:00:00"],
                   now: "2026-11-02T12:00:00", current: 3),
        // Cairo springs forward at midnight, so Friday 24 April starts at 01:00.
        StreakCase(zone: "Africa/Cairo",
                   stamps: ["2026-04-23T20:00:00", "2026-04-24T01:30:00", "2026-04-25T10:00:00"],
                   now: "2026-04-25T12:00:00", current: 3),
    ])
    func aStreakRunsThroughTheDayTheClocksChange(_ scenario: StreakCase) throws {
        let rig = try Rig()
        let calendar = TestClock.calendar(in: scenario.zone)
        let sessions = scenario.stamps.map { rig.trained($0, in: scenario.zone) }
        let streak = TrainingStats.streak(from: sessions, calendar: calendar,
                                          now: TestClock.at(scenario.now, in: scenario.zone))
        #expect(streak.current == scenario.current)
        #expect(streak.longest == scenario.current)
    }

    /// Kiritimati is UTC+14 and Pago Pago UTC-11, 25 hours apart, so at least
    /// one of them is on a different calendar day from wherever this runs.
    @Test(arguments: ["Pacific/Kiritimati", "Pacific/Pago_Pago"], [1, 2])
    func aStreakIsCountedInTheCalendarsOwnDays(zone: String, firstWeekday: Int) throws {
        let rig = try Rig()
        var calendar = TestClock.calendar(in: zone)
        calendar.firstWeekday = firstWeekday
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            TestClock.at(String(format: "2026-03-%02dT%02d:%02d:00", day, hour, minute), in: zone)
        }
        func run(_ days: [Int]) -> [WorkoutSession] {
            days.map { rig.session(at($0, 12), [Work(kg: 60, reps: 8)]) }
        }
        let now = at(20, 9)

        let three = TrainingStats.streak(from: run([18, 19, 20]), calendar: calendar, now: now)
        #expect(three.current == 3)
        #expect(three.longest == 3)
        // Today not trained yet keeps yesterday's streak.
        #expect(TrainingStats.streak(from: run([18, 19]), calendar: calendar, now: now).current == 2)
        let missed = TrainingStats.streak(from: run([17, 18]), calendar: calendar, now: now)
        #expect(missed.current == 0)
        #expect(missed.longest == 2)
        let gapped = TrainingStats.streak(from: run([12, 13, 14, 18, 19]), calendar: calendar, now: now)
        #expect(gapped.current == 2, "The best run is not the current one")
        #expect(gapped.longest == 3)
        #expect(TrainingStats.streak(from: [], calendar: calendar, now: now).current == 0)

        // A minute either side of local midnight is two days, not one.
        let midnight = [at(19, 23, 59), at(20, 0, 1)].map { rig.session($0, [Work(kg: 60, reps: 8)]) }
        #expect(TrainingStats.streak(from: midnight, calendar: calendar, now: now).current == 2)
        // Two sessions on one local day are one day.
        let sameDay = [at(20, 0, 30), at(20, 23, 30)].map { rig.session($0, [Work(kg: 60, reps: 8)]) }
        let one = TrainingStats.streak(from: sameDay, calendar: calendar, now: at(20, 23, 45))
        #expect(one.current == 1)
        #expect(one.longest == 1)
    }

    /// A day apart in UTC and two days apart in Kiritimati: the day is the
    /// calendar's, not UTC's.
    @Test func aDaySkippedInKiritimatiSplitsTheStreakThoughUTCSeesNoGap() throws {
        let rig = try Rig()
        let zone = "Pacific/Kiritimati"
        let sessions = [rig.trained("2026-03-20T00:30:00", in: zone), rig.trained("2026-03-18T23:30:00", in: zone)]
        let now = TestClock.at("2026-03-20T12:00:00", in: zone)
        let local = TrainingStats.streak(from: sessions, calendar: TestClock.calendar(in: zone), now: now)
        #expect(local.current == 1)
        #expect(local.longest == 1)
        // The scenario is only a test if UTC would have got it wrong.
        #expect(TrainingStats.streak(from: sessions, calendar: utc, now: now).longest == 2)
    }

    @Test func stepsFromCairosShortDayLandOnTheKeysItsSessionsAreFiledUnder() throws {
        try requireMidnightSpringForward(on: "2026-04-24", in: "Africa/Cairo")
        let friday = cairoDay("2026-04-24")
        #expect(TrainingStats.startOfDay(1, from: cairoDay("2026-04-23"), calendar: cairo) == friday)
        #expect(TrainingStats.startOfDay(-1, from: friday, calendar: cairo) == cairoDay("2026-04-23"))
        #expect(TrainingStats.startOfDay(1, from: friday, calendar: cairo) == cairoDay("2026-04-25"))
    }

    @Test func aStreakAndTheDailyChartRunThroughCairosShortDay() throws {
        try requireMidnightSpringForward(on: "2026-04-24", in: "Africa/Cairo")
        let rig = try Rig()
        // A run straight through the change, seen two days later.
        let run = (22...26).map { rig.session(inCairo("2026-04-\($0)T18:00:00"), [Self.hold]) }
        let across = TrainingStats.streak(from: run, calendar: cairo, now: inCairo("2026-04-26T20:00:00"))
        #expect(across.current == 5)
        #expect(across.longest == 5)

        // Seen on the Friday itself, before training.
        let before = (20...23).map { rig.session(inCairo("2026-04-\($0)T18:00:00"), [Self.hold]) }
        let onFriday = inCairo("2026-04-24T12:00:00")
        #expect(TrainingStats.streak(from: before, calendar: cairo, now: onFriday).current == 4)
        let points = TrainingStats.daily(.sets, sessions: before, days: 7, calendar: cairo, now: onFriday)
        // The chart's days are the keys sessions are filed under, so every
        // trained day before the change shows.
        #expect(points.map(\.date) == (18...24).map { cairoDay("2026-04-\($0)") })
        #expect(points.filter { $0.value > 0 }.map(\.date) == (20...23).map { cairoDay("2026-04-\($0)") })
    }

    @Test func aStreakRunsThroughCairosLongAutumnDay() throws {
        let rig = try Rig()
        let autumn = (28...31).map { rig.session(inCairo("2026-10-\($0)T18:00:00"), [Self.hold]) }
        let streak = TrainingStats.streak(from: autumn, calendar: cairo, now: inCairo("2026-10-31T20:00:00"))
        #expect(streak.current == 4)
        #expect(streak.longest == 4)
    }

    /// Finish pressed with nothing logged is a mis-tap, and counts toward
    /// nothing the calendar beside it would call a rest day.
    @Test func aSessionWithNothingLoggedCountsTowardNothing() throws {
        let rig = try Rig()
        let today = utc.startOfDay(for: now)
        func noon(_ offset: Int) -> Date {
            TrainingStats.startOfDay(offset, from: today, calendar: utc).addingTimeInterval(12 * 3_600)
        }
        let trained = rig.session(noon(-2), [Self.hold])
        let empty = rig.session(noon(-1), [])
        let sessions = [trained, empty]

        let streak = TrainingStats.streak(from: sessions, calendar: utc, now: now)
        #expect(streak.current == 0, "An empty session yesterday kept the streak alive")
        #expect(streak.longest == 1, "An empty session lengthened the best streak")
        #expect(TrainingStats.sessions(in: sessions, days: 7, calendar: utc, now: now).map(\.id) == [trained.id])
        // A one-day window's previous window is yesterday, which held only the
        // empty session.
        #expect(TrainingStats.previousWindow(sessions, days: 1, calendar: utc, now: now).isEmpty)
        #expect(TrainingStats.weeklySessionCounts(sessions, weeks: 1, calendar: utc, now: now) == [1])

        #expect(!TrainingStats.isTrained(empty))
        #expect(TrainingStats.isTrained(trained))
        let running = rig.session(now, finished: false, [Self.hold])
        #expect(!TrainingStats.isTrained(running), "A session still running is not yet a day trained")
        var planned = Self.hold
        planned.logged = false
        let unlogged = rig.session(noon(-3), [planned])
        #expect(!TrainingStats.isTrained(unlogged), "A planned row that was never logged is not training")
    }

    // MARK: - Calendar weeks

    @Test func theWeekFollowsTheCalendarsFirstWeekday() {
        let monday = TrainingStats.weekInterval(containing: now, calendar: utc)
        #expect(monday.start == TestClock.at("2026-03-09T00:00:00"))
        #expect(monday.end == TestClock.at("2026-03-16T00:00:00"))

        var sundayFirst = utc
        sundayFirst.firstWeekday = 1
        let sunday = TrainingStats.weekInterval(containing: now, calendar: sundayFirst)
        #expect(sunday.start == TestClock.at("2026-03-08T00:00:00"))
        #expect(sunday.end == TestClock.at("2026-03-15T00:00:00"))
    }

    @Test func aWeekOwnsItsFirstInstantAndNotItsLast() {
        let start = TestClock.at("2026-03-09T00:00:00")
        let end = TestClock.at("2026-03-16T00:00:00")
        #expect(TrainingStats.weekInterval(containing: start, calendar: utc).start == start)
        #expect(TrainingStats.weekInterval(containing: end.addingTimeInterval(-1), calendar: utc).start == start)
        #expect(TrainingStats.weekInterval(containing: end, calendar: utc).start == end)
    }

    @Test func theWeekOfTheSpringForwardIsOneHourShort() {
        let calendar = TestClock.calendar(in: "America/New_York")
        let week = TrainingStats.weekInterval(containing: TestClock.at("2026-03-08T12:00:00", in: "America/New_York"),
                                              calendar: calendar)
        #expect(week.start == TestClock.at("2026-03-02T00:00:00", in: "America/New_York"))
        #expect(week.end == TestClock.at("2026-03-09T00:00:00", in: "America/New_York"))
        #expect(week.duration == 167 * 3_600)
    }

    @Test func thisWeekCountsFinishedTrainingStartedInsideItsEdges() throws {
        let rig = try Rig()
        let inside = [
            rig.trained("2026-03-09T00:00:00"), rig.trained("2026-03-11T09:00:00"), rig.trained("2026-03-15T23:59:59"),
        ]
        let outside = [
            rig.trained("2026-03-08T23:59:59"), rig.trained("2026-03-16T00:00:00"),
            rig.session(TestClock.at("2026-03-10T08:00:00"), [Work(kg: 100, reps: 5, logged: false)]),
            rig.session(TestClock.at("2026-03-10T09:00:00"), finished: false, [Work(kg: 100, reps: 5)]),
        ]
        let found = TrainingStats.sessionsThisWeek(inside + outside, calendar: utc, now: now)
        #expect(Set(found.map(\.id)) == Set(inside.map(\.id)))
        #expect(TrainingStats.sessionsThisWeek([], calendar: utc, now: now).isEmpty)
    }

    @Test func aLateSundayInNewYorkBelongsToLastWeekThere() throws {
        let rig = try Rig()
        let zone = "America/New_York"
        // 23:30 on Sunday 8 March in New York is 03:30 UTC on Monday the 9th.
        let lateSunday = rig.trained("2026-03-08T23:30:00", in: zone)
        let wednesday = TestClock.at("2026-03-11T12:00:00", in: zone)
        let local = TrainingStats.sessionsThisWeek([lateSunday], calendar: TestClock.calendar(in: zone), now: wednesday)
        let universal = TrainingStats.sessionsThisWeek([lateSunday], calendar: utc, now: wednesday)
        #expect(local.isEmpty)
        #expect(universal.count == 1)
    }

    struct WeekStart: Sendable, CustomTestStringConvertible {
        let firstWeekday: Int
        let sessions: Int
        var testDescription: String { "first weekday \(firstWeekday)" }
    }

    /// Sunday 8 March. A Monday-first week holds the Wednesday and Saturday
    /// before it and stops at the Sunday's midnight, so Monday's 1 am is next
    /// week's; a Sunday-first week has only just begun and holds the Sunday and
    /// that Monday. The session on 1 March is in neither.
    @Test(arguments: ["Pacific/Kiritimati", "Pacific/Pago_Pago"],
          [WeekStart(firstWeekday: 2, sessions: 3), WeekStart(firstWeekday: 1, sessions: 2)])
    func aWeekOpensAtLocalMidnightOnTheCalendarsFirstWeekday(zone: String, week: WeekStart) throws {
        let rig = try Rig()
        var calendar = TestClock.calendar(in: zone)
        calendar.firstWeekday = week.firstWeekday
        func at(_ day: Int, _ hour: Int) -> Date {
            TestClock.at(String(format: "2026-03-%02dT%02d:00:00", day, hour), in: zone)
        }
        let now = at(8, 10)
        try #require(calendar.component(.weekday, from: now) == 1, "The fixture day must be a Sunday")
        let sessions = [at(4, 12), at(7, 12), at(8, 9), at(1, 12), at(9, 1)].map { rig.session($0, [Work(kg: 60, reps: 8)]) }
        #expect(TrainingStats.sessionsThisWeek(sessions, calendar: calendar, now: now).count == week.sessions)

        let interval = TrainingStats.weekInterval(containing: now, calendar: calendar)
        #expect(calendar.component(.weekday, from: interval.start) == week.firstWeekday)
        #expect(calendar.component(.hour, from: interval.start) == 0)
    }

    /// The review's Monday: trained Thursday, Friday and Sunday. Seven days
    /// back holds all three, and each locale's own week holds what it holds.
    @Test(arguments: [WeekStart(firstWeekday: 2, sessions: 0), WeekStart(firstWeekday: 7, sessions: 1),
                      WeekStart(firstWeekday: 1, sessions: 1)])
    func thisWeekOnAMondayHoldsWhatTheLocalesOwnWeekHolds(_ week: WeekStart) throws {
        let rig = try Rig()
        let calendar = cairoCalendar(firstWeekday: week.firstWeekday)
        let sessions = [16, 17, 19].map { rig.session(inCairo("2026-04-\($0)T18:00:00"), [Self.hold]) }
        let thisWeek = TrainingStats.sessionsThisWeek(sessions, calendar: calendar, now: inCairo("2026-04-20T10:00:00"))
        #expect(thisWeek.count == week.sessions)
    }

    /// The week holding Cairo's spring-forward Friday is 167 hours long, and the
    /// one holding its autumn Thursday 169. Its first and last hours, the short
    /// day's first hour, and the hours either side of it are the edges.
    @Test func cairosWeeksAcrossTheClockChangesKeepTheirEdges() throws {
        try requireMidnightSpringForward(on: "2026-04-24", in: "Africa/Cairo")
        let rig = try Rig()
        let lateSunday = inCairo("2026-04-26T20:00:00")
        let week = TrainingStats.weekInterval(containing: lateSunday, calendar: cairo)
        #expect(week.start == cairoDay("2026-04-20"))
        #expect(week.end == cairoDay("2026-04-27"))
        #expect(week.duration == 167 * 3_600)
        let edges = [
            rig.session(inCairo("2026-04-19T23:30:00"), [Self.hold]),   // last week
            rig.session(inCairo("2026-04-20T00:30:00"), [Self.hold]),   // first hour
            rig.session(inCairo("2026-04-24T01:15:00"), [Self.hold]),   // first hour of the short day
            rig.session(inCairo("2026-04-26T23:30:00"), [Self.hold]),   // last hour
            rig.session(inCairo("2026-04-27T00:30:00"), [Self.hold]),   // next week
            rig.session(inCairo("2026-04-21T09:00:00"), []),            // nothing logged
        ]
        #expect(TrainingStats.sessionsThisWeek(edges, calendar: cairo, now: lateSunday).count == 3)

        let autumn = TrainingStats.weekInterval(containing: inCairo("2026-10-28T12:00:00"), calendar: cairo)
        #expect(autumn.duration == 169 * 3_600)
    }

    /// Columns open on the calendar's first weekday, today lands in the last
    /// one, and every cell is the key a session on that day is filed under.
    @Test func theConsistencyGridOpensOnTheFirstWeekdayAndEndsOnToday() throws {
        let monday = cairoCalendar(firstWeekday: 2)
        let sunday = cairoCalendar(firstWeekday: 1)
        let saturday = cairoCalendar(firstWeekday: 7)
        let wednesday = inCairo("2026-04-22T12:00:00")
        #expect(TrainingStats.gridStart(weeks: 4, calendar: monday, now: wednesday) == cairoDay("2026-03-30"))
        #expect(TrainingStats.gridStart(weeks: 4, calendar: sunday, now: wednesday) == cairoDay("2026-03-29"))

        let springFriday = inCairo("2026-04-24T12:00:00")
        let start = TrainingStats.gridStart(weeks: 3, calendar: saturday, now: springFriday)
        #expect(start == cairoDay("2026-04-04"))
        for offset in 0..<21 {
            let cell = TrainingStats.startOfDay(offset, from: start, calendar: saturday)
            let session = inCairo(String(format: "2026-04-%02dT13:00:00", 4 + offset))
            #expect(cell == saturday.startOfDay(for: session), "cell \(offset)")
        }
        #expect(TrainingStats.startOfDay(20, from: start, calendar: saturday) == saturday.startOfDay(for: springFriday))

        #expect(TrainingStats.gridWeekdayIndices(calendar: sunday) == [0, 1, 2, 3, 4, 5, 6])
        #expect(TrainingStats.gridWeekdayIndices(calendar: monday) == [1, 2, 3, 4, 5, 6, 0])
        #expect(TrainingStats.gridWeekdayIndices(calendar: saturday) == [6, 0, 1, 2, 3, 4, 5])
    }

    // MARK: - Done for today

    /// Legs is pinned to Wednesday. Only a session of the plan started today may
    /// turn the card into "done", and Legs wins when it was trained.
    @Test func onlyAPlanSessionStartedTodayMarksTheScheduledDayDone() throws {
        let rig = try Rig()
        let now = inCairo("2026-04-22T18:00:00")
        let plan = rig.plan()
        let legs = rig.day("Legs", in: plan, weekday: 4)
        let push = rig.day("Push", in: plan, weekday: 5)
        func done(_ sessions: [WorkoutSession]) -> WorkoutSession? {
            TrainingStats.completedToday(in: sessions, plan: plan, calendar: cairo, now: now)
        }

        #expect(done([]) == nil, "No session yet leaves the scheduled day on the card")
        let freestyle = rig.session(inCairo("2026-04-22T08:00:00"), [Self.hold])
        #expect(done([freestyle]) == nil, "A freestyle session must not hide today's scheduled Legs")
        let otherDay = rig.session(inCairo("2026-04-22T09:00:00"), of: push, [Self.hold])
        #expect(done([otherDay]) === otherDay, "A plan day swapped in for Legs is today's workout")
        let lastNight = rig.session(inCairo("2026-04-21T23:10:00"), lasting: 90 * 60, of: legs, [Self.hold])
        #expect(done([lastNight]) == nil, "The tail of a session that started yesterday is not today's")
        let empty = rig.session(inCairo("2026-04-22T10:00:00"), of: legs, [])
        #expect(done([empty]) == nil, "A Legs session closed with nothing logged is not a day trained")
        let active = rig.session(inCairo("2026-04-22T17:00:00"), finished: false, of: legs, [])
        #expect(done([active]) == nil, "A session still in progress is not done")
        let trained = rig.session(inCairo("2026-04-22T11:00:00"), of: legs, [Self.hold])
        #expect(done([trained]) === trained)
        let laterFreestyle = rig.session(inCairo("2026-04-22T15:00:00"), [Self.hold])
        #expect(done([freestyle, laterFreestyle, trained, otherDay]) === trained,
                "The scheduled day's session wins over a later freestyle one")

        // Nothing is scheduled on a Saturday, so whatever was trained is the day's workout.
        let saturday = inCairo("2026-04-25T18:00:00")
        let restDay = rig.session(inCairo("2026-04-25T09:00:00"), [Self.hold])
        #expect(TrainingStats.completedToday(in: [restDay], plan: plan, calendar: cairo, now: saturday) === restDay)
        #expect(TrainingStats.completedToday(in: [restDay], plan: nil, calendar: cairo, now: saturday) === restDay)
    }

    /// An unpinned rotation moves on as soon as its day is trained, so the
    /// finished day is matched against what the card offered before it.
    @Test func aRotationsDayIsDoneThoughTheRotationHasMovedOn() throws {
        let rig = try Rig()
        let now = inCairo("2026-04-22T18:00:00")
        let plan = rig.plan()
        let push = rig.day("Push", in: plan, weekday: nil)
        let pull = rig.day("Pull", in: plan, weekday: nil)
        let legs = rig.day("Legs", in: plan, weekday: nil)
        let yesterdayPush = rig.session(inCairo("2026-04-21T18:00:00"), of: push, [Self.hold])
        func done(_ today: [WorkoutSession]) -> WorkoutSession? {
            TrainingStats.completedToday(in: [yesterdayPush] + today, plan: plan, calendar: cairo, now: now)
        }
        try #require(plan.nextDay(on: now, after: [yesterdayPush], calendar: cairo)?.id == pull.id)

        let freestyle = rig.session(inCairo("2026-04-22T09:00:00"), [Self.hold])
        #expect(done([freestyle]) == nil, "A freestyle session must not hide the rotation's Pull")
        let skippedAhead = rig.session(inCairo("2026-04-22T10:00:00"), of: legs, [Self.hold])
        #expect(done([skippedAhead]) === skippedAhead, "Legs trained when Pull was offered is today's workout")
        let pulled = rig.session(inCairo("2026-04-22T11:00:00"), of: pull, [Self.hold])
        #expect(done([pulled]) === pulled)
        #expect(done([pulled, skippedAhead]) === pulled, "The offered day wins over a swapped one")
        #expect(plan.nextDay(on: now, after: [yesterdayPush, pulled], calendar: cairo)?.id == legs.id)
    }

    /// Cairo skips 00:00 to 01:00 on Friday 24 April 2026. A session at 23:50
    /// the night before is not that day's.
    @Test func aSessionBegunBeforeCairosShortDayStartedIsNotThatDays() throws {
        try requireMidnightSpringForward(on: "2026-04-24", in: "Africa/Cairo")
        let rig = try Rig()
        let now = inCairo("2026-04-24T18:00:00")
        let plan = rig.plan()
        let friday = rig.day("Friday", in: plan, weekday: 6)
        let thursdayNight = rig.session(inCairo("2026-04-23T23:50:00"), lasting: 2 * 3_600, of: friday, [Self.hold])
        #expect(TrainingStats.completedToday(in: [thursdayNight], plan: plan, calendar: cairo, now: now) == nil)
        let firstHour = rig.session(inCairo("2026-04-24T01:10:00"), of: friday, [Self.hold])
        #expect(TrainingStats.completedToday(in: [thursdayNight, firstHour], plan: plan,
                                            calendar: cairo, now: now) === firstHour)
    }

    // MARK: - Counting days

    struct DayCase: Sendable, CustomTestStringConvertible {
        let zone: String
        let from: String
        let to: String
        let days: Int
        var testDescription: String { "\(zone) \(from) to \(to)" }
    }

    @Test(arguments: [
        DayCase(zone: "UTC", from: "2026-03-10T23:59:00", to: "2026-03-11T00:01:00", days: 1),
        DayCase(zone: "UTC", from: "2026-03-11T00:00:00", to: "2026-03-11T23:59:59", days: 0),
        DayCase(zone: "UTC", from: "2026-03-12T10:00:00", to: "2026-03-11T10:00:00", days: -1),
        DayCase(zone: "America/New_York", from: "2026-03-07T23:30:00", to: "2026-03-09T00:30:00", days: 2),
        DayCase(zone: "America/New_York", from: "2026-03-08T00:30:00", to: "2026-03-09T00:30:00", days: 1),
        DayCase(zone: "America/New_York", from: "2026-03-08T00:10:00", to: "2026-03-08T23:50:00", days: 0),
        DayCase(zone: "America/New_York", from: "2026-11-01T00:30:00", to: "2026-11-02T00:30:00", days: 1),
        DayCase(zone: "Africa/Cairo", from: "2026-04-24T01:30:00", to: "2026-04-25T00:30:00", days: 1),
        DayCase(zone: "Pacific/Kiritimati", from: "2026-03-10T23:59:00", to: "2026-03-11T00:01:00", days: 1),
    ])
    func wholeCalendarDaysAreCountedBetweenWallClockMiddays(_ scenario: DayCase) {
        let calendar = TestClock.calendar(in: scenario.zone)
        let count = TrainingStats.dayCount(from: TestClock.at(scenario.from, in: scenario.zone),
                                           to: TestClock.at(scenario.to, in: scenario.zone), calendar: calendar)
        #expect(count == scenario.days)
    }

    /// Cairo and Beirut skip midnight on these days; UTC never changes. A
    /// session on the short day used to read as "today" all through the next.
    @Test(arguments: [("Africa/Cairo", "2026-04-24"), ("Asia/Beirut", "2026-03-29"), ("UTC", "2026-03-29")])
    func dayCountsFromAShortDayCountEachDayOnce(zone: String, date: String) throws {
        if zone != "UTC" { try requireMidnightSpringForward(on: date, in: zone) }
        let calendar = TestClock.calendar(in: zone)
        let spring = TestClock.at("\(date)T12:00:00", in: zone)
        let next = try #require(calendar.date(byAdding: .day, value: 1, to: spring))
        let after = try #require(calendar.date(byAdding: .day, value: 2, to: spring))
        #expect(TrainingStats.dayCount(from: spring, to: next, calendar: calendar) == 1)
        #expect(TrainingStats.dayCount(from: spring, to: after, calendar: calendar) == 2)
        #expect(TrainingStats.dayCount(from: spring, to: spring, calendar: calendar) == 0)
        let evening = TestClock.at("\(date)T23:59:00", in: zone)
        let early = try #require(calendar.date(byAdding: .minute, value: 2, to: evening))
        #expect(TrainingStats.dayCount(from: evening, to: early, calendar: calendar) == 1)
    }

    @Test func cairosLongDayIsOneDayAndAWeekAcrossItsShortOneIsSeven() {
        #expect(TrainingStats.dayCount(from: inCairo("2026-10-29T12:00:00"), to: inCairo("2026-10-30T12:00:00"),
                                       calendar: cairo) == 1)
        #expect(TrainingStats.dayCount(from: inCairo("2026-04-19T12:00:00"), to: inCairo("2026-04-26T12:00:00"),
                                       calendar: cairo) == 7)
    }

    /// The body-weight sparkline was spaced by position, so ten weigh-ins in a
    /// week then one ten weeks later drew a long wiggle and one short segment.
    @Test func weighInsAreSpacedByTheDaysBetweenThem() throws {
        let start = inCairo("2026-03-01T08:00:00")
        // Seven weigh-ins on seven days, then one ten weeks on.
        var dates = try (0..<7).map { try #require(cairo.date(byAdding: .day, value: $0, to: start)) }
        dates.append(try #require(cairo.date(byAdding: .day, value: 70, to: start)))
        let positions = TrainingStats.weighInPositions(dates, calendar: cairo)
        try #require(positions.count == dates.count)
        #expect(positions.first == 0)
        #expect(positions.last == 1)
        #expect(abs(positions[6] - 6.0 / 70.0) < 1e-9)
        #expect(abs(positions[1] - 1.0 / 70.0) < 1e-9)
        #expect(zip(positions, positions.dropFirst()).allSatisfy { $0 <= $1 })

        // Two days apart across the spring change, with one between: exactly the middle.
        let across = ["2026-04-23", "2026-04-24", "2026-04-25"].map { inCairo("\($0)T12:00:00") }
        #expect(TrainingStats.weighInPositions(across, calendar: cairo) == [0, 0.5, 1])
        // With no day between them there is nothing to space.
        let sameDay = [inCairo("2026-04-23T07:00:00"), inCairo("2026-04-23T19:00:00")]
        #expect(TrainingStats.weighInPositions(sameDay, calendar: cairo) == [0.5, 0.5])
        #expect(TrainingStats.weighInPositions([], calendar: cairo).isEmpty)
    }

    @Test(arguments: [
        (0, nil), (-3, nil), (1, "1 day"), (9, "9 days"), (13, "13 days"), (14, "2 weeks"),
        (42, "6 weeks"), (45, "6 weeks"), (46, "7 weeks"), (84, "12 weeks"),
    ] as [(Int, String?)])
    func theWeightChangeNamesItsSpanInDaysThenWholeWeeks(days: Int, label: String?) {
        #expect(TrainingStats.changeSpan(days: days, locale: Locale(identifier: "en_US")) == label)
    }

    // MARK: - Windows

    @Test func theSevenDayWindowAndTheOneBeforeItMeetWithoutAGap() throws {
        let rig = try Rig()
        let today = utc.startOfDay(for: now)
        func finished(_ offset: Int) throws -> WorkoutSession {
            rig.session(try #require(utc.date(byAdding: .day, value: offset, to: today)), [Self.hold])
        }
        let fourteenDaysAgo = try finished(-14)
        let thirteenDaysAgo = try finished(-13)
        let sevenDaysAgo = try finished(-7)
        let sixDaysAgo = try finished(-6)
        let currentDay = try finished(0)
        let tomorrow = try finished(1)
        let sessions = [fourteenDaysAgo, thirteenDaysAgo, sevenDaysAgo, sixDaysAgo, currentDay, tomorrow]

        // Today's chart bucket and the six before it.
        let current = TrainingStats.sessions(in: sessions, days: 7, calendar: utc, now: now)
        #expect(Set(current.map(\.id)) == [sixDaysAgo.id, currentDay.id])
        let previous = TrainingStats.previousWindow(sessions, days: 7, calendar: utc, now: now)
        #expect(Set(previous.map(\.id)) == [thirteenDaysAgo.id, sevenDaysAgo.id])
        // Today's session belongs to the newest bucket of the weekly sparkline.
        #expect(TrainingStats.weeklySessionCounts(sessions, weeks: 2, calendar: utc, now: now) == [2, 2])
    }

    @Test func aLoggedHoldIsADayTrainedThoughItMovedNoWeight() throws {
        let rig = try Rig()
        let today = utc.startOfDay(for: now)
        let hold = rig.session(today, [Self.hold])
        let empty = rig.session(TrainingStats.startOfDay(-1, from: today, calendar: utc), [])
        #expect(hold.totalVolumeKg == 0)
        #expect(TrainingStats.trainedDays(in: [hold, empty], calendar: utc) == [today])
    }

    /// The first half hour of the window's first day and the last half hour
    /// before it both sit on the edge that used to land an hour late.
    @Test func theWindowsMeetAtMidnightBesideCairosShortDay() throws {
        try requireMidnightSpringForward(on: "2026-04-24", in: "Africa/Cairo")
        let rig = try Rig()
        let onFriday = inCairo("2026-04-24T12:00:00")
        let windowStart = rig.session(inCairo("2026-04-18T00:30:00"), [Self.hold])
        let lastWeek = rig.session(inCairo("2026-04-17T23:30:00"), [Self.hold])
        let edges = [windowStart, lastWeek]
        #expect(TrainingStats.sessions(in: edges, days: 7, calendar: cairo, now: onFriday).map(\.id) == [windowStart.id])
        #expect(TrainingStats.previousWindow(edges, days: 7, calendar: cairo, now: onFriday).map(\.id) == [lastWeek.id])
        #expect(TrainingStats.weeklySessionCounts(edges, weeks: 2, calendar: cairo, now: onFriday) == [1, 1])
    }

    @Test func dailyBucketsLandOnTheirOwnDaysAcrossTheSpringForward() throws {
        let rig = try Rig()
        let zone = "America/New_York"
        let calendar = TestClock.calendar(in: zone)
        let sessions = [
            rig.session(TestClock.at("2026-03-07T20:00:00", in: zone), [Work(kg: 100, reps: 5)]),
            rig.session(TestClock.at("2026-03-08T00:30:00", in: zone), [Work(kg: 100, reps: 5), Work(kg: 100, reps: 5)]),
            rig.session(TestClock.at("2026-03-08T15:00:00", in: zone), [Work(kg: 100, reps: 5)]),
            rig.session(TestClock.at("2026-03-10T09:00:00", in: zone), [Work(kg: 100, reps: 5)]),
        ]
        let points = TrainingStats.daily(.sets, sessions: sessions, days: 4, calendar: calendar,
                                         now: TestClock.at("2026-03-10T12:00:00", in: zone))
        #expect(points.map(\.value) == [1, 3, 0, 1])
        let expectedDays = ["2026-03-07", "2026-03-08", "2026-03-09", "2026-03-10"]
            .map { TestClock.at("\($0)T00:00:00", in: zone) }
        #expect(points.map(\.date) == expectedDays)
        #expect(TrainingStats.daily(.sets, sessions: sessions, days: 0, calendar: calendar, now: now).isEmpty)
        #expect(TrainingStats.daily(.sets, sessions: sessions, days: -3, calendar: calendar, now: now).isEmpty)
    }

    @Test func sevenDayBucketsIncludeTheirFirstDayAndNotTheNextBucketsLast() throws {
        let rig = try Rig()
        let sessions = [
            "2026-03-11T08:00:00", "2026-03-08T08:00:00", "2026-03-05T00:00:00",
            "2026-03-04T23:59:00", "2026-02-26T00:00:00", "2026-02-25T23:59:00",
        ].map { rig.trained($0) }
        let counts = TrainingStats.weeklySessionCounts(sessions, weeks: 2, calendar: utc, now: now)
        #expect(counts == [2, 3])
        #expect(TrainingStats.weeklySessionCounts(sessions, weeks: 0, calendar: utc, now: now).isEmpty)
    }

    @Test func changeNeedsABaselineAndAverageNeedsNoFullWindow() {
        #expect(TrainingStats.change(from: 0, to: 5) == nil)
        #expect(TrainingStats.change(from: -3, to: 5) == nil)
        #expect(TrainingStats.change(from: 100, to: 125) == 0.25)
        #expect(TrainingStats.change(from: 100, to: 50) == -0.5)

        let points = [3.0, 6, 9, 12].enumerated().map {
            TrainingStats.DayPoint(date: now.addingTimeInterval(Double($0.offset) * 86_400), value: $0.element)
        }
        #expect(TrainingStats.rollingAverage(points, window: 3).map(\.value) == [3, 4.5, 6, 9])
        #expect(TrainingStats.rollingAverage(points, window: 1).map(\.value) == [3, 6, 9, 12])
        #expect(TrainingStats.rollingAverage([], window: 3).isEmpty)
    }

    // MARK: - Volume

    @Test func volumeCountsEveryKilogramThatMovedAndNothingThatDidNot() throws {
        let rig = try Rig()
        let big = rig.session(TestClock.at("2026-03-09T09:00:00"), [
            Work(kg: 100, reps: 5),
            Work(kg: 200, reps: 5, logged: false),
            // A drop's back-off row: a set the lifter did not add, but weight they lifted.
            Work(kg: 80, reps: 6, drop: true),
            Work(id: "pull-up", kg: 0, reps: 10, tracking: .bodyweightReps),
            Work(id: "pull-up", kg: 20, reps: 8, tracking: .bodyweightReps),
            Work(id: "plank-bodyweight", seconds: 60, tracking: .duration),
        ])
        let small = rig.trained("2026-03-10T09:00:00")
        #expect(big.completedSets.count == 5)
        #expect(big.effortSets.count == 4)
        #expect(big.totalVolumeKg == 500 + 480 + 160)
        #expect(TrainingStats.totalVolume([big, small]) == 500 + 480 + 160 + 500)
        #expect(TrainingStats.totalVolume([]) == 0)

        // Kilograms are the storage unit: the display unit never reaches the total.
        let original = AppSettings.shared.weightUnit
        defer { AppSettings.shared.weightUnit = original }
        AppSettings.shared.weightUnit = .lb
        #expect(TrainingStats.totalVolume([big, small]) == 500 + 480 + 160 + 500)
    }

    @Test func aSessionOfUnloggedSetsMovedNothing() throws {
        let rig = try Rig()
        let empty = rig.session(TestClock.at("2026-03-09T09:00:00"), [Work(kg: 100, reps: 5, logged: false)])
        #expect(empty.totalVolumeKg == 0)
        #expect(TrainingStats.totalVolume([empty]) == 0)
    }

    // MARK: - Records

    /// A session's sets in the order they were logged; a relationship array
    /// makes no promise about its own order.
    private func logged(_ session: WorkoutSession) -> [SetLog] {
        session.sets.sorted { $0.setIndex < $1.setIndex }
    }

    private func weightRecord(_ record: TrainingStats.PersonalRecord) throws -> (kg: Double, reps: Int, oneRepMax: Double?) {
        guard case let .weight(kg, reps, oneRepMax) = record.measure else {
            Issue.record("Expected a weight record, got \(record.measure)")
            throw CancellationError()
        }
        return (kg, reps, oneRepMax)
    }

    @Test func theRecordIsTheSetWithTheBestEstimatedMaxNotTheHeaviestOrTheLongest() throws {
        let rig = try Rig()
        let sessions = [
            rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(kg: 100, reps: 5)]),
            rig.session(TestClock.at("2026-03-04T09:00:00"), [Work(kg: 90, reps: 8)]),
            rig.session(TestClock.at("2026-03-06T09:00:00"), [Work(kg: 110, reps: 1)]),
        ]
        let records = TrainingStats.records(in: sessions)
        #expect(records.count == 1)
        let best = try weightRecord(#require(records.first))
        #expect(best.kg == 100)
        #expect(best.reps == 5)
        // 100 x 5 estimates 116.7 against 114 for 90 x 8 and 110 for the single.
        let estimate = try #require(best.oneRepMax)
        #expect(abs(estimate - 116.667) < 0.01)
        #expect(TrainingStats.records(in: []).isEmpty)
    }

    @Test func aTiedRecordBelongsToTheSetThatReachedItFirst() throws {
        let rig = try Rig()
        let early = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(kg: 100, reps: 5)])
        let late = rig.session(TestClock.at("2026-03-09T09:00:00"), [Work(kg: 100, reps: 5)])
        // Handed over newest first, so only the dates can be what decides.
        let record = try #require(TrainingStats.records(in: [late, early]).first)
        #expect(record.achievedAt == logged(early)[0].completedAt)
    }

    @Test func bodyweightAndTimedWorkKeepTheirOwnKindsOfRecord() throws {
        let rig = try Rig()
        let pull = "pull-up"
        let sessions = [
            rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: pull, reps: 12, tracking: .bodyweightReps)]),
            rig.session(TestClock.at("2026-03-04T09:00:00"), [Work(id: pull, reps: 15, tracking: .bodyweightReps)]),
            rig.session(TestClock.at("2026-03-06T09:00:00"), [Work(id: pull, kg: 10, reps: 6, tracking: .bodyweightReps)]),
            rig.session(TestClock.at("2026-03-03T09:00:00"), [Work(id: "plank-bodyweight", seconds: 45, tracking: .duration)]),
            rig.session(TestClock.at("2026-03-05T09:00:00"), [Work(id: "plank-bodyweight", seconds: 60, tracking: .duration)]),
        ]
        let records = TrainingStats.records(in: sessions)
        let measures = records.map(\.measure)
        #expect(measures.count == 3)
        #expect(measures.contains(.reps(15)))
        #expect(measures.contains(.addedLoad(kg: 10, reps: 6)))
        #expect(measures.contains(.duration(seconds: 60)))
        // Newest achievement first.
        #expect(records.map(\.achievedAt) == records.map(\.achievedAt).sorted(by: >))
    }

    @Test func aRowThatContinuedASetCanNeitherSetNorBlockARecord() throws {
        let rig = try Rig()
        let first = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(kg: 62.5, reps: 8)])
        // 62 x 10 estimates a higher max than 62.5 x 8, but it was lifted
        // already fatigued, inside the set above it.
        let second = rig.session(TestClock.at("2026-03-09T09:00:00"), [
            Work(kg: 60, reps: 8), Work(kg: 62, reps: 10, drop: true),
        ])
        let sessions = [first, second]
        let best = try weightRecord(#require(TrainingStats.records(in: sessions).first))
        #expect(best.kg == 62.5)
        #expect(best.reps == 8)
        #expect(!TrainingStats.isPersonalRecord(logged(second)[1], in: sessions))
        #expect(!TrainingStats.isPersonalRecord(logged(second)[0], in: sessions))
    }

    @Test func aPersonalRecordMustBeatEverythingBeforeItNotJustMatchIt() throws {
        let rig = try Rig()
        let first = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(kg: 100, reps: 5)])
        let tie = rig.session(TestClock.at("2026-03-04T09:00:00"), [Work(kg: 100, reps: 5)])
        let better = rig.session(TestClock.at("2026-03-06T09:00:00"), [Work(kg: 102.5, reps: 5)])
        let unlogged = rig.session(TestClock.at("2026-03-08T09:00:00"), [Work(kg: 200, reps: 5, logged: false)])
        let history = [first, tie, better, unlogged]
        // The first set of a kind is a baseline, with nothing to break.
        #expect(!TrainingStats.isPersonalRecord(logged(first)[0], in: history))
        #expect(!TrainingStats.isPersonalRecord(logged(tie)[0], in: history))
        #expect(TrainingStats.isPersonalRecord(logged(better)[0], in: history))
        #expect(!TrainingStats.isPersonalRecord(logged(unlogged)[0], in: history))
    }

    /// Uncapped, 60 kg x 30 estimated 120 kg and beat 100 kg x 5: the logger
    /// awarded a trophy and the card printed a set that says nothing about
    /// strength.
    @Test func repsPastTheCapAddNothingToTheEstimateAndOnlyBreakATie() throws {
        let rig = try Rig()
        let heavy = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: "squat", kg: 100, reps: 5)])
        let long = rig.session(TestClock.at("2026-03-03T09:00:00"), [Work(id: "squat", kg: 60, reps: 30)])
        let heavyFive = logged(heavy)[0]
        let lightThirty = logged(long)[0]
        // The uncapped Epley figure this guards against.
        #expect(abs(lightThirty.estimatedOneRepMax - 120) < 0.01)

        let squat = try #require(TrainingStats.records(in: [heavy, long]).first { $0.catalogID == "squat" })
        let best = try weightRecord(squat)
        #expect(best.kg == 100)
        #expect(best.reps == 5)
        let estimate = try #require(best.oneRepMax)
        #expect(abs(estimate - 116.67) < 0.01)
        #expect(squat.achievedAt == heavyFive.completedAt)
        #expect(!TrainingStats.isPersonalRecord(lightThirty, among: [heavyFive, lightThirty]))

        let cap = TrainingStats.oneRepMaxRepCap
        func standing(_ reps: Int) throws -> TrainingStats.RecordStanding {
            try #require(TrainingStats.standing(of: SetLog(catalogID: "x", exerciseName: "X", exerciseOrder: 0,
                                                           setIndex: 0, weightKg: 50, reps: reps, tracking: .weightReps)))
        }
        let atCap = try standing(cap)
        let pastCap = try standing(cap + 1)
        #expect(atCap.score.value == pastCap.score.value)
        #expect(atCap.score < pastCap.score)
    }

    /// A long set is still a record against other long sets: more reps at the
    /// same load, or a heavier load for as many.
    @Test func aLongSetIsARecordOnlyAgainstWhatItCanFairlyBeCompared() throws {
        func raise(_ kg: Double, _ reps: Int, day: Int) -> SetLog {
            let set = SetLog(catalogID: "lateral-raise", exerciseName: "Lateral Raise", exerciseOrder: 0,
                             setIndex: 0, weightKg: kg, reps: reps, tracking: .weightReps)
            set.isCompleted = true
            set.completedAt = now.addingTimeInterval(Double(day) * 86_400)
            return set
        }
        let raise15 = raise(12, 15, day: 0)
        let raise20 = raise(12, 20, day: 1)
        let lighter = raise(10, 40, day: 2)
        let heavier = raise(14, 15, day: 3)
        #expect(TrainingStats.isPersonalRecord(raise20, among: [raise15, raise20]))
        #expect(!TrainingStats.isPersonalRecord(lighter, among: [raise15, raise20, lighter]),
                "A lighter load for many more reps is not a heavier lift")
        #expect(TrainingStats.isPersonalRecord(heavier, among: [raise15, raise20, heavier]))

        let rig = try Rig()
        let history = [
            rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: "lateral-raise", kg: 12, reps: 15)]),
            rig.session(TestClock.at("2026-03-03T09:00:00"), [Work(id: "lateral-raise", kg: 12, reps: 20)]),
        ]
        let record = try #require(TrainingStats.records(in: history).first { $0.catalogID == "lateral-raise" })
        // Past the cap the row shows the load and the reps, and no estimate.
        #expect(record.measure == .weight(kg: 12, reps: 20, estimatedOneRepMax: nil))
        #expect(record.achievedAt == logged(history[1])[0].completedAt)
    }

    @Test func aRecordsLoadEstimateAndDateAllComeFromOneSet() throws {
        let rig = try Rig()
        let single = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: "press", kg: 105, reps: 1)])
        let five = rig.session(TestClock.at("2026-03-11T09:00:00"), [Work(id: "press", kg: 100, reps: 5)])
        let press = try #require(TrainingStats.records(in: [single, five]).first { $0.catalogID == "press" })
        let best = try weightRecord(press)
        // The set the estimate came from, not the heaviest set.
        #expect(best.kg == 100)
        #expect(best.reps == 5)
        let estimate = try #require(best.oneRepMax)
        #expect(abs(estimate - 116.67) < 0.01)
        #expect(press.achievedAt == logged(five)[0].completedAt)
    }

    /// Two records, two sets, two dates: one row would date itself by one set
    /// and print the other's figure beside it.
    @Test func unloadedRepsAndAddedLoadAreTwoRecordsWithTheirOwnDates() throws {
        let rig = try Rig()
        let unloaded = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: "pull-up", reps: 12, tracking: .bodyweightReps)])
        let weighted = rig.session(TestClock.at("2026-03-07T09:00:00"), [
            Work(id: "pull-up", kg: 10, reps: 8, tracking: .bodyweightReps),
            Work(id: "dip", kg: 20, reps: 5, tracking: .bodyweightReps),
        ])
        let records = TrainingStats.records(in: [unloaded, weighted])
        func record(_ id: String, _ kind: String) -> TrainingStats.PersonalRecord? {
            records.first { $0.catalogID == id && $0.measure.kindName == kind }
        }
        let reps = try #require(record("pull-up", "reps"))
        let added = try #require(record("pull-up", "added"))
        #expect(reps.measure == .reps(12))
        #expect(added.measure == .addedLoad(kg: 10, reps: 8))
        #expect(reps.achievedAt == logged(unloaded)[0].completedAt)
        #expect(added.achievedAt == logged(weighted)[0].completedAt)
        #expect(reps.id != added.id)
        #expect(record("dip", "reps") == nil, "Weighted reps must not stand in for an unloaded record")
    }

    @Test func eachTrackingModeRecordsWhatWasMeasuredAndNothingInferred() throws {
        let rig = try Rig()
        func on(_ day: Int, _ work: Work) -> WorkoutSession {
            rig.session(TestClock.at("2026-03-02T09:00:00").addingTimeInterval(Double(day) * 86_400), [work])
        }
        let records = TrainingStats.records(in: [
            on(0, Work(id: "plank", seconds: 75, tracking: .duration)),
            on(1, Work(id: "push-up", reps: 15, tracking: .bodyweightReps)),
            on(2, Work(id: "pull-up", kg: 10, reps: 8, tracking: .bodyweightReps)),
            on(3, Work(id: "test-unweighted-load", reps: 10)),
        ])
        func measure(_ id: String) -> TrainingStats.RecordMeasure? { records.first { $0.catalogID == id }?.measure }

        #expect(measure("plank") == .duration(seconds: 75))
        #expect(!records.contains { $0.catalogID == "plank" && $0.achievedAt == .distantPast })
        #expect(measure("push-up") == .reps(15))
        #expect(!records.contains { $0.catalogID == "push-up" && $0.measure.kindName == "added" })
        // Added load is a record only when it was logged.
        #expect(measure("pull-up") == .addedLoad(kg: 10, reps: 8))
        #expect(!records.contains { $0.catalogID == "pull-up" && $0.measure.kindName == "reps" })
        // A rep set with no load entered must not claim a zero-kilogram record.
        #expect(measure("test-unweighted-load") == .reps(10))
    }

    @Test func aSetOfOneKindIsNeverTheBaselineForAnother() throws {
        let rig = try Rig()
        let start = TestClock.at("2026-03-02T09:00:00")
        let added = logged(rig.session(start, [Work(id: "pull-up", kg: 10, reps: 8, tracking: .bodyweightReps)]))[0]
        let unloaded = logged(rig.session(start, [Work(id: "push-up", reps: 15, tracking: .bodyweightReps)]))[0]
        func after(_ earlier: SetLog, id: String, kg: Double = 0, reps: Int) throws -> SetLog {
            let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: 0,
                             weightKg: kg, reps: reps, tracking: .bodyweightReps)
            set.isCompleted = true
            set.completedAt = try #require(earlier.completedAt).addingTimeInterval(60)
            return set
        }
        let firstUnloaded = try after(added, id: "pull-up", reps: 12)
        #expect(!TrainingStats.isPersonalRecord(firstUnloaded, among: [added, firstUnloaded]),
                "A loaded set cannot serve as an unloaded rep baseline")
        let firstLoaded = try after(unloaded, id: "push-up", kg: 5, reps: 10)
        #expect(!TrainingStats.isPersonalRecord(firstLoaded, among: [unloaded, firstLoaded]),
                "An unloaded set cannot serve as an added-load baseline")
    }

    // MARK: - The session summary

    /// A set as the summary builds it, standing alone rather than in a session.
    private func summarySet(_ id: String, kg: Double = 0, reps: Int = 0, seconds: Int = 0, order: Int = 0,
                            index: Int = 0, tracking: TrackingMode = .weightReps) -> SetLog {
        SetLog(catalogID: id, exerciseName: id, exerciseOrder: order, setIndex: index,
               weightKg: kg, reps: reps, seconds: seconds, tracking: tracking)
    }

    /// The summary ranks each kind by its own measure. Ranking every kind on the
    /// estimate, which is 0 for holds and unloaded reps, picked whichever came
    /// first.
    @Test func theSummaryListsTheBestSetOfEachExerciseAndKindInSessionOrder() {
        let plank60 = summarySet("plank", seconds: 60, order: 1, index: 0, tracking: .duration)
        let plank75 = summarySet("plank", seconds: 75, order: 1, index: 1, tracking: .duration)
        let reps12 = summarySet("pull-up", reps: 12, order: 2, index: 0, tracking: .bodyweightReps)
        let reps15 = summarySet("pull-up", reps: 15, order: 2, index: 1, tracking: .bodyweightReps)
        let added = summarySet("pull-up", kg: 10, reps: 5, order: 2, index: 2, tracking: .bodyweightReps)
        let lighter = summarySet("bench", kg: 110, reps: 1, order: 0, index: 1)
        let stronger = summarySet("bench", kg: 100, reps: 5, order: 0, index: 0)
        let long = summarySet("bench", kg: 60, reps: 30, order: 0, index: 2)
        let candidates = [plank60, plank75, reps12, reps15, added, lighter, stronger, long]
        for ordering in [candidates, candidates.reversed(), candidates.shuffled()] {
            let rows = TrainingStats.summaryRecords(from: ordering)
            #expect(rows.map(\.id) == [stronger, plank75, reps15, added].map(\.id),
                    "Got \(rows.map(TrainingStats.setLabel))")
        }

        #expect(TrainingStats.setLabel(reps15) == "15 reps", "An unloaded set must not print a weight")
        #expect(TrainingStats.setLabel(summarySet("x", reps: 1, tracking: .bodyweightReps)) == "1 rep")
        #expect(TrainingStats.setLabel(plank75) == "75s")
        #expect(TrainingStats.setLabel(stronger) == "\(stronger.weightLabel) × 5")
        #expect(TrainingStats.setLabel(added) == "+\(added.weightLabel) × 5")
        #expect(!TrainingStats.setLabel(summarySet("x", reps: 10)).contains("kg"),
                "A rep set with no load entered must not claim 0 kg")
    }

    @Test func twoHoldsThatBothBeatThePriorBestListOnlyTheLonger() throws {
        let rig = try Rig()
        let history = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: "plank", seconds: 50, tracking: .duration)])
        let today = rig.session(TestClock.at("2026-03-03T09:00:00"), [
            Work(id: "plank", seconds: 60, tracking: .duration), Work(id: "plank", seconds: 75, tracking: .duration),
        ])
        let summary = TrainingStats.summaryRecords(from: TrainingStats.recordSets(in: today, history: [today, history]))
        #expect(summary.map(\.id) == [logged(today)[1].id])
    }

    /// Typing in the session note saves on every character. The summary is
    /// keyed so that doesn't recompute it, and a set coming or going does.
    @Test func aNoteEditLeavesTheSummaryKeyAloneAndASetChangesIt() throws {
        let rig = try Rig()
        let today = rig.session(TestClock.at("2026-03-03T09:00:00"), [
            Work(id: "plank", seconds: 60, tracking: .duration), Work(id: "plank", seconds: 75, tracking: .duration),
        ])
        let before = TrainingStats.SummaryRecordsKey(today)
        today.notes = "Felt strong"
        today.notes = "Felt strong today, ate well"
        #expect(TrainingStats.SummaryRecordsKey(today) == before)

        let last = logged(today)[1]
        let loggedAt = last.completedAt
        last.unlog()
        #expect(TrainingStats.SummaryRecordsKey(today) != before)
        last.isCompleted = true
        last.completedAt = loggedAt
        #expect(TrainingStats.SummaryRecordsKey(today) == before)
    }

    // MARK: - Exercise history

    @Test func lastPerformanceIsTheNewestFinishedSessionsOwnSetsAndHistoryKeepsTheDrops() throws {
        let rig = try Rig()
        let older = rig.session(TestClock.at("2026-03-02T09:00:00"), [
            Work(kg: 100, reps: 5), Work(kg: 90, reps: 10, drop: true),
        ])
        let newer = rig.session(TestClock.at("2026-03-09T09:00:00"), [Work(kg: 102.5, reps: 5)])
        let running = rig.session(TestClock.at("2026-03-10T09:00:00"), finished: false, [Work(kg: 105, reps: 5)])
        let all = [older, newer, running]
        let bench = "barbell-bench-press"

        #expect(TrainingStats.lastPerformance(of: bench, in: all).map(\.weightKg) == [102.5])
        // Excluding the newest falls back to the one before, without its drop row.
        #expect(TrainingStats.lastPerformance(of: bench, in: all, excluding: newer.id).map(\.weightKg) == [100])
        #expect(TrainingStats.lastPerformance(of: "deadlift", in: all).isEmpty)
        #expect(TrainingStats.lastPerformance(of: bench, in: []).isEmpty)

        let history = TrainingStats.history(for: bench, in: all)
        #expect(history.map(\.id) == [newer.id, older.id])
        let summary = try #require(history.last)
        #expect(summary.volumeKg == 500 + 900)
        #expect(summary.topSet?.weightKg == 100)
        // 90 x 10 would estimate 120, but a drop's rows say nothing about strength.
        #expect(abs(summary.bestEstimatedOneRepMax - 116.667) < 0.01)
    }

    @Test func aMergedExercisesOldIDFindsItsHistory() throws {
        let rig = try Rig()
        let old = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: "scaption-dumbbell", kg: 8, reps: 12)])
        #expect(TrainingStats.lastPerformance(of: "scaption", in: [old]).count == 1)
        #expect(TrainingStats.history(for: "scaption-dumbbell", in: [old]).count == 1)
    }

    /// Rows keep the ID they were logged with, so a merged exercise is asked for
    /// under two spellings and must give one answer to both.
    @Test func bothSpellingsOfAMergedExerciseShareOneHistoryProgressionAndRecord() throws {
        let rig = try Rig()
        let oldSession = rig.session(TestClock.at("2026-03-02T09:00:00"), [Work(id: "scaption-dumbbell", kg: 12, reps: 10)])
        let newSession = rig.session(TestClock.at("2026-03-03T09:00:00"), [Work(id: "scaption", kg: 12, reps: 8)])
        let oldID = logged(oldSession)[0]
        let survivorID = logged(newSession)[0]
        let merged = [oldSession, newSession]

        let history = TrainingStats.history(for: "scaption", in: merged)
        #expect(history.count == 2)
        #expect(history.flatMap(\.sets).count == 2)
        #expect(TrainingStats.history(for: "scaption-dumbbell", in: merged).count == 2)
        #expect(oldID.catalogID == "scaption-dumbbell", "Historical rows keep their logged ID")
        #expect(TrainingStats.lastPerformance(of: "scaption", in: [oldSession]).first?.id == oldID.id)
        #expect(TrainingStats.lastPerformance(of: "scaption-dumbbell", in: merged).first?.id == survivorID.id)

        // A weaker set under the survivor's ID does not reset the record's baseline.
        #expect(!TrainingStats.isPersonalRecord(survivorID, among: [oldID, survivorID]))
        #expect(TrainingStats.recordCandidates(in: merged)["scaption"]?.count == 2)
        #expect(TrainingStats.recordSets(in: newSession, history: merged).isEmpty)
        #expect(TrainingStats.records(in: merged).filter { $0.catalogID == "scaption" }.count == 1)
    }

    // MARK: - Lift trends

    /// A session `daysAgo` before `now`, holding `work`.
    private func ago(_ rig: Rig, _ daysAgo: Int, _ work: [Work]) -> WorkoutSession {
        rig.session(now.addingTimeInterval(-Double(daysAgo) * 86_400), work)
    }

    /// One lift trained every `gap` days for as many sessions as loads, oldest first.
    private func series(_ rig: Rig, _ id: String, loads: [Double], gap: Int = 7, newest: Int = 0) -> [WorkoutSession] {
        loads.enumerated().map { index, kg in
            ago(rig, newest + (loads.count - 1 - index) * gap, [Work(id: id, kg: kg, reps: 5)])
        }
    }

    private func trends(_ sessions: [WorkoutSession], rungKg: Double = 2.5,
                        limit: Int = LiftTrends.maximumRows) -> [LiftTrends.Lift] {
        LiftTrends.lifts(in: sessions, now: now, calendar: utc, incrementKg: { _ in rungKg }, limit: limit)
    }

    private func trend(_ id: String, _ sessions: [WorkoutSession], rungKg: Double = 2.5) -> LiftTrends.Trend? {
        trends(sessions, rungKg: rungKg).first { $0.catalogID == id }?.trend
    }

    @Test func aLiftIsMovingFlatOrSlidingByItsBestEstimates() throws {
        let rig = try Rig()
        #expect(trend("bench", series(rig, "bench", loads: [60, 60, 62.5, 65, 67.5, 70])) == .moving)
        #expect(trend("squat", series(rig, "squat", loads: [100, 100, 100, 100, 100])) == .flat)
        #expect(trend("row", series(rig, "row", loads: [100, 100, 95, 90, 85])) == .sliding)
    }

    /// One rung is what a plate does to a good day, not progress. Two is.
    @Test func oneRungOfChangeIsFlatAndTwoIsATrend() throws {
        let rig = try Rig()
        #expect(trend("ohp", series(rig, "ohp", loads: [100, 100, 102.5, 102.5])) == .flat)
        #expect(trend("ohp", series(rig, "ohp", loads: [100, 100, 105, 105])) == .moving)
        #expect(trend("ohp", series(rig, "ohp", loads: [100, 100, 97.5, 97.5])) == .flat)
        #expect(trend("ohp", series(rig, "ohp", loads: [100, 100, 95, 95])) == .sliding)
        // The rung is the exercise's own: 5 kg is two rungs of plates but one
        // pin on a 5 kg stack.
        #expect(trend("press", series(rig, "press", loads: [100, 100, 105, 105]), rungKg: 5) == .flat)
    }

    @Test func tooLittleRecentHistoryGetsNoTagAtAll() throws {
        let rig = try Rig()
        #expect(trends(series(rig, "few", loads: [60, 70, 80])).isEmpty, "Three sessions are not a trend")
        #expect(trends(series(rig, "stale", loads: [60, 60, 80, 80], gap: 30)).isEmpty,
                "Sessions older than the window do not count towards the four")
        #expect(trends(series(rig, "block", loads: [60, 62.5, 65, 67.5], gap: 3)).isEmpty,
                "Four sessions in nine days are a block, not a trend")
        #expect(trends([]).isEmpty)
    }

    /// A drop's rows are lifted pre-fatigued and are not the lift.
    @Test func aDropsRowsAreNotTheLiftsBestSet() throws {
        let rig = try Rig()
        let held: [Double] = [100, 100, 100, 100, 100]
        let sessions = held.enumerated().map { index, kg in
            ago(rig, (held.count - 1 - index) * 7, [
                Work(id: "curl", kg: kg, reps: 5),
                Work(id: "curl", kg: index >= 3 ? 130 : 60, reps: 5, drop: true),
            ])
        }
        #expect(trend("curl", sessions) == .flat)
    }

    @Test func workWithNoLoadToCompareIsNeverTagged() throws {
        let rig = try Rig()
        let bodyweight = (0..<6).map { ago(rig, $0 * 7, [Work(id: "pullup", reps: 10 + (5 - $0), tracking: .bodyweightReps)]) }
        let timed = (0..<6).map { ago(rig, $0 * 7, [Work(id: "plank", seconds: 30 + (5 - $0) * 5, tracking: .duration)]) }
        let unloaded = (0..<6).map { ago(rig, $0 * 7, [Work(id: "dip", reps: 8)]) }
        #expect(trends(bodyweight + timed + unloaded).isEmpty)
    }

    @Test func theSessionInProgressIsNotHistoryYet() throws {
        let rig = try Rig()
        let live = rig.session(now.addingTimeInterval(-86_400), finished: false, [Work(id: "live", kg: 90, reps: 5)])
        #expect(trends(series(rig, "live", loads: [60, 60, 60]) + [live]).isEmpty,
                "The session in progress must not make a fourth session")
    }

    @Test func theCardListsAFewLiftsMostRecentlyTrainedFirst() throws {
        let rig = try Rig()
        let many = (0..<7).flatMap { series(rig, "lift\($0)", loads: [60, 60, 70, 70], newest: $0) }
        let listed = trends(many)
        #expect(listed.count == LiftTrends.maximumRows)
        #expect(listed.map(\.catalogID) == (0..<LiftTrends.maximumRows).map { "lift\($0)" })
        #expect(trends(many, limit: 2).count == 2)
        #expect(trends(many, limit: 0).isEmpty)
    }
}
