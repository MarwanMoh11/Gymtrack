import Foundation

/// The daily check's few lines on one workout, written by `coach push-day` on
/// the Mac to `Inbox/daily.json`. A new push replaces the last one; the phone
/// keeps no history of them, since the Mac's notes are the record.
///
/// It changes nothing and asks nothing. Today shows it until a workout on a
/// later training day is finished: its "next time" is about the next session,
/// and once that session is done it is advice about a day already gone. So
/// there is nothing to dismiss, and a note nobody opens costs no taps.
struct CoachDayNote: Codable, Equatable, Sendable {
    static let format = "gymtrack-coach-day"
    static let currentVersion = 1

    var format: String
    var version: Int
    var id: String
    var createdAt: Date
    /// The training day the note is about, `yyyy-MM-dd`, keyed as
    /// `TrainingDay` keys it (before 04:00 is still the night before).
    var day: String
    var verdict: String
    var wentWell: [String]?
    var watch: [String]?
    var nextTime: [String]?

    var wentWellLines: [String] { Self.lines(wentWell) }
    var watchLines: [String] { Self.lines(watch) }
    var nextTimeLines: [String] { Self.lines(nextTime) }

    /// A note this build can show: its own format and version, a verdict, and a
    /// day it can place. Anything else stays unshown rather than half-shown.
    var isReadable: Bool {
        format == Self.format && version == Self.currentVersion
            && !verdict.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && dayStart() != nil
    }

    /// False once a workout has been finished on a training day after the one
    /// the note is about. Pass only sessions that were trained: one closed
    /// with nothing logged is not the next workout.
    func isCurrent(trainedStarts: [Date], calendar: Calendar = .current) -> Bool {
        let formatter = Self.dayFormatter(calendar)
        return !trainedStarts.contains { formatter.string(from: TrainingDay.key(for: $0, calendar: calendar)) > day }
    }

    /// The start of the day the note is about, or nil when `day` is not a date.
    func dayStart(calendar: Calendar = .current) -> Date? {
        Self.dayFormatter(calendar).date(from: day)
    }

    /// Gregorian whatever the lifter's calendar, because the Mac writes the day
    /// that way; the time zone is the lifter's, as `TrainingDay` reads it.
    static func dayFormatter(_ calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    private static func lines(_ list: [String]?) -> [String] {
        (list ?? []).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}
