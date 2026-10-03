import SwiftUI

// How the coach screens put a decision, a rating and a moment into words. Kept
// apart from the views so the review screen and the Settings history say the
// same thing the same way.

extension CoachDecision {

    /// The changes whose edits went into the plan. Counted from the record
    /// rather than from what the lifter tapped, because a change accepted and
    /// then found out of date during the apply is stored as stale.
    var appliedCount: Int { changes.filter { $0.decision == .accepted }.count }

    /// One line for what this decision did to the plan.
    var headline: String {
        guard appliedAt != nil else { return "Nothing was changed" }
        if revertedAt != nil { return "Applied \(appliedCount), then reverted" }
        return appliedCount == 1 ? "Applied 1 change" : "Applied \(appliedCount) changes"
    }

    /// "2 accepted · 1 declined", leaving out whatever is zero.
    var breakdown: String {
        let counts: [(Int, String)] = [
            (changes.filter { $0.decision == .accepted }.count, "accepted"),
            (changes.filter { $0.decision == .declined }.count, "declined"),
            (changes.filter { $0.decision == .stale }.count, "out of date"),
        ]
        return counts.filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }.joined(separator: " · ")
    }
}

extension CoachRating {

    /// Who gave it. A rating from someone else without a name is still not the
    /// lifter's, so it is never labelled as theirs.
    var raterLabel: String {
        switch rater {
        case .user: "You"
        case .other: raterName ?? "Someone else"
        }
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
