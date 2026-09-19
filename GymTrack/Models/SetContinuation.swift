import SwiftUI

/// What a row did to the row above it, on the rows that were one effort.
///
/// A drop set is not "a set of type drop". It is the set above it taken again
/// without putting the bar down, and the fact worth recording is the link
/// between the rows rather than a label on either of them. 62.5 × 8, 50 × 6,
/// 40 × 5 with the link is one working set extended twice; the same three rows
/// without it is a lifter collapsing across three working sets. Identical
/// numbers, opposite conclusions — and the file this app writes is read by
/// something that only has the numbers.
///
/// So the link is the only thing stored, as `SetLog.continuesPreviousSet`.
/// These two words are read back off the weights every time they're asked for
/// and are never written down anywhere: either the load came down between the
/// rows or it didn't, and that is the whole difference. Storing the word beside
/// the weights would let the two disagree — a lifter who says "drop" and then
/// keeps the load has stated two contradictory things, and in a JSON file the
/// word would be believed over the numbers that actually happened. It is the
/// same reason a load offer stores the rung it named and not the weight it came
/// from: one of them is already on the set.
///
/// Two words, because two is what changes a reading. A drop's lighter rows are
/// work below the working load and shouldn't be counted as sets at it; a
/// cluster's rows are more reps *at* the working load, bought with a pause
/// instead of a reduction. A coach does something different with each.
///
/// Three candidates were left out. **To failure / AMRAP** is already in the
/// record and better said: the effort question's `allOut` means "nothing left",
/// is asked of every set, and doesn't need a set to be a special kind of set to
/// be true of it. A second way to say it would only let the two contradict each
/// other. **Warm-ups** were a flag this app already carried and already dropped
/// — a set is a set, and the weights say which ones were light. And a
/// **superset** is not this: two exercises alternated is two efforts sharing a
/// rest, not one effort spread over several rows, and the app already has a way
/// to say it (`preferredExerciseID`) that doesn't touch any set.
enum SetContinuation: String, Sendable {
    /// The load came down and the set kept going — a drop.
    case drop
    /// The load stayed where it was and only the pause was given — myo-reps,
    /// rest-pause, clusters. The app doesn't try to tell those three apart:
    /// what separates them is how long the pause was and what the lifter
    /// intended, and the pause is already on the record as the gap between the
    /// two rows' stamps. Splitting them by name would be inventing a
    /// distinction out of a number that is already there to be read.
    case cluster

    /// The word on the row.
    var label: String {
        switch self {
        case .drop: "Drop"
        case .cluster: "Cluster"
        }
    }

    /// Said in full for VoiceOver, where there's room for what it means.
    var spoken: String {
        switch self {
        case .drop: "Drop — continued from the set above at a lower weight, without resting"
        case .cluster: "Cluster — continued from the set above at the same weight, without a full rest"
        }
    }

    /// Named on the set that's being worked, where the eyebrow otherwise reads
    /// "SET 2". It changes under the lifter's thumb as they dial the weight,
    /// which is the honest thing for it to do: the word *is* the weight.
    var eyebrow: String { label.uppercased() }

    /// The one glyph both words share. The point being made is that this row
    /// hangs off the one above it, which is the same point either way.
    static let symbol = "arrow.turn.down.right"
}
