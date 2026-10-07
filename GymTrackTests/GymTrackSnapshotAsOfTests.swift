import Foundation
import Testing
@testable import GymTrack

/// `GymTrackSnapshot.asOf`, which lets a widget or the watch reloading after
/// midnight, with no app run in between, stop offering yesterday's session and
/// yesterday's week.
///
/// The streak across Cairo's spring-forward and the rotation flag are pinned by
/// `WidgetSnapshotTests`; this holds the rest: the schedule lookup, the week
/// rollover, the finished-today card, a session gone stale, and the cases that
/// must leave the snapshot exactly as the app wrote it.
@MainActor
@Suite(.serialized)
struct GymTrackSnapshotAsOfTests {

    /// UTC with weeks opening on Sunday, so in September and October 2026
    /// Sunday the 27th opens a week, Monday the 28th is a Monday, and Sunday
    /// 4 October opens the next.
    private let calendar: Calendar = {
        var calendar = TestClock.calendar(in: "UTC")
        calendar.firstWeekday = 1
        return calendar
    }()

    // MARK: - Same day

    @Test func laterTheSameDayNothingIsWorkedOutAgain() {
        let snapshot = mondaySnapshot()
        #expect(snapshot.asOf(at(28, 23), calendar: calendar) == snapshot, "The finished card included")
    }

    @Test func aSnapshotWithoutADayIsTakenAtItsWord() {
        var undated = mondaySnapshot()
        undated.day = nil
        #expect(undated.asOf(at(20, month: 10), calendar: calendar) == undated,
                "An older build's snapshot with no day is returned as written")
    }

    @Test func aClockBehindTheStampChangesNothing() {
        let snapshot = mondaySnapshot()
        #expect(snapshot.asOf(at(20), calendar: calendar) == snapshot)
    }

    // MARK: - A later day

    @Test func theNextDayReadsTheRoutinesEntryForItsWeekday() {
        let tuesday = mondaySnapshot().asOf(at(29, 8), calendar: calendar)

        #expect(tuesday.todayTitle == "Pull" && tuesday.todayIsRotation == true, "Tuesday's session, flag included")
        #expect(tuesday.todayExerciseCount == 4 && tuesday.todaySetCount == 12 && tuesday.todayMuscles == ["Back"],
                "The counts and muscles come from that weekday's entry")
        #expect(tuesday.day == calendar.startOfDay(for: at(29)), "The stamp moves to the new day's midnight")
        #expect(tuesday.hasPlan && tuesday.weekVolumeKg == 21000 && tuesday.sessionsThisWeek == 3,
                "Same week: the plan flag and the week's totals are not touched")
        #expect(tuesday.streak == 4, "Trained yesterday, so the streak survives")
    }

    @Test func aWeekdayWithNoSessionReadsAsARestDay() {
        let wednesday = mondaySnapshot().asOf(at(30), calendar: calendar)

        #expect(wednesday.todayTitle == nil && wednesday.todayIsRotation == nil)
        #expect(wednesday.todayExerciseCount == 0 && wednesday.todaySetCount == 0 && wednesday.todayMuscles.isEmpty,
                "A rest day carries no counts or muscles from the day before")
        #expect(!wednesday.hasSessionToday, "hasSessionToday follows the title")
        #expect(wednesday.streak == 0, "Last trained Monday, two days back: the streak has lapsed")
    }

    @Test func yesterdaysFinishedWorkoutIsNotShownAsTodays() {
        #expect(mondaySnapshot().asOf(at(29), calendar: calendar).finishedToday == nil)
    }

    @Test func theWeekRollsOverOnlyWhenANewWeekBegins() {
        let sunday = mondaySnapshot().asOf(at(4, month: 10), calendar: calendar)
        #expect(sunday.sessionsThisWeek == 0 && sunday.weekVolumeKg == 0,
                "A new week starts its count and volume from nothing")
        #expect(sunday.weekStart == calendar.startOfDay(for: at(4, month: 10)), "weekStart moves to the new week's first day")

        let saturday = mondaySnapshot().asOf(at(3, month: 10), calendar: calendar)
        #expect(saturday.sessionsThisWeek == 3 && saturday.weekVolumeKg == 21000, "The last day of the week still counts it")

        var noWeek = mondaySnapshot()
        noWeek.weekStart = nil
        #expect(noWeek.asOf(at(4, month: 10), calendar: calendar).sessionsThisWeek == 3,
                "Without a week stamp the count cannot be judged and is kept")
    }

    @Test func aSnapshotFromBeforeTheScheduleKeepsTodaysFieldsButStillMovesOn() {
        var old = mondaySnapshot()
        old.schedule = nil

        let next = old.asOf(at(29), calendar: calendar)

        #expect(next.todayTitle == "Push" && next.todayExerciseCount == 5,
                "With no schedule to read, today's fields are left rather than guessed")
        #expect(next.finishedToday == nil && next.day == calendar.startOfDay(for: at(29)),
                "The day still moves on and the finished card still goes")
    }

    // MARK: - A session left running

    @Test func aStaleSessionIsDroppedWhateverTheDay() {
        var snapshot = mondaySnapshot()
        let started = at(28, 8)
        snapshot.session = .init(title: "Push", startedAt: started, completedSets: 3, totalSets: 15,
                                 exercise: "Bench", target: "3 x 5", restEndsAt: nil)

        #expect(snapshot.asOf(started.addingTimeInterval(12 * 3600), calendar: calendar).session != nil,
                "Exactly the stale limit is still running")
        #expect(snapshot.asOf(at(28, 21), calendar: calendar).session == nil,
                "Past the limit on the same day the widget stops showing it running")
        #expect(snapshot.asOf(at(28, 19), calendar: calendar).todayTitle == "Push",
                "Dropping the session does not disturb the rest of the day")
        #expect(snapshot.asOf(at(29, 9), calendar: calendar).session == nil,
                "A stale session does not survive the day rolling over")

        var overnight = snapshot
        overnight.session?.startedAt = at(28, 23)
        #expect(overnight.asOf(at(29, 3), calendar: calendar).session != nil,
                "A session still inside the limit runs on past midnight")
    }

    // MARK: - Fixture

    private func at(_ day: Int, _ hour: Int = 10, month: Int = 9) -> Date {
        TestClock.at(String(format: "2026-%02d-%02dT%02d:00:00", month, day, hour))
    }

    private let schedule: [GymTrackSnapshot.ScheduledDay] = [
        .init(weekday: 2, title: "Push", exerciseCount: 5, setCount: 15, muscles: ["Chest", "Triceps"]),
        .init(weekday: 3, title: "Pull", exerciseCount: 4, setCount: 12, muscles: ["Back"], isRotation: true),
    ]

    /// Written on Monday 28 September, the day the schedule's Push falls on.
    private func mondaySnapshot() -> GymTrackSnapshot {
        let monday = calendar.startOfDay(for: at(28))
        return GymTrackSnapshot(
            updatedAt: at(28, 9), day: monday, schedule: schedule, lastTrainedDay: monday,
            weekStart: calendar.startOfDay(for: at(27)),
            finishedToday: .init(title: "Push", sets: 15, volumeKg: 9000, endedAt: at(28, 9)),
            hasPlan: true, todayTitle: "Push", todayExerciseCount: 5, todaySetCount: 15,
            todayMuscles: ["Chest", "Triceps"], streak: 4, sessionsThisWeek: 3, weekVolumeKg: 21000)
    }
}
