import Foundation
import SwiftData
import Observation

/// Answers "what is this exercise loaded in, and what is one step worth?" for
/// every exercise in the app.
///
/// Three layers, in order:
///
/// 1. What the user set on that exercise, if they ever put it right.
/// 2. What its equipment implies — a pin stack moves in bigger jumps than a
///    barbell, whatever unit you're in.
/// 3. The app-wide unit, for everything else.
///
/// Only layer 1 is stored. That's what keeps this invisible: a fresh install
/// with nothing saved still steps a barbell by 2.5 kg and a machine by 5, and
/// switching the app between kilograms and pounds moves every untouched
/// exercise with it.
@Observable
final class LoadScaleBook: @unchecked Sendable {

    static let shared = LoadScaleBook()

    /// Corrections the user has made, by canonical catalog ID.
    ///
    /// Keyed through `ExerciseCatalog.canonicalID(for:)` because a merged
    /// exercise has two spellings in play: the sheet saves under the survivor,
    /// while a plan slot or a set made before the merge still asks with the
    /// losing ID. Keyed raw, each missed the other's correction.
    ///
    /// Held behind a lock, because the book is read from model computed
    /// properties that are not on any actor. The observation hooks are written
    /// by hand for the same reason: the macro's own storage cannot be locked.
    private(set) var overrides: [String: LoadScale] {
        get {
            access(keyPath: \.overrides)
            return lock.withLock { storedOverrides }
        }
        set {
            withMutation(keyPath: \.overrides) {
                lock.withLock { storedOverrides = newValue }
            }
        }
    }

    @ObservationIgnored private let lock = NSLock()
    @ObservationIgnored private var storedOverrides: [String: LoadScale] = [:]

    /// Its own context: these rows are read from everywhere — the logger, the
    /// watch bridge, a progression suggestion — and belong to no one screen.
    ///
    /// Unisolated for the same reason `ExerciseCatalog` is: a scale is asked for
    /// in the middle of drawing a row and in the middle of building a watch
    /// mirror, and an `await` at every one of those would be noise. Everything
    /// that writes runs on the main thread — there is no other caller.
    @ObservationIgnored private var context: ModelContext?

    private init() {}

    // MARK: - Lifecycle

    func configure(container: ModelContainer) {
        let context = ModelContext(container)
        self.context = context
        reload()
    }

    /// Rows stored under a losing ID are read in place rather than rewritten
    /// here. A correction saved between the 16th and the 19th of September, or
    /// one brought back by a restore, then counts at once, and nothing in the
    /// store changes until the user sets or clears that exercise. A migration
    /// run on load would have to be re-run after every restore and after every
    /// merge added later, and would write to the store on a path that only
    /// reads.
    func reload() {
        guard let context,
              let rows = try? context.fetch(FetchDescriptor<ExerciseLoadPreference>())
        else { return }
        var newest: [String: ExerciseLoadPreference] = [:]
        for row in rows {
            let key = Self.key(row.catalogID)
            if let held = newest[key], !Self.supersedes(row, held, under: key) { continue }
            newest[key] = row
        }
        overrides = newest.mapValues(\.scale)
    }

    // MARK: - Reading

    /// The scale in force for an exercise.
    func scale(for catalogID: String) -> LoadScale {
        overrides[Self.key(catalogID)] ?? Self.derived(for: ExerciseCatalog.shared.exercise(id: catalogID))
    }

    func scale(for exercise: CatalogExercise?) -> LoadScale {
        guard let exercise else { return Self.derived(for: nil) }
        return overrides[Self.key(exercise.id)] ?? Self.derived(for: exercise)
    }

    /// Whether the user has corrected this exercise themselves.
    func isCustomised(_ catalogID: String) -> Bool { overrides[Self.key(catalogID)] != nil }

    /// Corrected exercises, named and sorted, for the settings list.
    var customised: [(exercise: CatalogExercise, scale: LoadScale)] {
        overrides
            .compactMap { id, scale in
                ExerciseCatalog.shared.exercise(id: id).map { ($0, scale) }
            }
            .sorted { $0.0.name < $1.0.name }
    }

    // MARK: - Writing

    /// Saves under the survivor and drops any row kept under a losing ID, so
    /// the store ends up with one row per movement once the user touches it,
    /// and an older spelling can't outlive the correction that replaced it.
    func set(_ scale: LoadScale, for catalogID: String) {
        let key = Self.key(catalogID)
        overrides[key] = scale
        guard let context else { return }
        let rows = storedRows(for: key, in: context)
        let kept = rows.first { $0.catalogID == key }
        for row in rows where row !== kept { context.delete(row) }
        if let kept {
            kept.scale = scale
        } else {
            context.insert(ExerciseLoadPreference(catalogID: key, scale: scale))
        }
        try? context.save()
    }

