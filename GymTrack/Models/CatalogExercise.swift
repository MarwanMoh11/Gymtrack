import Foundation

/// How an exercise is measured. Derived from the catalog's `defaultUnit` plus
/// its category — the original data only carried a unit, which meant push-ups
/// and bench press were logged identically.
enum TrackingMode: String, Codable, CaseIterable, Sendable {
    case weightReps     // barbell/dumbbell/machine work
    case bodyweightReps // pull-ups, push-ups (optional added weight)
    case duration       // planks, stretches, cardio holds

    var logsWeight: Bool { self == .weightReps }
    var logsReps: Bool { self != .duration }

    var label: String {
        switch self {
        case .weightReps: "Weight × reps"
        case .bodyweightReps: "Bodyweight reps"
        case .duration: "Duration"
        }
    }
}

/// A read-only exercise definition from the bundled library (or a user's own
/// custom exercise, projected into the same shape).
struct CatalogExercise: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let category: String
    let muscleGroups: [String]
    let equipment: [String]
    let details: String?
    let difficulty: String?
    let tracking: TrackingMode
    var isCustom: Bool = false

    /// The muscle this exercise is primarily credited to in the heatmap.
    var primaryMuscle: Muscle? { muscleGroups.compactMap(Muscle.match).first }

    /// Canonical muscles, de-duplicated, in listed order.
    var muscles: [Muscle] {
        var seen = Set<Muscle>()
        return muscleGroups.compactMap(Muscle.match).filter { seen.insert($0).inserted }
    }

    /// Short "what it works" line. Falls back to the library's own wording for
    /// the handful of full-body and cardio entries that map to no single group.
    var muscleSummary: String {
        let canonical = muscles.prefix(3).map(\.name)
        if !canonical.isEmpty { return canonical.joined(separator: " · ") }
        return muscleGroups.prefix(2).joined(separator: " · ")
    }

    var equipmentLabel: String {
        equipment.isEmpty || equipment == ["None"] ? "Bodyweight" : equipment.joined(separator: " · ")
    }

    /// SF Symbol used wherever the exercise appears without artwork.
    var symbol: String {
        switch category {
        case "cardio": "figure.run"
        case "mobility": "figure.cooldown"
        case "warmup": "flame"
        case "plyometrics": "figure.jumprope"
        case "core": "figure.core.training"
        case "bodyweight": "figure.strengthtraining.functional"
        default: "dumbbell.fill"
        }
    }
}

// MARK: - JSON decoding of the bundled library

/// The bundled file keeps the original web app's field names.
private struct RawCatalogExercise: Decodable {
    let id: String
    let name: String
    let category: String
    let muscleGroups: [String]
    let equipment: [String]?
    let description: String?
    let difficulty: String?
    let defaultUnit: String
}

/// Loads and indexes `exercises.json` once, then serves lookups.
final class ExerciseCatalog: @unchecked Sendable {
    static let shared = ExerciseCatalog()

    /// Bundled, read-only exercises.
    private(set) var builtIn: [CatalogExercise] = []
    private var index: [String: CatalogExercise] = [:]
    /// Prepared search text per exercise, rebuilt with the index rather than
    /// recomputed for 400+ entries on every keystroke.
    private var searchIndex: [String: ExerciseSearch.Entry] = [:]

    /// Custom exercises injected by the store at launch and after edits.
    private var custom: [CatalogExercise] = []

    /// Exercises the user has put away. They stay fully resolvable — a plan or
    /// a logged set that names one still reads correctly — they just stop
    /// turning up when browsing or searching.
    private(set) var hidden: Set<String> = []

    /// Entries in the bundled file that turned out to be the same movement
    /// written twice, mapped survivor-last.
    ///
    /// The losing ID is *redirected* rather than deleted, because sessions and
    /// plans store whichever ID was picked at the time. Resolving it to the
    /// survivor keeps that history readable and folds both spellings into one
    /// progression chart instead of two half-empty ones.
    static let merges: [String: String] = [
        "scaption-dumbbell": "scaption",                    // "Dumbbell Scaption Raise"
        "bicep-curl-band": "banded-bicep-curl",             // "Band Bicep Curl"
        "single-leg-leg-extension": "unilateral-leg-extension",  // "Single-Leg Extension Machine"
        "dumbbell-pullover-chest": "dumbbell-pullover",     // "Dumbbell Chest Pullover"
    ]

    private init() {
        builtIn = Self.loadBundled()
        rebuildIndex()
    }

    /// Everything the app knows about, including what the user has hidden.
    var all: [CatalogExercise] { builtIn + custom }

    /// What browsing and searching draw from.
    var visible: [CatalogExercise] { all.filter { !hidden.contains($0.id) } }

    func setCustom(_ exercises: [CatalogExercise]) {
        custom = exercises
        rebuildIndex()
    }

