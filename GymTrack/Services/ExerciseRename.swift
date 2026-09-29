import Foundation
import SwiftData

/// What a custom exercise's edits do to the plan slots that use it.
///
/// This used to sit inside `ExerciseEditorView.save()`, where nothing but a
/// simulator could reach it.
enum ExerciseRename {
    /// Puts `name` on each slot and returns how many actually changed.
    ///
    /// A blank name is refused. Slots copy their name into every session built
    /// from them, and one that reads "" would be a workout with an unlabelled
    /// exercise. The editor trims and checks before it gets here; this keeps
    /// the rule from depending on the caller.
    @discardableResult
    static func apply(_ name: String, to items: [PlanItem]) -> Int {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        var changed = 0
        for item in items where item.name != name {
            item.name = name
            changed += 1
        }
        return changed
    }
}

extension ModelContext {
    /// Carries a custom exercise's new name onto its plan slots, so a session
    /// started from the plan tomorrow shows it.
    ///
    /// Only slots. Past set logs keep the name the exercise had when they were
    /// performed, because that is what was written on the day; rewriting them
    /// would present a name nobody typed then as though it had been.
    @discardableResult
    func renamePlanSlots(of catalogID: String, to name: String) throws -> Int {
        let items = try fetch(FetchDescriptor<PlanItem>(
            predicate: #Predicate { $0.catalogID == catalogID }))
        return ExerciseRename.apply(name, to: items)
    }

    /// Gives every plan slot of a custom exercise a record of how the exercise
    /// is measured, when it has none. Returns how many were stamped.
    ///
    /// The record is read only when the catalog can't resolve the slot, which
    /// is the moment the exercise has gone: deleted from the library, or a
    /// restore that never brought it back. A slot with no record then falls
    /// back to weight × reps, and a timed hold opens a workout at 0 kg for some
    /// reps. Only new slots and the editor's own delete stamped one, so slots
    /// from older versions, and exercises that vanish some other way, were
    /// unprotected. Run whenever the custom exercises are read, this closes
    /// that without waiting for a path to notice.
    ///
    /// Stamping the current measurement is not an inference: a slot follows
    /// the catalog for as long as the exercise exists, so this is what it
    /// already reads.
    @discardableResult
    func snapshotCustomSlotTracking(of exercises: [CatalogExercise]) throws -> Int {
        var tracking: [String: TrackingMode] = [:]
        for exercise in exercises where exercise.isCustom { tracking[exercise.id] = exercise.tracking }
        guard !tracking.isEmpty else { return 0 }
        let unstamped = try fetch(FetchDescriptor<PlanItem>(
            predicate: #Predicate { $0.trackingRaw == nil }))
        var stamped = 0
        for item in unstamped {
            guard let mode = tracking[item.catalogID] else { continue }
            item.trackingRaw = mode.rawValue
            stamped += 1
        }
        if stamped > 0 { try save() }
        return stamped
    }
}
