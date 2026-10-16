import Foundation

/// What the set opposite this one did last session, small enough to cross the
/// watch link and be worded the same on both screens.
///
/// It is read off a past `SetLog` and stored nowhere: not in the store, not in
/// the backup. The lifter is racing it, so it is the target to beat before the
/// set is logged and the number the gain badge is measured from afterwards.
struct LastSetRecap: Codable, Hashable, Sendable {
    var weightKg: Double
    var reps: Int
    var seconds: Int
    /// How long the set took, only when both its announced start and its log
    /// stamp exist (`SetLog.timeUnderTension`). Absent for a set whose start
    /// nobody announced: a duration worked out from heart-rate data or from the
    /// gap between two logs is a guess, and a guess shown beside the number
    /// being raced would read as a time to beat.
    var measuredSeconds: Int?

    /// "80 × 8", "8 reps" for a bodyweight set, "45s" for a held one, then
    /// " · 42s" for a measured duration. The caller adds the word "last".
    func label(tracking: WatchTracking, scale: LoadScale) -> String {
        if tracking == .duration { return Self.duration(seconds) }
        let work = tracking.logsWeight && weightKg > 0
            ? "\(scale.format(weightKg, showUnit: false)) × \(reps)"
            : "\(reps) reps"
        guard let measuredSeconds, measuredSeconds > 0 else { return work }
        return "\(work) · \(Self.duration(measuredSeconds))"
    }

    /// "42s", "1m 05s": seconds while it fits, minutes after.
    static func duration(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(max(0, seconds))s" }
        return String(format: "%dm %02ds", seconds / 60, seconds % 60)
    }
}

extension WatchExerciseSnapshot {
    /// The "last …" hint under the exercise name for the set being logged: that
    /// set's own counterpart from last session when the phone sent one, the
    /// exercise's best set otherwise (a phone that predates the per-set field,
    /// or a set with no counterpart).
    ///
    /// The fallback is for the wrist only: the phone shows nothing for an
    /// unpaired row, but the wrist has long had this exercise-level line and a
    /// mirror in flight during an update carries nothing else.
    func lastTimeLine(for set: WatchSetSnapshot?, sessionUnit: WeightUnit) -> String? {
        if let recap = set?.lastSession {
            return "last " + recap.label(tracking: tracking, scale: resolvedScale(sessionUnit: sessionUnit))
        }
        return lastTimeLabel.map { "last \($0)" }
    }
}