    func setHidden(_ ids: Set<String>) {
        hidden = ids
    }

    func isHidden(_ id: String) -> Bool { hidden.contains(id) }

    /// The exercise for an ID, following a merge if that ID was one of the
    /// duplicates. Never filters by hidden: an ID that's stored somewhere has
    /// to keep resolving, or the thing that stored it loses its name.
    func exercise(id: String) -> CatalogExercise? {
        index[Self.merges[id] ?? id] ?? index[id]
    }

    /// The exercises the user has put away, named and sorted, for the screen
    /// that offers them back.
    var hiddenExercises: [CatalogExercise] {
        hidden.compactMap { index[$0] }.sorted { $0.name < $1.name }
    }

    /// Matches against name, muscles and equipment — see `ExerciseSearch` for
    /// what counts as a match and how results are ordered.
    func search(_ query: String,
                muscle: Muscle? = nil,
                equipment: String? = nil,
                includeHidden: Bool = false) -> [CatalogExercise] {
        let q = ExerciseSearch.Query(query)
        let pool = includeHidden ? all : visible

        return pool
            .compactMap { ex -> (CatalogExercise, Int)? in
                if let muscle, !ex.muscles.contains(muscle) { return nil }
                if let equipment {
                    let hasEquipment = equipment == "Bodyweight"
                        ? (ex.equipment.isEmpty || ex.equipment.contains("None"))
                        : ex.equipment.contains(equipment)
                    if !hasEquipment { return nil }
                }
                guard let entry = searchIndex[ex.id],
                      let score = ExerciseSearch.score(entry: entry, query: q)
                else { return nil }
                return (ex, score)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                // Among equally good matches the plainer name is the one people
                // mean — "Seated Cable Row" before "Wide Grip Seated Cable Row".
                // Only when they're actually searching, though: with no query
                // every entry scores the same, and ordering the whole library by
                // name length would just look broken.
                if !q.isEmpty, lhs.0.name.count != rhs.0.name.count {
                    return lhs.0.name.count < rhs.0.name.count
                }
                return lhs.0.name < rhs.0.name
            }
            .map(\.0)
    }

    /// Whether anything at all answers a query — used to offer building the
    /// exercise yourself when the library comes up short.
    func hasMatch(for query: String) -> Bool {
        let q = ExerciseSearch.Query(query)
        guard !q.isEmpty else { return true }
        return visible.contains { ex in
            searchIndex[ex.id].flatMap { ExerciseSearch.score(entry: $0, query: q) } != nil
        }
    }

    /// Whether an exercise by this name already exists, so a custom one isn't
    /// built on top of a library entry the search simply didn't surface.
    func existing(named name: String, excluding id: String? = nil) -> CatalogExercise? {
        let target = ExerciseSearch.normalise(name)
        guard !target.isEmpty else { return nil }
        return all.first { $0.id != id && ExerciseSearch.normalise($0.name) == target }
    }

    /// Equipment filter options, most common first.
    var equipmentOptions: [String] {
        var counts: [String: Int] = [:]
        for ex in visible {
            for e in ex.equipment {
                counts[e, default: 0] += 1
            }
        }
        return ["Bodyweight"] + counts.sorted { $0.value > $1.value }.map(\.key)
    }

    private func rebuildIndex() {
        let everything = all
        index = Dictionary(everything.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        searchIndex = Dictionary(
            everything.map { ($0.id, ExerciseSearch.Entry(exercise: $0)) },
            uniquingKeysWith: { _, new in new }
        )
    }

    private static func loadBundled() -> [CatalogExercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([RawCatalogExercise].self, from: data)
        else {
            assertionFailure("exercises.json missing from the app bundle")
            return []
        }

        // A merged duplicate is dropped from the list entirely — `exercise(id:)`
        // sends its ID to the survivor, so nothing that referenced it breaks.
        return raw.compactMap { r in
            guard merges[r.id] == nil else { return nil }
            return CatalogExercise(
                id: r.id,
                name: r.name,
                category: r.category,
                muscleGroups: r.muscleGroups,
                equipment: (r.equipment ?? []).filter { $0 != "None" && $0 != "Other" },
                details: r.description,
                difficulty: r.difficulty,
                tracking: trackingMode(unit: r.defaultUnit, category: r.category, equipment: r.equipment ?? [])
            )
        }
    }

    private static func trackingMode(unit: String, category: String, equipment: [String]) -> TrackingMode {
        if unit == "s" || unit == "min" { return .duration }
        let loadable: Set<String> = ["Barbell", "Dumbbell", "Machine", "Cable", "Kettlebell", "Plate", "Band"]
        if equipment.contains(where: loadable.contains) { return .weightReps }
        if category == "strength" { return .weightReps }
        return .bodyweightReps
    }
}