    /// Hands an exercise back to its equipment default.
    ///
    /// Deletes every spelling. Settings clears by the survivor's ID, and a
    /// row left under the losing ID would keep the correction in force with no
    /// way to reach it.
    func clear(_ catalogID: String) {
        let key = Self.key(catalogID)
        overrides[key] = nil
        guard let context else { return }
        for row in storedRows(for: key, in: context) { context.delete(row) }
        try? context.save()
    }

    func clearAll() {
        overrides = [:]
        guard let context,
              let rows = try? context.fetch(FetchDescriptor<ExerciseLoadPreference>())
        else { return }
        for row in rows { context.delete(row) }
        try? context.save()
    }

    // MARK: - Merged IDs

    private static func key(_ catalogID: String) -> String {
        ExerciseCatalog.canonicalID(for: catalogID)
    }

    /// Every stored row for one movement, whichever spelling it was saved under.
    private func storedRows(for key: String, in context: ModelContext) -> [ExerciseLoadPreference] {
        let rows = (try? context.fetch(FetchDescriptor<ExerciseLoadPreference>())) ?? []
        return rows.filter { Self.key($0.catalogID) == key }
    }

    /// Whether `row` should win over `held` when both spell the same movement.
    /// The newer one is what the user last said. On an exact tie the row under
    /// the survivor wins, because every save since the merge has gone there.
    private static func supersedes(_ row: ExerciseLoadPreference, _ held: ExerciseLoadPreference,
                                   under key: String) -> Bool {
        if row.updatedAt != held.updatedAt { return row.updatedAt > held.updatedAt }
        return row.catalogID == key
    }

    // MARK: - Defaults

    /// What an exercise is loaded in when nobody has said otherwise: the
    /// app-wide unit, stepping by whatever its equipment can actually do.
    static func derived(for exercise: CatalogExercise?, unit: WeightUnit? = nil) -> LoadScale {
        let unit = unit ?? AppSettings.shared.weightUnit
        return LoadScale(unit: unit, increment: defaultIncrement(for: exercise, in: unit))
    }

    /// Equipment in the order it's consulted. Most specific first: a cable
    /// crossover is a stack, not a barbell, even when the catalog lists a bench
    /// alongside it.
    static let equipmentPriority = ["Machine", "Cable", "Kettlebell", "Dumbbell", "Barbell", "Plate", "Band"]

    /// The smallest jump an exercise's equipment allows.
    static func defaultIncrement(for exercise: CatalogExercise?, in unit: WeightUnit) -> Double {
        let equipment = Set(exercise?.equipment ?? [])
        let match = equipmentPriority.first { equipment.contains($0) }
        return increment(for: match ?? "", in: unit)
    }

    /// What one pin or one pair of plates is worth on a given kind of kit.
    ///
    /// Pin-selected stacks are the coarse ones and the reason this exists: a
    /// machine that only does 5 kg steps should never be offered 62.5. Free
    /// weights are limited by the smallest pair of plates or by the next
    /// dumbbell on the rack. Pound gyms get their own ladder rather than a
    /// conversion of the metric one — nobody's stack is marked 5.5 lb.
    static func increment(for equipment: String, in unit: WeightUnit) -> Double {
        switch equipment {
        case "Machine": unit == .kg ? 5 : 10
        case "Cable": unit == .kg ? 2.5 : 5
        case "Kettlebell": unit == .kg ? 4 : 5
        case "Dumbbell": unit == .kg ? 2 : 5
        case "Barbell": unit == .kg ? 2.5 : 5
        case "Plate": unit == .kg ? 1.25 : 2.5
        case "Band": unit == .kg ? 1 : 2.5
        // Bodyweight work that takes added weight — a belt, a vest, a plate
        // held to the chest — moves in whatever you can hang off it.
        default: unit == .kg ? 1.25 : 2.5
        }
    }
}

// MARK: - Reaching the scale from the things that have a weight

extension CatalogExercise {
    /// How this exercise is loaded — its own correction, or its equipment's.
    var loadScale: LoadScale { LoadScaleBook.shared.scale(for: self) }
}

extension PlanItem {
    var loadScale: LoadScale { LoadScaleBook.shared.scale(for: catalogID) }
}

extension SetLog {
    var loadScale: LoadScale { LoadScaleBook.shared.scale(for: catalogID) }

    /// This set's weight as the machine in front of you reads it.
    var weightLabel: String { loadScale.format(weightKg) }
}
