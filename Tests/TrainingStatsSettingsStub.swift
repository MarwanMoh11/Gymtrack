import Foundation

/// Only the preferences and outcome enum required by the model and stats test.
final class AppSettings {
    static let shared = AppSettings()
    var weightUnit: WeightUnit = .kg
    var defaultRestSeconds = 90
}

enum LoadNudgeOutcome: String {
    case taken
    case declined
}
