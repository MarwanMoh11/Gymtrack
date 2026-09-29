import Foundation
import SwiftData

/// The session summary's record rows, worked out from the sets that could
/// matter rather than from the whole history.
///
/// The summary used to fetch every session and let `recordSets` walk each one's
/// sets, which faults in every set ever logged to answer a question about the
/// handful of exercises in one workout.
enum SummaryRecords {
    /// The IDs a set of these exercises could have been logged under: the
    /// canonical ones and every spelling merged into them. Old rows keep the
    /// ID they were logged with, so asking for the survivor alone would drop
    /// their history.
    static func spellings(of canonicalIDs: Set<String>) -> [String] {
        var ids = canonicalIDs
        for (merged, survivor) in ExerciseCatalog.merges where canonicalIDs.contains(survivor) {
            ids.insert(merged)
        }
        return Array(ids)
    }

    /// The sets of `session` that set a record, as `TrainingStats.summaryRecords`
    /// answers for the whole history, from a fetch of only the completed sets
    /// of the same exercises.
    static func sets(for session: WorkoutSession, in context: ModelContext) throws -> [SetLog] {
        let canonical = Set(session.completedSets.map { ExerciseCatalog.canonicalID(for: $0.catalogID) })
        guard !canonical.isEmpty else { return [] }
        let spellings = spellings(of: canonical)
        let sessionID = session.id
        let fetched = try context.fetch(FetchDescriptor<SetLog>(
            predicate: #Predicate { spellings.contains($0.catalogID) && $0.isCompleted }))

        // Sets with no session are not history: the whole-history walk reached
        // sets only through their sessions and never saw them.
        var earlier: [String: [SetLog]] = [:]
        for set in fetched where !set.isContinuation {
            guard let owner = set.session, owner.id != sessionID else { continue }
            earlier[ExerciseCatalog.canonicalID(for: set.catalogID), default: []].append(set)
        }
        let today = Dictionary(grouping: session.sets) { ExerciseCatalog.canonicalID(for: $0.catalogID) }
        let recordSets = session.completedSets.filter { set in
            let catalogID = ExerciseCatalog.canonicalID(for: set.catalogID)
            return TrainingStats.isPersonalRecord(set, among: (earlier[catalogID] ?? []) + (today[catalogID] ?? []))
        }
        return TrainingStats.summaryRecords(from: recordSets)
    }
}
