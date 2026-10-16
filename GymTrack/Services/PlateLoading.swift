import Foundation

/// Where the plate calculator meets the catalog and the settings: which bar,
/// if any, sits under an exercise's load. The arithmetic lives in `PlateMath`.
enum PlateLoading {

    /// The empty bar's weight in the exercise's own display unit, or nil when
    /// the exercise is not loaded on a plain bar, so nothing is drawn for it.
    static func bar(for exercise: CatalogExercise?, scale: LoadScale,
                    preset: BarWeight = AppSettings.shared.barWeight) -> Double? {
        guard let exercise,
              PlateMath.usesPlainBar(catalogID: exercise.id, equipment: exercise.equipment)
        else { return nil }
        return preset.weight(in: scale.unit)
    }

    static func bar(forCatalogID id: String, scale: LoadScale,
                    preset: BarWeight = AppSettings.shared.barWeight) -> Double? {
        bar(for: ExerciseCatalog.shared.exercise(id: id), scale: scale, preset: preset)
    }
}
