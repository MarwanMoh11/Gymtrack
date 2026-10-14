import Foundation
import SwiftData

/// The machine each exercise is done on and how the lifter sets it up,
/// resolved by movement so a merged exercise keeps its setup.
enum MachineSetups {
    static func setup(for catalogID: String, in records: [MachineSetupRecord]) -> MachineSetupRecord? {
        let canonical = ExerciseCatalog.canonicalID(for: catalogID)
        return records.filter { ExerciseCatalog.canonicalID(for: $0.catalogID) == canonical }
            .max { $0.updatedAt < $1.updatedAt }
    }

    static func setup(for catalogID: String, context: ModelContext) -> MachineSetupRecord? {
        setup(for: catalogID, in: (try? context.fetch(FetchDescriptor<MachineSetupRecord>())) ?? [])
    }

    /// Machines this lifter already uses for something, most recent first: the
    /// gym they train at, learnt from what they picked rather than asked for.
    static func usedMachineIDs(in records: [MachineSetupRecord]) -> [String] {
        var seen = Set<String>()
        return records.sorted { $0.updatedAt > $1.updatedAt }
            .compactMap { seen.insert($0.machineID).inserted ? $0.machineID : nil }
    }

    /// Chooses the machine for an exercise. Choosing the one already chosen
    /// keeps its settings; a different machine starts with nothing set, since
    /// a seat position on one machine says nothing about another's.
    static func choose(_ machineID: String, for catalogID: String, context: ModelContext, at moment: Date = .now) {
        let canonical = ExerciseCatalog.canonicalID(for: catalogID)
        if let current = setup(for: canonical, context: context), current.machineID == machineID { return }
        deleteSetups(canonical, context: context)
        context.insert(MachineSetupRecord(catalogID: canonical, machineID: machineID, at: moment))
        try? context.save()
    }

    /// "No machine": the exercise goes back to having no setup at all.
    static func clear(_ catalogID: String, context: ModelContext) {
        deleteSetups(ExerciseCatalog.canonicalID(for: catalogID), context: context)
        try? context.save()
    }

    /// Sets one adjustment, or takes it back when `value` is nil. A value the
    /// machine can't hold is ignored rather than stored.
    static func set(_ adjustmentID: String, to value: Int?, for catalogID: String,
                    context: ModelContext, at moment: Date = .now) {
        guard let record = setup(for: catalogID, context: context) else { return }
        var settings = record.settings
        if let value {
            guard let adjustment = record.rig?.adjustment(adjustmentID), adjustment.range.contains(value) else { return }
            settings.values[adjustmentID] = value
        } else {
            settings.values[adjustmentID] = nil
        }
        record.settingsRaw = settings.raw
        record.updatedAt = moment
        try? context.save()
    }

    private static func deleteSetups(_ canonical: String, context: ModelContext) {
        let records = (try? context.fetch(FetchDescriptor<MachineSetupRecord>())) ?? []
        for record in records where ExerciseCatalog.canonicalID(for: record.catalogID) == canonical {
            context.delete(record)
        }
    }
}
