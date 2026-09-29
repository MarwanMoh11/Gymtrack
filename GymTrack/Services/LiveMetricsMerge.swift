import Foundation

extension WatchWorkoutMetrics {
    /// What `current` becomes once `incoming` is folded in, or `nil` when
    /// nothing would change.
    ///
    /// `WatchBridge` is observable, and assigning to an observable property
    /// notifies its readers whether or not the value moved. The wrist resends
    /// a reading that hasn't changed, and every resend put the header, and
    /// whatever else reads the metrics, through a pass to draw the same number.
    /// The caller assigns only a non-nil answer. It has to be an assignment: an
    /// `inout` access to an observable property notifies just the same.
    ///
    /// A first payload for a session that holds nothing yet is a change even
    /// when every field in it is empty, because the phone reads the metrics
    /// being present at all as "the watch is recording".
    static func merged(_ incoming: WatchWorkoutMetrics,
                       into current: WatchWorkoutMetrics?) -> WatchWorkoutMetrics? {
        let result = (current ?? .empty).merging(incoming)
        return result == current ? nil : result
    }
}
