import Foundation

/// How far through a rest a moment falls, which is what the Dynamic Island's
/// ring is drawn from.
///
/// Held apart from `WorkoutActivity`, which only exists on iOS behind
/// ActivityKit, so the arithmetic can be checked on its own. It is worth
/// checking: the first version measured time since the rest *ends* rather than
/// since it began, so through the whole of a rest — when its end is still in
/// the future — the answer clamped to zero and the ring sat full whatever the
/// clock said.
enum RestProgress {

    /// 0 when the rest has just begun, 1 once it has run out. A rest that
    /// began after `now` reads as 0 and one that was never any length as done,
    /// so a clock a little out of step with the phone's can't push the ring
    /// outside its track.
    static func fraction(startedAt: Date, endsAt: Date, now: Date = .now) -> Double {
        let total = endsAt.timeIntervalSince(startedAt)
        guard total > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(startedAt) / total))
    }
}
