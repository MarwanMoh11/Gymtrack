import Foundation

/// Fixed dates and calendars for tests.
///
/// The app reads `Calendar.current` and the wall clock in places, and a test
/// that leaned on either would pass or fail depending on the runner's time zone
/// and the day it ran. Every date a test asserts on comes from here instead.
enum TestClock {
    /// Gregorian, UTC, weeks starting Monday, POSIX locale.
    static let calendar: Calendar = calendar(in: "UTC")

    /// A Wednesday at noon UTC, clear of month ends and daylight-saving changes.
    static let reference = at("2026-03-11T12:00:00")

    static func calendar(in zone: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: zone)!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// A wall-clock time in the given zone, written `yyyy-MM-dd'T'HH:mm:ss`.
    static func at(_ stamp: String, in zone: String = "UTC") -> Date {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: zone)!
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        guard let date = formatter.date(from: stamp) else {
            preconditionFailure("Unreadable test date \(stamp)")
        }
        return date
    }

    /// A `UserDefaults` of its own, emptied first, for code that takes one.
    static func freshDefaults(_ name: String = #function) -> UserDefaults {
        let suite = "GymTrackTests.\(name)"
        UserDefaults().removePersistentDomain(forName: suite)
        return UserDefaults(suiteName: suite)!
    }
}
