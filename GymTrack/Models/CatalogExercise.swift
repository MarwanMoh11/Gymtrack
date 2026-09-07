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

    /// Custom exercises injected by the store at launch and after edits.
    private var custom: [CatalogExercise] = []

    private init() {
        builtIn = Self.loadBundled()
        rebuildIndex()
    }

    var all: [CatalogExercise] { builtIn + custom }

    func setCustom(_ exercises: [CatalogExercise]) {
        custom = exercises
        rebuildIndex()
    }

    func exercise(id: String) -> CatalogExercise? { index[id] }

    /// Full-text-ish search across name, muscles and equipment.
    func search(_ query: String, muscle: Muscle? = nil, equipment: String? = nil) -> [CatalogExercise] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { ex in
            if let muscle, !ex.muscles.contains(muscle) { return false }
            if let equipment {
                let hasEquipment = equipment == "Bodyweight"
                    ? (ex.equipment.isEmpty || ex.equipment.contains("None"))
                    : ex.equipment.contains(equipment)
                if !hasEquipment { return false }
            }
            guard !q.isEmpty else { return true }
            if ex.name.lowercased().contains(q) { return true }
            if ex.muscleGroups.contains(where: { $0.lowercased().contains(q) }) { return true }
            if ex.equipment.contains(where: { $0.lowercased().contains(q) }) { return true }
            return false
        }
        .sorted { lhs, rhs in
            // Prefix matches on the name float to the top of a search.
            guard !q.isEmpty else { return lhs.name < rhs.name }
            let l = lhs.name.lowercased().hasPrefix(q)
            let r = rhs.name.lowercased().hasPrefix(q)
            if l != r { return l }
            return lhs.name < rhs.name
        }
    }

    /// Equipment filter options, most common first.
    var equipmentOptions: [String] {
        var counts: [String: Int] = [:]
        for ex in all {
            for e in ex.equipment {
                counts[e, default: 0] += 1
            }
        }
        return ["Bodyweight"] + counts.sorted { $0.value > $1.value }.map(\.key)
    }

    private func rebuildIndex() {
        index = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
    }

    private static func loadBundled() -> [CatalogExercise] {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([RawCatalogExercise].self, from: data)
        else {
            assertionFailure("exercises.json missing from the app bundle")
            return []
        }

        return raw.map { r in
            CatalogExercise(
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
