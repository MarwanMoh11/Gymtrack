import Foundation

/// Canonical muscle groups. The bundled library uses 42 different free-text
/// labels ("Grip", "Posterior Chain", "Inner Thighs", …); everything is folded
/// into these so the heatmap and filters stay coherent.
enum Muscle: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case chest, shoulders, rearDelts, biceps, triceps, forearms
    case abs, obliques
    case lats, upperBack, traps, lowerBack
    case glutes, quads, hamstrings, calves, adductors

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chest: "Chest"
        case .shoulders: "Shoulders"
        case .rearDelts: "Rear Delts"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .forearms: "Forearms"
        case .abs: "Abs"
        case .obliques: "Obliques"
        case .lats: "Lats"
        case .upperBack: "Upper Back"
        case .traps: "Traps"
        case .lowerBack: "Lower Back"
        case .glutes: "Glutes"
        case .quads: "Quads"
        case .hamstrings: "Hamstrings"
        case .calves: "Calves"
        case .adductors: "Adductors"
        }
    }

    /// Which side of the body map the muscle is drawn on.
    var isAnterior: Bool {
        switch self {
        case .chest, .shoulders, .biceps, .forearms, .abs, .obliques, .quads, .adductors: true
        default: false
        }
    }

    /// Broad region, used to group filters and the weekly volume breakdown.
    var region: Region {
        switch self {
        case .chest, .shoulders, .rearDelts, .biceps, .triceps, .forearms: .upper
        case .lats, .upperBack, .traps, .lowerBack: .back
        case .abs, .obliques: .core
        case .glutes, .quads, .hamstrings, .calves, .adductors: .lower
        }
    }

    enum Region: String, CaseIterable, Identifiable {
        case upper = "Upper Body"
        case back = "Back"
        case core = "Core"
        case lower = "Lower Body"
        var id: String { rawValue }
    }

    /// Recommended weekly hard sets per muscle — the yardstick the progress
    /// screen scores against. Middle of the commonly cited 10–20 set range.
    var weeklySetTarget: Int {
        switch self {
        case .chest, .lats, .quads, .hamstrings, .glutes, .shoulders: 14
        case .upperBack, .biceps, .triceps, .abs: 12
        case .traps, .rearDelts, .calves, .forearms, .obliques, .lowerBack, .adductors: 8
        }
    }

    /// Folds a free-text label from the exercise library into a canonical group.
    static func match(_ label: String) -> Muscle? {
        switch label.lowercased() {
        case "chest", "upper chest", "lower chest", "inner chest", "pectorals", "serratus": .chest
        case "shoulders", "front delts", "side delts", "deltoids", "rotator cuff": .shoulders
        case "rear delts", "posterior deltoids": .rearDelts
        case "biceps", "arms": .biceps
        case "triceps": .triceps
        case "forearms", "grip": .forearms
        case "core", "abs", "lower abs", "abdominals": .abs
        case "obliques": .obliques
        case "lats": .lats
        case "back", "upper back", "mid back", "rhomboids": .upperBack
        case "traps", "lower traps": .traps
        case "lower back", "spine", "erector spinae": .lowerBack
        case "glutes", "hips", "abductors": .glutes
        case "quads", "legs", "hip flexors", "quadriceps": .quads
        case "hamstrings", "posterior chain": .hamstrings
        case "calves": .calves
        case "adductors", "inner thighs": .adductors
        default: nil        // "Full Body", "Cardio", "Upper Body" — no single region
        }
    }
}
