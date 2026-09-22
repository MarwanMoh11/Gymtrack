import SwiftUI

/// The five things a lifter actually reports, as taps rather than prose.
///
/// A note is worth most when something can be counted off it. "Left shoulder
/// pinched on set 3" and "shoulder felt off again" are the same fact to a
/// person and two unrelated strings to anything reading a few months of
/// training, so each note carries a tag or two alongside its sentence: the tag
/// is the dimension you can count, the sentence is the part no vocabulary can
/// hold.
///
/// Five, deliberately. Each one leads somewhere different — back off and get it
/// looked at, drop the load or stop the set earlier, stop comparing these
/// numbers to the ones above them, push harder, look at what happened outside
/// the gym. A longer list would split the same report across two tags nobody
/// picks consistently, which is worse than not having the tag at all: a tally
/// you can't trust is read as a tally.
///
/// They are not a scale and don't exclude each other — a set can pinch *and*
/// break down — so they're stored as a list rather than a single choice.
enum NoteTag: String, CaseIterable, Identifiable, Sendable {
    /// Something hurt, in the way that means stop rather than the way that
    /// means hard. The one tag worth acting on the same day.
    case pain
    /// The reps stopped looking like the exercise. Different from a hard set:
    /// effort is how close to failure you were, this is what the failure did to
    /// the movement.
    case formBreakdown
    /// A different machine, bar or bench than usual. Without it a reader sees a
    /// 20 kg drop and calls it a regression.
    case substitution
    /// Moved better than the numbers alone say.
    case feltStrong
    /// Moved worse than the numbers alone say — the sleep, the food, the week.
    case feltFlat

    var id: String { rawValue }

    /// The word on the chip. Short enough that five of them fit across a card.
    var label: String {
        switch self {
        case .pain: "Pain"
        case .formBreakdown: "Form broke"
        case .substitution: "Swapped"
        case .feltStrong: "Strong"
        case .feltFlat: "Flat"
        }
    }

    /// What the chip means, spelled out — for VoiceOver, where there's room for
    /// the whole sentence, and for anywhere the label alone is too terse.
    var detail: String {
        switch self {
        case .pain: "Something hurt"
        case .formBreakdown: "Form broke down"
        case .substitution: "Different machine or exercise than usual"
        case .feltStrong: "Moved better than usual"
        case .feltFlat: "Moved worse than usual"
        }
    }

    /// Red where it hurts, amber where it went wrong, green where it went well
    /// — and a flat day in the colour of nothing in particular, which is what
    /// it was. A swap takes the accent: it's information, not a verdict.
    var tint: Color {
        switch self {
        case .pain: Theme.negative
        case .formBreakdown: Theme.warning
        case .substitution: Theme.accent
        case .feltStrong: Theme.positive
        case .feltFlat: Theme.textSecondary
        }
    }

    /// The tags in a stored list, in the order they're offered rather than the
    /// order they were tapped, so the same two tags always read the same way.
    static func resolve(_ raw: [String]) -> [NoteTag] {
        allCases.filter { raw.contains($0.rawValue) }
    }
}
