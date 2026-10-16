import SwiftUI

// How the coach screens put a decision and a moment into words. Kept
// apart from the views so the review screen and the Settings history say the
// same thing the same way.

extension CoachDecision {

    /// The changes whose edits went into the plan. Counted from the record
    /// rather than from what the lifter tapped, because a change accepted and
    /// then found out of date during the apply is stored as stale.
    var appliedCount: Int { changes.filter { $0.decision == .accepted }.count }

    /// One line for what this decision did to the plan.
    var headline: String {
        if changes.isEmpty { return "Advice read" }
        guard appliedAt != nil else { return "Nothing was changed" }
        if revertedAt != nil { return "Applied \(appliedCount), then reverted" }
        return appliedCount == 1 ? "Applied 1 change" : "Applied \(appliedCount) changes"
    }

    /// "2 accepted · 1 declined", leaving out whatever is zero.
    var breakdown: String {
        if changes.isEmpty { return "No plan changes" }
        let counts: [(Int, String)] = [
            (changes.filter { $0.decision == .accepted }.count, "accepted"),
            (changes.filter { $0.decision == .declined }.count, "declined"),
            (changes.filter { $0.decision == .stale }.count, "out of date"),
        ]
        return counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
    }
}

extension CoachChangeDecision.Outcome {
    var label: String {
        switch self {
        case .accepted: "Accepted"
        case .declined: "Declined"
        case .stale: "Out of date"
        }
    }

    var tint: Color {
        switch self {
        case .accepted: Theme.accent
        case .declined: Theme.textSecondary
        case .stale: Theme.warning
        }
    }
}

enum CoachWording {

    /// "Sat, Oct 3 at 6:02 PM" in the lifter's own locale.
    static func moment(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }

    /// "Sat, Oct 3", for a proposal's age where the hour adds nothing.
    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }
}

extension CoachDayNote {

    /// Which workout the note is about, as Today's line and the note's header
    /// name it: "today's workout", "yesterday's workout", "Friday's workout"
    /// within the week, and "your last workout" beyond it, where a weekday
    /// alone would point at the wrong week.
    func workoutName(now: Date = .now, calendar: Calendar = .current) -> String {
        guard let start = dayStart(calendar: calendar) else { return "your last workout" }
        let today = TrainingDay.key(for: now, calendar: calendar)
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: today).day ?? 0
        switch days {
        case 0: return "today's workout"
        case 1: return "yesterday's workout"
        case 2...6:
            var weekday = Date.FormatStyle.dateTime.weekday(.wide)
            weekday.calendar = calendar
            weekday.timeZone = calendar.timeZone
            weekday.locale = calendar.locale ?? .autoupdatingCurrent
            return start.formatted(weekday) + "'s workout"
        default: return "your last workout"
        }
    }
}
