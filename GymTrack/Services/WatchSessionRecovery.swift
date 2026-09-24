import Foundation
import SwiftData

/// Removes empty sessions left by a repeated watch start before the phone
/// checked whether it was already holding a workout.
@MainActor
enum WatchSessionRecovery {
    static func discardUntouchedOverlaps(_ sessions: [WorkoutSession], in context: ModelContext) -> [WorkoutSession] {
        let finished = sessions.compactMap { session -> (Date, Date)? in
            guard let end = session.endedAt else { return nil }
            return (session.startedAt, end)
        }
        let orphans = sessions.filter { session in
            // The rejected duplicate was never marked watch-driven: its
            // factory inserted it, then the presentation guard returned
            // before setting that flag. Overlap with a finished workout is
            // the evidence that it could not have been a valid new session.
            guard session.isActive,
                  session.completedSets.isEmpty,
                  session.notes.isEmpty, session.noteTagsRaw.isEmpty,
                  session.exerciseNotes.isEmpty,
                  session.sets.allSatisfy({ $0.startedAt == nil })
            else { return false }
            return finished.contains { interval in
                session.startedAt >= interval.0 && session.startedAt < interval.1
            }
        }
        guard !orphans.isEmpty else { return sessions }

        let orphanIDs = Set(orphans.map(\.id))
        for orphan in orphans { context.delete(orphan) }
        do {
            try context.save()
        } catch {
            assertionFailure("An empty overlapping watch session couldn't be removed: \(error)")
            return sessions
        }
        return sessions.filter { !orphanIDs.contains($0.id) }
    }
}
