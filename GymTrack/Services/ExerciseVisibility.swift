import Foundation
import SwiftData

/// Putting library exercises away, and bringing them back.
///
/// The bundled library is deliberately broad — it carries every variation of a
/// movement so that whatever a gym has on the floor is in there somewhere. Most
/// of it is noise for any one person: nobody trains eight kinds of push-up.
/// Hiding is what turns the shipped library into *your* gym, and it's reversible
/// precisely because it isn't deletion — the entry stays resolvable, so a plan
/// or a session that already names one reads exactly as it did before.
enum ExerciseVisibility {

    /// Reads the stored rows into the catalog, which is what actually filters
    /// browsing and search.
    static func sync(from records: [HiddenExerciseRecord]) {
        ExerciseCatalog.shared.setHidden(Set(records.map(\.catalogID)))
    }

    /// Re-reads straight from the store. Used right after a change so the list
    /// updates on the same frame as the tap, ahead of the `@Query` refresh.
    @discardableResult
    static func reload(context: ModelContext) -> [HiddenExerciseRecord] {
        let records = (try? context.fetch(FetchDescriptor<HiddenExerciseRecord>())) ?? []
        sync(from: records)
        return records
    }

    static func hide(_ catalogID: String, context: ModelContext) {
        guard !ExerciseCatalog.shared.isHidden(catalogID) else { return }
        context.insert(HiddenExerciseRecord(catalogID: catalogID))
        try? context.save()
        reload(context: context)
    }

    static func show(_ catalogID: String, context: ModelContext) {
        let records = (try? context.fetch(FetchDescriptor<HiddenExerciseRecord>())) ?? []
        for record in records where record.catalogID == catalogID { context.delete(record) }
        try? context.save()
        reload(context: context)
    }

    static func showAll(context: ModelContext) {
        let records = (try? context.fetch(FetchDescriptor<HiddenExerciseRecord>())) ?? []
        for record in records { context.delete(record) }
        try? context.save()
        reload(context: context)
    }
}
