import Testing
import Foundation
import SwiftData
@testable import GymTrack

/// Protects one answer per movement from `LoadScaleBook`, whichever spelling of
/// a merged exercise asks and whichever was stored.
///
/// Four bundled exercises were folded into survivors on 2026-09-19, but plan
/// slots and logged sets keep the losing ID they were made with, and a
/// correction saved between the 16th and the 19th sits under a losing ID too.
/// The sheet always saves under the survivor. Without these, a machine put
/// right in Settings would step on the wrong ladder in the logger.
///
/// Each test points the shared book at a store of its own, and leaves it on an
/// empty one: it has no way back to unconfigured, and an empty store reads the
/// same, nothing corrected.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct LoadScaleMergeTests {

    private let pounds5 = LoadScale(unit: .lb, increment: 5)
    private let pounds2 = LoadScale(unit: .lb, increment: 2.5)
    private let kilos3 = LoadScale(unit: .kg, increment: 3)
    private let bench = "barbell-bench-press"

    /// The book on a fresh store, in kilograms, so the defaults below are the
    /// metric ones whatever the host's unit.
    private func withBook(_ body: (LoadScaleBook, ModelContainer) throws -> Void) throws {
        let book = LoadScaleBook.shared
        let savedUnit = AppSettings.shared.weightUnit
        let container = try TestStore.container()
        let empty = try TestStore.context().container
        defer {
            book.clearAll()
            book.configure(container: empty)
            AppSettings.shared.weightUnit = savedUnit
        }
        AppSettings.shared.weightUnit = .kg
        book.configure(container: container)
        try #require(book.overrides.isEmpty)
        try body(book, container)
    }

    private func derived(_ id: String) -> LoadScale {
        LoadScaleBook.derived(for: ExerciseCatalog.shared.exercise(id: id))
    }

    private func storedIDs(in container: ModelContainer) throws -> [String] {
        try ModelContext(container).fetch(FetchDescriptor<ExerciseLoadPreference>()).map(\.catalogID).sorted()
    }

    /// A row as a build from before the merge, or a restored backup, left it.
    private func storeLegacy(_ row: ExerciseLoadPreference, in container: ModelContainer) throws {
        let legacy = ModelContext(container)
        legacy.insert(row)
        try legacy.save()
    }

    /// The corrections every test below starts from: the bench under its own
    /// ID, the pullover saved under its survivor, a leg extension stored under
    /// its losing ID, and a scaption written through its losing ID.
    private func correct(_ book: LoadScaleBook, in container: ModelContainer) throws {
        book.set(pounds2, for: bench)
        book.set(pounds5, for: "dumbbell-pullover")
        try storeLegacy(ExerciseLoadPreference(catalogID: "single-leg-leg-extension", scale: pounds5), in: container)
        book.reload()
        book.set(kilos3, for: "scaption-dumbbell")
    }

    @Test func everyCorrectionHereDiffersFromItsDefault() throws {
        try withBook { _, _ in
            // Otherwise a correction that was lost would pass unseen.
            #expect(derived("dumbbell-pullover") != pounds5)
            #expect(derived("unilateral-leg-extension") != pounds5)
            #expect(derived("scaption") != kilos3)
        }
    }

    @Test func aCorrectionSavedUnderTheSurvivorReachesEveryMergedSpelling() throws {
        try withBook { book, container in
            try correct(book, in: container)
            #expect(book.scale(for: "dumbbell-pullover-chest") == pounds5)
            // The caption on a merged-ID slot shows the correction as the user's.
            #expect(book.isCustomised("dumbbell-pullover-chest"))
            let oldSlot = PlanItem(catalogID: "dumbbell-pullover-chest", name: "Dumbbell Chest Pullover", order: 0)
            #expect(oldSlot.loadScale == pounds5, "A plan slot made before the merge steps on the corrected ladder")
            let oldSet = SetLog(catalogID: "dumbbell-pullover-chest", exerciseName: "Dumbbell Chest Pullover",
                                exerciseOrder: 0, setIndex: 0)
            #expect(oldSet.loadScale == pounds5, "A set logged under the merged ID reads the corrected scale")
        }
    }

    @Test func aCorrectionStoredUnderAMergedIDReachesTheSurvivor() throws {
        try withBook { book, container in
            try correct(book, in: container)
            #expect(book.scale(for: "unilateral-leg-extension") == pounds5)
            // The sheet reads through the survivor's exercise.
            #expect(book.scale(for: ExerciseCatalog.shared.exercise(id: "unilateral-leg-extension")) == pounds5)
            #expect(book.scale(for: "single-leg-leg-extension") == pounds5)
            #expect(book.scale(for: "scaption") == kilos3)
            // A write lands under the survivor, so the store converges on one spelling.
            #expect(try storedIDs(in: container).filter { $0.hasPrefix("scaption") } == ["scaption"])
        }
    }

    @Test func settingsListEachCorrectedMovementOnceUnderItsSurvivor() throws {
        try withBook { book, container in
            try correct(book, in: container)
            let listed = book.customised.map(\.exercise.id)
            #expect(listed.sorted() == [bench, "dumbbell-pullover", "scaption", "unilateral-leg-extension"].sorted())
            #expect(Set(listed).count == listed.count)

            // Two rows for one movement: the newer one is what the user last said.
            let older = ExerciseLoadPreference(catalogID: "dumbbell-pullover-chest", scale: kilos3)
            older.updatedAt = .distantPast
            try storeLegacy(older, in: container)
            book.reload()
            #expect(book.scale(for: "dumbbell-pullover-chest") == pounds5)
            let both = book.customised.map(\.exercise.id)
            #expect(Set(both).count == both.count, "Both spellings stored still list as one row: \(both)")
        }
    }

    /// Settings clears by the survivor's ID, and a row left under the losing ID
    /// would keep the correction in force with no way to reach it.
    @Test func clearingEitherSpellingRemovesTheCorrectionFromMemoryAndTheStore() throws {
        try withBook { book, container in
            try correct(book, in: container)
            let older = ExerciseLoadPreference(catalogID: "dumbbell-pullover-chest", scale: kilos3)
            older.updatedAt = .distantPast
            try storeLegacy(older, in: container)
            book.reload()

            book.clear("unilateral-leg-extension")
            #expect(!book.isCustomised("single-leg-leg-extension"))
            #expect(book.scale(for: "single-leg-leg-extension") == derived("unilateral-leg-extension"))
            book.clear("dumbbell-pullover-chest")
            #expect(!book.isCustomised("dumbbell-pullover"))
            book.clear("scaption")
            #expect(try storedIDs(in: container) == [bench])
            book.reload()
            #expect(book.scale(for: "dumbbell-pullover") == derived("dumbbell-pullover"),
                    "A cleared correction must not come back from the store")
            #expect(book.scale(for: "single-leg-leg-extension") == derived("unilateral-leg-extension"))
            #expect(!book.customised.contains { $0.exercise.id != bench })

            // An unrelated correction survives its neighbours being cleared, and
            // a merged pair nobody corrected stays on its default.
            #expect(book.scale(for: bench) == pounds2)
            #expect(book.isCustomised(bench))
            #expect(!book.isCustomised("banded-bicep-curl"))
            #expect(!book.isCustomised("bicep-curl-band"))
        }
    }
}
