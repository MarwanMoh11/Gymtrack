import Foundation

/// Run with scripts/test-today-mirror.sh; no simulator is needed.
///
/// Two things the widget and the wrist read about "today" off a mirror the
/// phone wrote earlier. A streak must survive the day Cairo's clocks spring
/// forward at midnight (STATS-01), and a day the plan's rotation chose must be
/// able to say "Next up" through both mirrors without breaking an older phone,
/// watch or widget on the other end (STATS-03).
@main
struct TodayMirrorTests {
    static var failures = 0

    static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static func main() throws {
        streakSurvivesCairoSpringForward()
        rollForwardCarriesTheRotationFlag()
        try idleSnapshotDecodesBothWays()
        try widgetSnapshotDecodesBothWays()

        guard failures == 0 else {
            print("\(failures) today mirror check(s) failed")
            exit(1)
        }
        print("Today mirror tests passed")
    }

    // MARK: STATS-01

    static func streakSurvivesCairoSpringForward() {
        var cairo = Calendar(identifier: .gregorian)
        cairo.timeZone = TimeZone(identifier: "Africa/Cairo")!
        func at(_ day: Int, _ hour: Int) -> Date {
            cairo.date(from: DateComponents(year: 2026, month: 4, day: day, hour: hour))!
        }
        // Egypt springs forward at 00:00 on the last Friday of April, so the
        // 24th begins at 01:00. Without that the check below proves nothing.
        let springDay = cairo.startOfDay(for: at(24, 12))
        precondition(cairo.component(.hour, from: springDay) == 1,
                     "This time zone database has no midnight spring-forward in Cairo on 2026-04-24")

        let thursday = cairo.startOfDay(for: at(23, 12))
        let trainedThursday = GymTrackSnapshot(day: thursday, lastTrainedDay: thursday, streak: 5)

        check(trainedThursday.asOf(at(24, 10), calendar: cairo).streak == 5,
              "A streak trained yesterday must survive the day the clocks spring forward")
        check(trainedThursday.asOf(at(24, 23), calendar: cairo).streak == 5,
              "It must survive all of that day")
        check(trainedThursday.asOf(at(25, 10), calendar: cairo).streak == 0,
              "A streak last trained two days ago must lapse")

        let trainedFriday = GymTrackSnapshot(day: springDay, lastTrainedDay: springDay, streak: 6)
        check(trainedFriday.asOf(at(25, 10), calendar: cairo).streak == 6,
              "A streak trained on the short day must survive the day after it")
    }

    // MARK: STATS-03

    static func rollForwardCarriesTheRotationFlag() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        func day(_ number: Int) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 9, day: number, hour: 9))!
        }
        // Monday the 21st, pinned. Tuesday pinned too; Wednesday carries the
        // rotation's next day.
        let schedule = [
            GymTrackSnapshot.ScheduledDay(weekday: 3, title: "Pull", exerciseCount: 5, setCount: 15,
                                          muscles: [], isRotation: false),
            GymTrackSnapshot.ScheduledDay(weekday: 4, title: "Legs", exerciseCount: 5, setCount: 15,
                                          muscles: [], isRotation: true),
        ]
        let monday = GymTrackSnapshot(day: calendar.startOfDay(for: day(21)), schedule: schedule,
                                      hasPlan: true, todayTitle: "Push", todayIsRotation: false)
        check(monday.asOf(day(22), calendar: calendar).todayIsRotation == false,
              "A pinned weekday rolled forward to must read as today's")
        check(monday.asOf(day(23), calendar: calendar).todayIsRotation == true,
              "A weekday carrying the rotation must read as next up once the widget rolls forward to it")
        check(monday.asOf(day(24), calendar: calendar).todayIsRotation == nil,
              "A rest day has no session to call anything")
    }

    /// `WatchIdleSnapshot` exactly as builds before `todayIsRotation` declared it.
    struct OldWatchIdleSnapshot: Codable {
        var day: Date?
        var todayTitle: String?
        var todayExerciseCount: Int
        var todaySetCount: Int
        var todayMuscles: [String]
        var streak: Int
        var sessionsThisWeek: Int
        var lastSessionTitle: String?
        var lastSessionDate: Date?
        var unit: WeightUnit
    }

    static func idleSnapshotDecodesBothWays() throws {
        var fresh = WatchIdleSnapshot.empty
        fresh.day = Date(timeIntervalSince1970: 1_790_000_000)
        fresh.todayTitle = "Legs"
        fresh.todayExerciseCount = 5
        fresh.todayIsRotation = true

        // New phone, old watch.
        let newData = try JSONEncoder.watchLink.encode(fresh)
        let onOldWatch = try? JSONDecoder.watchLink.decode(OldWatchIdleSnapshot.self, from: newData)
        check(onOldWatch?.todayTitle == "Legs" && onOldWatch?.todayExerciseCount == 5,
              "An older watch must still decode a mirror that carries the rotation flag")

        // Old phone, new watch.
        let old = OldWatchIdleSnapshot(day: fresh.day, todayTitle: "Push", todayExerciseCount: 4,
                                       todaySetCount: 12, todayMuscles: ["Chest"], streak: 3,
                                       sessionsThisWeek: 2, lastSessionTitle: nil, lastSessionDate: nil,
                                       unit: .kg)
        let oldData = try JSONEncoder.watchLink.encode(old)
        let onNewWatch = try? JSONDecoder.watchLink.decode(WatchIdleSnapshot.self, from: oldData)
        check(onNewWatch?.todayTitle == "Push", "A newer watch must still decode an older phone's mirror")
        check(onNewWatch?.todayIsRotation == nil, "An older phone's mirror must read as today's, as before")

        // Round trip, so the flag the phone sends is the flag the wrist reads.
        let roundTrip = try JSONDecoder.watchLink.decode(WatchIdleSnapshot.self, from: newData)
        check(roundTrip == fresh, "The flag must survive the link")
    }

    static func widgetSnapshotDecodesBothWays() throws {
        // The shared container's own coders are private to it; these match
        // them, and the dates are not what is under test.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970

        // A snapshot written by a build before the flag existed.
        let unflagged = GymTrackSnapshot(
            day: Date(timeIntervalSince1970: 1_790_000_000),
            schedule: [GymTrackSnapshot.ScheduledDay(weekday: 2, title: "Push", exerciseCount: 4,
                                                     setCount: 12, muscles: [])],
            hasPlan: true, todayTitle: "Push")
        let oldData = try encoder.encode(unflagged)
        let oldJSON = String(decoding: oldData, as: UTF8.self)
        check(!oldJSON.contains("isRotation") && !oldJSON.contains("todayIsRotation"),
              "A snapshot with no flag must carry no key, just as an older build wrote it")
        let read = try? decoder.decode(GymTrackSnapshot.self, from: oldData)
        check(read?.todayTitle == "Push" && read?.todayIsRotation == nil
              && read?.schedule?.first?.isRotation == nil,
              "An older snapshot must still decode, and read as today's")

        var flagged = unflagged
        flagged.todayIsRotation = true
        flagged.schedule?[0].isRotation = true
        let newData = try encoder.encode(flagged)
        let back = try decoder.decode(GymTrackSnapshot.self, from: newData)
        check(back.todayIsRotation == true && back.schedule?.first?.isRotation == true,
              "The flags the app writes must be the flags the widget reads")
    }
}
