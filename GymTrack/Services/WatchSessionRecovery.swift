import Foundation
import SwiftData

/// Removes empty sessions left by a repeated watch start before the phone
/// checked whether it was already holding a workout.
@MainActor
enum WatchSessionRecovery {
    /// How far back from a candidate's start a finished workout can begin and
    /// still be read as covering it. A session left open is retired at twelve
    /// hours, so nothing longer is a workout; the margin is double that.
    private static let overlapLookback: TimeInterval = 2 * WorkoutSession.staleAfter

    /// - Parameter sessions: the sessions to check. A list of open sessions
    ///   alone is enough: the finished ones that could cover a candidate are
    ///   fetched here, and only when there is a candidate, so a caller need
    ///   not read the whole history to ask.
    static func discardUntouchedOverlaps(_ sessions: [WorkoutSession], in context: ModelContext) -> [WorkoutSession] {
        let candidates = sessions.filter(isUntouched)
        guard !candidates.isEmpty else { return sessions }

        var finished = sessions.compactMap { session -> (Date, Date)? in
            guard let end = session.endedAt else { return nil }
            return (session.startedAt, end)
        }
        let earliest = candidates.map(\.startedAt).min()!.addingTimeInterval(-overlapLookback)
        let latest = candidates.map(\.startedAt).max()!
        let window = FetchDescriptor<WorkoutSession>(predicate: #Predicate {
            $0.endedAt != nil && $0.startedAt >= earliest && $0.startedAt <= latest
        })
        for session in (try? context.fetch(window)) ?? [] {
            if let end = session.endedAt { finished.append((session.startedAt, end)) }
        }
        let orphans = candidates.filter { session in
            // The rejected duplicate was never marked watch-driven: its
            // factory inserted it, then the presentation guard returned
            // before setting that flag. Overlap with a finished workout is
            // the evidence that it could not have been a valid new session.
            finished.contains { interval in
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

    /// An open session with nothing in it: no set logged or started, no note.
    private static func isUntouched(_ session: WorkoutSession) -> Bool {
        session.isActive
            && session.completedSets.isEmpty
            && session.notes.isEmpty && session.noteTagsRaw.isEmpty
            && session.exerciseNotes.isEmpty
            && session.sets.allSatisfy { $0.startedAt == nil }
    }
}
