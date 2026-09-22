import SwiftUI

/// How a set felt, in the four words people actually use about a set.
///
/// The question used to be five numbers — 6, 7, 8, 9, 10 — which mean nothing
/// unless you're already carrying the RPE scale in your head, and mid-set
/// nobody is. These are four rungs of that same scale wearing their meaning on
/// the outside. The raw value is still what gets stored, so the progression
/// reads exactly the numbers it always read.
enum SetFeel: Double, CaseIterable, Identifiable, Sendable {
    case easy = 6
    case solid = 8
    case hard = 9
    case allOut = 10

    var id: Double { rawValue }

    /// The word on the button.
    var label: String {
        switch self {
        case .easy: "Easy"
        case .solid: "Solid"
        case .hard: "Hard"
        case .allOut: "All out"
        }
    }

    /// What the word means, in reps — the part the numbers never said out loud.
    var detail: String {
        switch self {
        case .easy: "3+ left"
        case .solid: "2 left"
        case .hard: "1 left"
        case .allOut: "nothing left"
        }
    }

    /// Spelled out for VoiceOver, where there's room for the whole sentence.
    var spokenDetail: String {
        switch self {
        case .easy: "Three or more reps left"
        case .solid: "About two reps left"
        case .hard: "One rep left"
        case .allOut: "Nothing left in the tank"
        }
    }

    /// Green where there's room, red at the limit — the same reading the
    /// progression makes of the answer.
    var tint: Color {
        switch self {
        case .easy: Theme.positive
        case .solid: Theme.accent
        case .hard: Theme.warning
        case .allOut: Theme.negative
        }
    }

    /// The nearest word to a rating already on record. Sets rated 7 or 8.5 on
    /// the old strip still have to draw as something.
    static func nearest(to value: Double) -> SetFeel {
        allCases.min { abs($0.rawValue - value) < abs($1.rawValue - value) } ?? .solid
    }
}
