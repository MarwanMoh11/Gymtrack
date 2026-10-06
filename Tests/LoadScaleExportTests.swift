import Foundation
import SwiftData

/// Run with scripts/test-load-scale-export.sh; no simulator is needed.
///
/// The store can hold a machine correction under a merged, losing ID next to
/// one under the survivor: saved before the merge, or brought back by a
/// restore. The logger reads one answer per movement through `LoadScaleBook`,
/// and the backup, which is written for a coach to read, has to give that same
/// one answer, under the ID the rest of the file uses for the movement.
@main
struct LoadScaleExportTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let base = Date(timeIntervalSince1970: 1_780_000_000)

        func store(_ id: String, _ scale: LoadScale, at offset: TimeInterval) {
            let row = ExerciseLoadPreference(catalogID: id, scale: scale)
            row.updatedAt = base.addingTimeInterval(offset)
            context.insert(row)
        }
        // The survivor saved after the losing ID: the survivor's answer.
        store("dumbbell-pullover-chest", LoadScale(unit: .lb, increment: 5), at: 100)
        store("dumbbell-pullover", LoadScale(unit: .kg, increment: 2), at: 200)
        // The losing ID saved after the survivor: its answer, under the survivor.
        store("unilateral-leg-extension", LoadScale(unit: .kg, increment: 5), at: 300)
        store("single-leg-leg-extension", LoadScale(unit: .lb, increment: 10), at: 400)
        // Only ever saved under the losing ID.
        store("scaption-dumbbell", LoadScale(unit: .lb, increment: 2.5), at: 500)
        // Saved in the same instant: the survivor's row, as the book decides.
        store("bicep-curl-band", LoadScale(unit: .lb, increment: 1), at: 600)
        store("banded-bicep-curl", LoadScale(unit: .kg, increment: 1.5), at: 600)
        // Nothing merged about it.
        store("barbell-bench-press", LoadScale(unit: .lb, increment: 5), at: 700)
        try context.save()

        let url = try BackupService.export(context: context)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let archive = try decoder.decode(BackupService.Archive.self, from: Data(contentsOf: url))
        let scales = archive.loadScales ?? []

        check(archive.version == 2, "The backup version must stay 2")
        let ids = scales.map(\.catalogID)
        check(ids.count == Set(ids).count, "One movement must have one correction in the file, got \(ids)")
        check(ids.allSatisfy { ExerciseCatalog.canonicalID(for: $0) == $0 },
              "Every correction must be written under the survivor's ID, got \(ids)")
        check(ids == ids.sorted(), "Corrections must be written in a stable order, got \(ids)")

        func exported(_ id: String) -> (unit: String, increment: Double)? {
            scales.first { $0.catalogID == id }.map { ($0.unit, $0.increment) }
        }
        func expect(_ id: String, _ unit: WeightUnit, _ increment: Double, _ why: String) {
            let found = exported(id)
            check(found?.unit == unit.rawValue && found?.increment == increment,
                  "\(why): expected \(unit.rawValue) \(increment) under \(id), got \(String(describing: found))")
        }
        expect("dumbbell-pullover", .kg, 2, "The newer survivor row must win")
        expect("unilateral-leg-extension", .lb, 10, "A newer row under the losing ID must win")
        expect("scaption", .lb, 2.5, "A row only under the losing ID must be written under the survivor")
        expect("banded-bicep-curl", .kg, 1.5, "On an exact tie the survivor's row must win")
        expect("barbell-bench-press", .lb, 5, "An unmerged correction must be written as stored")
        check(scales.count == 5, "Five movements were corrected, got \(scales.count) entries")

        // The book, which the logger reads, gives the same answers.
        let book = LoadScaleBook.shared
        book.configure(container: container)
        for dto in scales {
            let scale = book.scale(for: dto.catalogID)
            check(scale.unit.rawValue == dto.unit && scale.increment == dto.increment,
                  "The file and the logger must agree about \(dto.catalogID)")
        }

        guard failures == 0 else {
            print("\(failures) load scale export check(s) failed")
            exit(1)
        }
        print("Load scale export tests passed")
    }
}
