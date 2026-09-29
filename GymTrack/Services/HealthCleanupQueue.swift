import Foundation

/// A workout waiting to be removed from Apple Health.
///
/// Three things put one here: a phone fallback the watch's measured workout
/// replaced, a workout that finished writing after its session was deleted,
/// and the workout of a session the user deleted from history. The entry is
/// kept until Health confirms the workout is gone, including across an app
/// restart or a temporary loss of read permission.
struct PendingWorkoutCleanup: Codable, Equatable {
    var workoutID: UUID
    var sessionID: UUID
    /// The workout the session should point at once `workoutID` is gone. It
    /// travels with the entry so a crash between the two writes can be
    /// repaired on the next launch. Absent when the session has no successor,
    /// which is every entry whose session is already deleted; the key is then
    /// not stored at all, and entries written before it was optional still
    /// decode.
    var preferredWorkoutID: UUID?
}

/// The decisions behind the cleanup list, apart from HealthKit so they can be
/// run without a device. `HealthKitService` supplies the storage and the
/// delete; this decides what is queued and what may leave the list.
enum HealthCleanupQueue {

    /// `entry` added to `queue`. A workout is queued once: a later entry for
    /// the same workout replaces the earlier one, since it is the newer
    /// account of what the session should point at.
    static func enqueue(_ entry: PendingWorkoutCleanup,
                        into queue: [PendingWorkoutCleanup]) -> [PendingWorkoutCleanup] {
        var queue = queue
        queue.removeAll { $0.workoutID == entry.workoutID }
        queue.append(entry)
        return queue
    }

    /// What to queue for a workout whose session may be gone, or nil when
    /// the session is still there and owns it.
    ///
    /// A session deleted from history and a late watch workout for a session
    /// that no longer exists are the same case: the workout has no owner, and
    /// left alone it stays in Health with nothing in the app able to find it.
    /// `sessionExists` comes from a fresh fetch, because the instance a caller
    /// holds can look alive after a delete saved through another context. A
    /// restore may have put the same session back, and that one keeps its
    /// workout.
    static func orphaned(workoutID: UUID, sessionID: UUID, sessionExists: Bool) -> PendingWorkoutCleanup? {
        guard !sessionExists else { return nil }
        return PendingWorkoutCleanup(workoutID: workoutID, sessionID: sessionID, preferredWorkoutID: nil)
    }

    /// `queue` after an attempt to delete `workoutID`. Only a workout Health
    /// reports gone leaves the list; a refused or failed delete keeps the
    /// entry for the next attempt.
    static func settle(_ queue: [PendingWorkoutCleanup], workoutID: UUID,
                       gone: Bool) -> [PendingWorkoutCleanup] {
        guard gone else { return queue }
        return queue.filter { $0.workoutID != workoutID }
    }

    /// One pass over the list.
    ///
    /// The list is read again after every delete, because an entry can be
    /// added while Health is answering, and settling from the copy taken at
    /// the start of the pass would write it back over that entry.
    ///
    /// - Parameters:
    ///   - prepare: Points the session at its successor before the old
    ///     workout goes. False keeps the entry and skips the delete, since a
    ///     link that did not reach disk would be left pointing at nothing.
    ///   - linkFailed: Told when `prepare` said no, and true when the entry
    ///     should now leave the list. An entry whose link never succeeds would
    ///     otherwise be tried at every foreground for as long as the app stays
    ///     installed, which is the endless retry the delete side already stops.
    ///     The caller counts the failure, so the entry leaves the list on the
    ///     same cap and shows in the same Settings line as a delete Health
    ///     keeps refusing. The default never gives up, which keeps every caller
    ///     written before it as it was.
    ///   - delete: True when the workout is gone from Health, whether this
    ///     call removed it or it was not there to remove.
    @MainActor
    static func drain(load: () -> [PendingWorkoutCleanup],
                      save: ([PendingWorkoutCleanup]) -> Void,
                      prepare: (PendingWorkoutCleanup) -> Bool,
                      linkFailed: (PendingWorkoutCleanup) -> Bool = { _ in false },
                      delete: (UUID) async -> Bool) async {
        for entry in load() {
            guard prepare(entry) else {
                if linkFailed(entry) {
                    save(settle(load(), workoutID: entry.workoutID, gone: true))
                }
                continue
            }
            let gone = await delete(entry.workoutID)
            save(settle(load(), workoutID: entry.workoutID, gone: gone))
        }
    }
}
