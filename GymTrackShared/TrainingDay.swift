import Foundation

/// The day a moment counts for in training: its calendar day, except that the
/// small hours before `cutoffHour` still belong to the night before.
///
/// Training late is still "tonight" to the lifter. Keyed at midnight, a
/// Wednesday-night session that started at 00:30 was Thursday's: the streak
/// read Wednesday as missed, Today offered Thursday's day at 00:30, and then
/// called Thursday done all day and hid its workout until Friday.
///
/// Every reader that buckets sessions by day or asks which day "today" is goes
/// through `key(for:calendar:)`: the phone, the widgets and the watch. A reader
/// left on midnight would disagree with the rest about which day a session
/// belongs to. Nothing is stored differently; only the reading changes.
enum TrainingDay {

    /// The wall-clock hour a new training day begins.
    static let cutoffHour = 4

    /// The start of the calendar day `date` counts for: that day's start, or
    /// the day before's when `date` falls before `cutoffHour`. These are the
    /// same keys `Calendar.startOfDay` gives, so a day key compares, steps and
    /// is labelled as it always was. Pass a moment, not a key: a key is the
    /// small hours of its day, and reads as the night before.
    ///
    /// The wall-clock hour is compared, rather than four hours being taken
    /// off. Cairo springs forward at midnight in late April, so that day starts
    /// at 01:00, and its 04:30 is only three and a half hours in: four hours
    /// earlier is the day before.
    static func key(for date: Date, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        guard calendar.component(.hour, from: date) < cutoffHour else { return day }
        // Stepped back from midday, which is inside the day however long it
        // is, as `TrainingStats.startOfDay(_:from:calendar:)` steps. That one
        // isn't compiled into the widgets or the watch.
        let midday = day.addingTimeInterval(12 * 60 * 60)
        let dayBefore = calendar.date(byAdding: .day, value: -1, to: midday) ?? midday
        return calendar.startOfDay(for: dayBefore)
    }
}
