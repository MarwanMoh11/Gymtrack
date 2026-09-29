import Foundation
import SwiftData

/// Run with scripts/test-load-scale-merges.sh; no simulator is needed.
///
/// Four bundled exercises were folded into survivors on 2026-09-19, but plan
/// slots and logged sets keep the losing ID they were made with, and a
/// correction saved between the 16th and the 19th sits under a losing ID too.
/// The sheet always saves under the survivor. These checks hold the book to
/// one answer per movement, whichever spelling asks and whichever was stored,
/// so a machine that was put right in the logger stays put right there.
@main
struct LoadScaleMergeTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: ExerciseLoadPreference.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let book = LoadScaleBook.shared
        book.configure(container: container)

        let pounds5 = LoadScale(unit: .lb, increment: 5)
        let pounds2 = LoadScale(unit: .lb, increment: 2.5)
        let kilos3 = LoadScale(unit: .kg, increment: 3)
        let bench = "barbell-bench-press"
        book.set(pounds2, for: bench)

        func derived(_ id: String) -> LoadScale {
            LoadScaleBook.derived(for: ExerciseCatalog.shared.exercise(id: id))
        }
        func storedIDs() -> [String] {
            let rows = (try? ModelContext(container).fetch(FetchDescriptor<ExerciseLoadPreference>())) ?? []
            return rows.map(\.catalogID).sorted()
        }
        precondition(derived("dumbbell-pullover") != pounds5
                     && derived("unilateral-leg-extension") != pounds5
                     && derived("scaption") != kilos3,
                     "The corrections must differ from the defaults, or a lost one would pass unseen")

        // 1. Saved under the survivor, as the sheet does, and read through a
        // plan slot or a set that still holds the losing ID.
        book.set(pounds5, for: "dumbbell-pullover")
        check(book.scale(for: "dumbbell-pullover-chest") == pounds5,
              "A lookup by a merged ID must find the survivor's correction")
        check(book.isCustomised("dumbbell-pullover-chest"),
              "The caption on a merged-ID slot must show the correction as the user's")
        let oldSlot = PlanItem(catalogID: "dumbbell-pullover-chest", name: "Dumbbell Chest Pullover", order: 0)
        check(oldSlot.loadScale == pounds5, "A plan slot made before the merge must step on the corrected ladder")
        let oldSet = SetLog(catalogID: "dumbbell-pullover-chest", exerciseName: "Dumbbell Chest Pullover",
                            exerciseOrder: 0, setIndex: 0)
        check(oldSet.loadScale == pounds5, "A set logged under the merged ID must read the corrected scale")

        // 2. Stored under a losing ID, by a build from before the merge or by a
        // restored backup, and read by the survivor.
        let legacy = ModelContext(container)
        legacy.insert(ExerciseLoadPreference(catalogID: "single-leg-leg-extension", scale: pounds5))
        try legacy.save()
        book.reload()
        check(book.scale(for: "unilateral-leg-extension") == pounds5,
              "A correction stored under a merged ID must reach the survivor")
        check(book.scale(for: ExerciseCatalog.shared.exercise(id: "unilateral-leg-extension")) == pounds5,
              "The sheet reads through the survivor's exercise and must find it too")
        check(book.scale(for: "single-leg-leg-extension") == pounds5,
              "The merged ID must still read its own stored correction")
        book.set(kilos3, for: "scaption-dumbbell")
        check(book.scale(for: "scaption") == kilos3, "A correction written under a merged ID must reach the survivor")
        check(storedIDs().filter { $0.hasPrefix("scaption") } == ["scaption"],
              "A write must land under the survivor, so the store converges on one spelling")

        let listed = book.customised.map(\.exercise.id)
        check(listed.sorted() == [bench, "dumbbell-pullover", "scaption", "unilateral-leg-extension"].sorted(),
              "Settings must list each movement once, under the survivor: got \(listed)")
        check(Set(listed).count == listed.count, "Settings rows must not share an ID")

        // Two rows for one movement: the newer one is what the user last said.
        let older = ExerciseLoadPreference(catalogID: "dumbbell-pullover-chest", scale: kilos3)
        older.updatedAt = .distantPast
        legacy.insert(older)
        try legacy.save()
        book.reload()
        check(book.scale(for: "dumbbell-pullover-chest") == pounds5,
              "An older row under the merged ID must not override a newer one under the survivor")
        let both = book.customised.map(\.exercise.id)
        check(Set(both).count == both.count, "Both spellings stored must still list as one Settings row: got \(both)")

        // 3. Clearing either spelling removes the movement's correction, from
        // memory and from the store. Settings clears by the survivor's ID.
        book.clear("unilateral-leg-extension")
        check(!book.isCustomised("single-leg-leg-extension"), "Clearing the survivor must clear a merged-ID row")
        check(book.scale(for: "single-leg-leg-extension") == derived("unilateral-leg-extension"),
              "A cleared merged-ID slot must fall back to its equipment default")
        book.clear("dumbbell-pullover-chest")
        check(!book.isCustomised("dumbbell-pullover"), "Clearing the merged ID must clear the survivor's row")
        book.clear("scaption")
        check(storedIDs() == [bench], "Clearing must delete every stored spelling: left \(storedIDs())")
        book.reload()
        check(book.scale(for: "dumbbell-pullover") == derived("dumbbell-pullover")
              && book.scale(for: "single-leg-leg-extension") == derived("unilateral-leg-extension"),
              "A cleared correction must not come back from the store")
        check(!book.customised.contains { $0.exercise.id != bench }, "Settings must show nothing left to clear")

        // 4. An unrelated exercise is untouched by all of the above.
        check(book.scale(for: bench) == pounds2 && book.isCustomised(bench),
              "An unrelated correction must survive its neighbours being cleared")
        check(!book.isCustomised("banded-bicep-curl") && !book.isCustomised("bicep-curl-band"),
              "A merged pair nobody corrected must stay on its default")

        if failures > 0 {
            print("\(failures) load scale merge check(s) failed")
            exit(1)
        }
        print("Load scale merge checks passed")
    }
}
