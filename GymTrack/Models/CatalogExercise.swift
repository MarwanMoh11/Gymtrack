import Foundation
import SwiftData

/// How an exercise is measured. Derived from the catalog's `defaultUnit` plus
/// its equipment — the original data only carried a unit, which meant push-ups
/// and bench press were logged identically.
enum TrackingMode: String, Codable, CaseIterable, Sendable {
    case weightReps     // barbell/dumbbell/machine work
    case bodyweightReps // pull-ups, push-ups (optional added weight)
    case duration       // planks, stretches, cardio holds

    var logsWeight: Bool { self == .weightReps }
    var logsReps: Bool { self != .duration }

    /// The rep range a new plan slot starts on, as `DayEditorView.add` writes
    /// it. A timed slot has none.
    var newSlotRepRange: ClosedRange<Int>? { logsReps ? 8...12 : nil }

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
///
/// Not main-actor isolated: it is asked from model computed properties and
/// from pure statistics functions that have no actor to hop to, and an `await`
/// at each of those would be noise. What is written after launch lives in
/// `State`, behind one lock, so the `Sendable` claim is true rather than
/// merely made. Every read takes one snapshot of it, which also keeps a search
/// from seeing the index of one edit and the custom list of another.
final class ExerciseCatalog: @unchecked Sendable {
    static let shared = ExerciseCatalog()

    /// Bundled, read-only exercises.
    let builtIn: [CatalogExercise]

    /// Everything that changes after launch.
    private struct State {
        var index: [String: CatalogExercise] = [:]
        /// Prepared search text per exercise, rebuilt with the index rather
        /// than recomputed for 400+ entries on every keystroke.
        var searchIndex: [String: ExerciseSearch.Entry] = [:]
        /// Custom exercises injected by the store at launch and after edits.
        var custom: [CatalogExercise] = []
        /// Exercises the user has put away. They stay fully resolvable — a
        /// plan or a logged set that names one still reads correctly — they
        /// just stop turning up when browsing or searching.
        var hidden: Set<String> = []

        mutating func rebuildIndex(builtIn: [CatalogExercise]) {
            let everything = builtIn + custom
            index = Dictionary(everything.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
            searchIndex = Dictionary(
                everything.map { ($0.id, ExerciseSearch.Entry(exercise: $0)) },
                uniquingKeysWith: { _, new in new }
            )
        }
    }

    private let lock = NSLock()
    /// Guarded by `lock`; read through `snapshot()`.
    private var state = State()

    private var snapshot: State { lock.withLock { state } }

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

    /// The identity used when comparing logged sets. Old rows keep the ID
    /// they were logged with, while the survivor owns their shared history.
    static func canonicalID(for id: String) -> String { merges[id] ?? id }

    private init() {
        let bundled = Self.loadBundled()
        builtIn = bundled
        state.rebuildIndex(builtIn: bundled)
    }

    /// Everything the app knows about, including what the user has hidden.
    var all: [CatalogExercise] { builtIn + snapshot.custom }

    /// What browsing and searching draw from.
    var visible: [CatalogExercise] { visible(in: snapshot) }

    private func visible(in state: State) -> [CatalogExercise] {
        (builtIn + state.custom).filter { !state.hidden.contains($0.id) }
    }

    func setCustom(_ exercises: [CatalogExercise]) {
        lock.withLock {
            state.custom = exercises
            state.rebuildIndex(builtIn: builtIn)
        }
    }

    func setHidden(_ ids: Set<String>) {
        lock.withLock { state.hidden = ids }
    }

    /// The IDs the user has put away.
    var hidden: Set<String> { snapshot.hidden }

    func isHidden(_ id: String) -> Bool { snapshot.hidden.contains(id) }

    /// The exercise for an ID, following a merge if that ID was one of the
    /// duplicates. Never filters by hidden: an ID that's stored somewhere has
    /// to keep resolving, or the thing that stored it loses its name.
    func exercise(id: String) -> CatalogExercise? {
        let index = lock.withLock { state.index }
        return index[Self.canonicalID(for: id)] ?? index[id]
    }

    /// The exercises the user has put away, named and sorted, for the screen
    /// that offers them back.
    var hiddenExercises: [CatalogExercise] {
        let state = snapshot
        return state.hidden.compactMap { state.index[$0] }.sorted { $0.name < $1.name }
    }

