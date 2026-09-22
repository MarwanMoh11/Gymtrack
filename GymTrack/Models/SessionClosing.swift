import Foundation
import SwiftData

/// Ending a session, said once.
///
/// A session ends three ways: *Finish* on the phone, *Finish* on the wrist with
/// the phone asleep in a locker, and the phone finding yesterday's session still
/// open when it launches. Only the first used to do the whole job. The wrist's
/// path deleted the sets nobody lifted and stopped there, so a note about an
/// exercise that was never trained outlived it, and a drop row whose set had
/// been taken back went on claiming to continue whichever set now sat above it.
/// The launch path only stamped an end, so a plan's untouched prescription
/// reached the export as a column of sets marked "not completed" rather than as
/// nothing, which is what they were.
///
/// Three paths closing different amounts is how a record ends up half closed,
/// so all three come through here.
extension WorkoutSession {

    /// Drops everything that didn't happen and stamps the end.
    ///
    /// - Parameter moment: when the session ended. Now, for a session somebody
    ///   finished; the last logged set, for one the app is closing on the
    ///   lifter's behalf, which otherwise would report a workout that ran all
    ///   night.
    func close(at moment: Date = .now, in context: ModelContext) {
        // Before the unlogged sets go, because which exercises survive is what
        // decides which notes still have something to be about.
        pruneNotesForClosing(in: context)
        unlinkOrphanedContinuations()
        for set in sets where !set.isCompleted {
            context.delete(set)
        }
        endedAt = moment
    }

    /// What survives the end of the session: a note that says something, about
    /// an exercise that ended up in the record.
    ///
    /// An exercise you logged nothing for is dropped from the session entirely
    /// — that's what `close` does with its sets — so a note left on it would be
    /// the only trace of an exercise the record says you didn't do, and it would
    /// have nowhere to be read back. It goes with the sets.
    private func pruneNotesForClosing(in context: ModelContext) {
        let trained = Set(sets.filter(\.isCompleted).map(\.catalogID))
        for note in exerciseNotes where note.isEmpty || !trained.contains(note.catalogID) {
            context.delete(note)
        }
    }

    /// Cuts the link on any row left continuing a set that won't be in the
    /// record.
    ///
    /// A continuation is always built on top of a set that has already been
    /// logged, so this only comes up one way: the lifter takes that set back
    /// and leaves it taken back. `close` then deletes it as an unlogged set,
    /// and the row underneath would survive as the exercise's first set still
    /// claiming it was taken on without rest from something that, as far as
    /// the record goes, never happened. It is a set on its own now, and the
    /// only honest thing left to say about it is nothing.
    ///
    /// The set it has to keep is the row directly above it — the one
    /// `SetLog.continuedSet` names — not any logged set further up. Asked the
    /// looser question, a drop taken off set 2 survived set 2 being taken back
    /// as long as set 1 was still there, and went into the record as a drop
    /// off set 1: a lift the lifter did, attached to a set it had nothing to
    /// do with.
    private func unlinkOrphanedContinuations() {
        for set in sets where set.isContinuation && set.continuedSet?.isCompleted != true {
            set.continuesPreviousSet = nil
        }
    }
}
