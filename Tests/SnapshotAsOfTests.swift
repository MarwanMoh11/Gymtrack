import Foundation

/// Run with scripts/test-snapshot-asof.sh; no simulator is needed.
///
/// `GymTrackSnapshot.asOf` is what lets a widget reloading after midnight, with
/// no app run in between, stop offering yesterday's session and yesterday's
/// week. TodayMirrorTests pins the streak across Cairo's spring-forward and the
/// rotation flag; this holds the rest: the schedule lookup, the week rollover,
/// the finished-today card, a session gone stale, and the cases that must
/// leave the snapshot exactly as the app wrote it.
@main
struct SnapshotAsOfTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// September/October 2026: Sunday 27th opens a week, Monday 28th is a
    /// Monday, and Sunday 4 October opens the next.
    static func at(_ day: Int, _ hour: Int = 10, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    static let schedule: [GymTrackSnapshot.ScheduledDay] = [
        .init(weekday: 2, title: "Push", exerciseCount: 5, setCount: 15, muscles: ["Chest", "Triceps"]),
        .init(weekday: 3, title: "Pull", exerciseCount: 4, setCount: 12, muscles: ["Back"], isRotation: true),
    ]

    /// Written on Monday 28 September, the day the schedule's Push falls on.
    static func mondaySnapshot() -> GymTrackSnapshot {
        let monday = calendar.startOfDay(for: at(28))
        return GymTrackSnapshot(
            day: monday, schedule: schedule, lastTrainedDay: monday,
            weekStart: calendar.startOfDay(for: at(27)),
            finishedToday: .init(title: "Push", sets: 15, volumeKg: 9000, endedAt: at(28, 9)),
            hasPlan: true, todayTitle: "Push", todayExerciseCount: 5, todaySetCount: 15,
            todayMuscles: ["Chest", "Triceps"], streak: 4, sessionsThisWeek: 3, weekVolumeKg: 21000)
    }

    static func main() {
        sameDayIsLeftAlone()
        nextDayReadsTheScheduleForItsWeekday()
        restDayClearsToday()
        finishedTodayDoesNotOutliveTheDay()
        weekRollsOverOnlyWhenANewWeekBegins()
        aSnapshotWithoutADayIsTakenAtItsWord()
        aClockBehindTheStampChangesNothing()
        staleSessionIsDroppedWhateverTheDay()
        oldSnapshotWithoutScheduleKeepsItsTitle()

        guard failures == 0 else {
            print("\(failures) snapshot as-of check(s) failed")
            exit(1)
        }
        print("Snapshot as-of tests passed")
    }

    static func sameDayIsLeftAlone() {
        let snapshot = mondaySnapshot()
        check(snapshot.asOf(at(28, 23), calendar: calendar) == snapshot,
              "Later the same day nothing is worked out again, the finished card included")
    }

    static func nextDayReadsTheScheduleForItsWeekday() {
        let tuesday = mondaySnapshot().asOf(at(29, 8), calendar: calendar)
        check(tuesday.todayTitle == "Pull" && tuesday.todayIsRotation == true,
              "Tuesday must show the routine's Tuesday, flag included")
        check(tuesday.todayExerciseCount == 4 && tuesday.todaySetCount == 12 && tuesday.todayMuscles == ["Back"],
              "The day's counts and muscles come from that weekday's entry")
        check(tuesday.day == calendar.startOfDay(for: at(29)), "The stamp moves to the new day's midnight")
        check(tuesday.hasPlan && tuesday.weekVolumeKg == 21000 && tuesday.sessionsThisWeek == 3,
              "Same week: the plan flag and the week's totals are not touched")
        check(tuesday.streak == 4, "Trained yesterday, so the streak survives")
    }

    static func restDayClearsToday() {
        let wednesday = mondaySnapshot().asOf(at(30), calendar: calendar)
        check(wednesday.todayTitle == nil && wednesday.todayIsRotation == nil,
              "A weekday the routine has no session on reads as a rest day")
        check(wednesday.todayExerciseCount == 0 && wednesday.todaySetCount == 0 && wednesday.todayMuscles.isEmpty,
              "A rest day carries no counts or muscles from the day before")
        check(!wednesday.hasSessionToday, "hasSessionToday follows the title")
        check(wednesday.streak == 0, "Last trained Monday, two days back: the streak has lapsed")
    }

    static func finishedTodayDoesNotOutliveTheDay() {
        check(mondaySnapshot().asOf(at(29), calendar: calendar).finishedToday == nil,
              "Yesterday's finished workout must not be shown as today's")
    }

    static func weekRollsOverOnlyWhenANewWeekBegins() {
        let sunday = mondaySnapshot().asOf(at(4, 10, month: 10), calendar: calendar)
        check(sunday.sessionsThisWeek == 0 && sunday.weekVolumeKg == 0,
              "A new week starts its count and volume from nothing")
        check(sunday.weekStart == calendar.startOfDay(for: at(4, 10, month: 10)),
              "weekStart moves to the new week's first day")
        let saturday = mondaySnapshot().asOf(at(3, 10, month: 10), calendar: calendar)
        check(saturday.sessionsThisWeek == 3 && saturday.weekVolumeKg == 21000,
              "The last day of the week still counts it")
        var noWeek = mondaySnapshot()
        noWeek.weekStart = nil
        check(noWeek.asOf(at(4, 10, month: 10), calendar: calendar).sessionsThisWeek == 3,
              "Without a week stamp the count cannot be judged and is kept")
    }

    static func aSnapshotWithoutADayIsTakenAtItsWord() {
        var undated = mondaySnapshot()
        undated.day = nil
        check(undated.asOf(at(20, month: 10), calendar: calendar) == undated,
              "An older build's snapshot with no day is returned as written")
    }

    static func aClockBehindTheStampChangesNothing() {
        let snapshot = mondaySnapshot()
        check(snapshot.asOf(at(20), calendar: calendar) == snapshot,
              "A date before the stamp must not roll anything")
    }

    static func staleSessionIsDroppedWhateverTheDay() {
        var snapshot = mondaySnapshot()
        let started = at(28, 8)
        snapshot.session = .init(title: "Push", startedAt: started, completedSets: 3, totalSets: 15,
                                 exercise: "Bench", target: "3 x 5", restEndsAt: nil)
        check(snapshot.asOf(started.addingTimeInterval(12 * 3600), calendar: calendar).session != nil,
              "Exactly the stale limit is still running")
        check(snapshot.asOf(at(28, 21), calendar: calendar).session == nil,
              "Past the limit on the same day the widget stops showing it running")
        check(snapshot.asOf(at(28, 19), calendar: calendar).todayTitle == "Push",
              "Dropping the session does not disturb the rest of the day")
        check(snapshot.asOf(at(29, 9), calendar: calendar).session == nil,
              "A stale session does not survive the day rolling over")
        var overnight = snapshot
        overnight.session?.startedAt = at(28, 23)
        check(overnight.asOf(at(29, 3), calendar: calendar).session != nil,
              "A session still inside the limit runs on past midnight")
    }

    static func oldSnapshotWithoutScheduleKeepsItsTitle() {
        var old = mondaySnapshot()
        old.schedule = nil
        let next = old.asOf(at(29), calendar: calendar)
        check(next.todayTitle == "Push" && next.todayExerciseCount == 5,
              "With no schedule to read, today's fields are left rather than guessed")
        check(next.finishedToday == nil && next.day == calendar.startOfDay(for: at(29)),
              "The day still moves on and the finished card still goes")
    }
}