    /// Matches against name, muscles and equipment — see `ExerciseSearch` for
    /// what counts as a match and how results are ordered.
    func search(_ query: String,
                muscle: Muscle? = nil,
                equipment: String? = nil,
                includeHidden: Bool = false) -> [CatalogExercise] {
        let q = ExerciseSearch.Query(query)
        let state = snapshot
        let pool = includeHidden ? builtIn + state.custom : visible(in: state)

        return pool
            .compactMap { ex -> (CatalogExercise, Int)? in
                if let muscle, !ex.muscles.contains(muscle) { return nil }
                if let equipment {
                    let hasEquipment = equipment == "Bodyweight"
                        ? (ex.equipment.isEmpty || ex.equipment.contains("None"))
                        : ex.equipment.contains(equipment)
                    if !hasEquipment { return nil }
                }
                guard let entry = state.searchIndex[ex.id],
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
        let state = snapshot
        return visible(in: state).contains { ex in
            state.searchIndex[ex.id].flatMap { ExerciseSearch.score(entry: $0, query: q) } != nil
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
                tracking: trackingMode(id: r.id, unit: r.defaultUnit, equipment: r.equipment ?? [])
            )
        }
    }

    /// Library entries whose load is real but sits in equipment the file
    /// only calls "Other": the vest and the roller are the weight.
    private static let loadedWithoutListedEquipment: Set<String> = [
        "walking-lunge-weighted-vest",
        "wrist-roller",
    ]

    /// Anything without loadable equipment is measured as bodyweight, whatever
    /// its category. Chest Dip and Hyper-Extension are filed under "strength",
    /// and reading that as weight × reps opened them at 0 kg, from which the
    /// progression climbed to a 1.25 kg dip nobody had done. Bodyweight still
    /// takes added weight, so a belt costs nothing; a load that was never
    /// there, logged mid-set with one tap, costs the record its honesty.
    private static func trackingMode(id: String, unit: String, equipment: [String]) -> TrackingMode {
        if unit == "s" || unit == "min" { return .duration }
        let loadable: Set<String> = ["Barbell", "Dumbbell", "Machine", "Cable", "Kettlebell", "Plate", "Band"]
        if equipment.contains(where: loadable.contains) { return .weightReps }
        if loadedWithoutListedEquipment.contains(id) { return .weightReps }
        return .bodyweightReps
    }
}

extension ExerciseCatalog {
    /// Reads what the store holds about the library into the catalog: the
    /// user's own exercises, and the ones they have put away.
    ///
    /// Launch runs this before the watch link comes up. iOS wakes a terminated
    /// app in the background to hand it a watch message, and no view runs then,
    /// so nothing else would have loaded the custom exercises. A workout
    /// started from the wrist would find its custom slots unresolvable, fall
    /// back to weight × reps, and record a timed hold as 0 kg for some reps.
    func loadLibrary(from context: ModelContext) {
        let custom = (try? context.fetch(FetchDescriptor<CustomExerciseRecord>())) ?? []
        setCustom(custom.map(\.asCatalogExercise))
        let hidden = (try? context.fetch(FetchDescriptor<HiddenExerciseRecord>())) ?? []
        setHidden(Set(hidden.map(\.catalogID)))
    }
}

extension CatalogExercise {
    /// What a new plan slot for this exercise keeps as its own record of how
    /// it is measured, read only when the catalog cannot resolve the slot.
    ///
    /// Custom exercises only. They resolve once the store has been read into
    /// the catalog, and a slot that misses without a snapshot reads a timed
    /// hold as weight × reps. Bundled exercises always resolve.
    var slotTrackingSnapshot: String? { isCustom ? tracking.rawValue : nil }
}

extension ModelContext {
    /// Moves a custom exercise's plan slots onto the tracking it has just
    /// been given.
    ///
    /// The snapshot is only read when the catalog lookup misses, which is
    /// exactly when a stale one would build a workout in the measurement the
    /// exercise no longer uses. Slots without one follow the catalog already.
    ///
    /// A slot added while the exercise was timed holds a 0–0 rep range. Once
    /// it counts reps, that opens every set at zero reps, and the progression
    /// has nothing to climb through. Such a slot gets the range a new slot
    /// starts on. A range the lifter set is theirs and stays.
    func retrackPlanSlots(of catalogID: String, to tracking: TrackingMode) throws {
        let items = try fetch(FetchDescriptor<PlanItem>(
            predicate: #Predicate { $0.catalogID == catalogID }))
        for item in items {
            if item.trackingRaw != nil {
                item.trackingRaw = tracking.rawValue
            }
            if let range = tracking.newSlotRepRange, item.targetRepsHigh < 1 {
                item.targetRepsLow = range.lowerBound
                item.targetRepsHigh = range.upperBound
            }
        }
    }
}
