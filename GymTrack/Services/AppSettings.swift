import Foundation
import SwiftUI

enum SettingsKey {
    static let weightUnit = "settings.weightUnit"
    static let haptics = "settings.haptics"
    static let restTimerAutoStart = "settings.restTimerAutoStart"
    static let restTimerSound = "settings.restTimerSound"
    static let defaultRestSeconds = "settings.defaultRestSeconds"
    static let keepScreenAwake = "settings.keepScreenAwake"
    /// Whether the logger asks how hard a set was once it's logged.
    static let trackRPE = "settings.trackRPE"
    static let hasSeeded = "settings.hasSeeded"
    static let hasOnboarded = "settings.hasOnboarded"
    static let userName = "settings.userName"
    static let activeSessionID = "settings.activeSessionID"
    /// Whether the user tucked the running session away rather than closing it.
    static let sessionMinimised = "settings.sessionMinimised"
    /// One-shot marker for the migration that turned per-exercise rest into a
    /// real override rather than a copy of the default.
    static let didClearBakedRest = "settings.didClearBakedRest"

    // Health
    /// Whether the Health permission sheet has been through at least once.
    static let healthRequested = "settings.healthRequested"
    static let healthWriteWorkouts = "settings.healthWriteWorkouts"
    static let healthReadVitals = "settings.healthReadVitals"
    static let healthBodyWeight = "settings.healthBodyWeight"

    // Watch
    /// Wake the watch app when a session starts on the phone.
    static let watchAutoLaunch = "settings.watchAutoLaunch"
}

/// App-wide preferences. Backed by `UserDefaults` so views can read them with
/// `@AppStorage` and non-view code can read them statically.
@Observable
final class AppSettings {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    var weightUnit: WeightUnit {
        didSet { defaults.set(weightUnit.rawValue, forKey: SettingsKey.weightUnit) }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: SettingsKey.haptics) }
    }
    var restTimerAutoStart: Bool {
        didSet { defaults.set(restTimerAutoStart, forKey: SettingsKey.restTimerAutoStart) }
    }
    var defaultRestSeconds: Int {
        didSet { defaults.set(defaultRestSeconds, forKey: SettingsKey.defaultRestSeconds) }
    }
    var keepScreenAwake: Bool {
        didSet {
            defaults.set(keepScreenAwake, forKey: SettingsKey.keepScreenAwake)
            UIApplication.shared.isIdleTimerDisabled = keepScreenAwake
        }
    }
    var userName: String {
        didSet { defaults.set(userName, forKey: SettingsKey.userName) }
    }
    /// Offer an effort rating after each set, and let it steer the progression.
    /// The strip only ever appears on the set you just logged and never blocks
    /// the next one, so leaving it unanswered costs nothing — which is what
    /// makes it safe to have on by default.
    var trackRPE: Bool {
        didSet { defaults.set(trackRPE, forKey: SettingsKey.trackRPE) }
    }

    // MARK: Health & watch

    /// Save finished sessions to Health as strength-training workouts.
    var healthWriteWorkouts: Bool {
        didSet { defaults.set(healthWriteWorkouts, forKey: SettingsKey.healthWriteWorkouts) }
    }
    /// Read heart rate and active energy back for each session.
    var healthReadVitals: Bool {
        didSet { defaults.set(healthReadVitals, forKey: SettingsKey.healthReadVitals) }
    }
    /// Two-way body weight sync.
    var healthBodyWeight: Bool {
        didSet { defaults.set(healthBodyWeight, forKey: SettingsKey.healthBodyWeight) }
    }
    /// Start the watch app when a workout starts on the phone.
    var watchAutoLaunch: Bool {
        didSet { defaults.set(watchAutoLaunch, forKey: SettingsKey.watchAutoLaunch) }
    }

    /// True once any part of the Health integration is switched on.
    var healthEnabled: Bool { healthWriteWorkouts || healthReadVitals || healthBodyWeight }

    private init() {
        defaults.register(defaults: [
            SettingsKey.weightUnit: WeightUnit.kg.rawValue,
            SettingsKey.haptics: true,
            SettingsKey.restTimerAutoStart: true,
            SettingsKey.defaultRestSeconds: 90,
            SettingsKey.keepScreenAwake: true,
            SettingsKey.trackRPE: true,
            SettingsKey.healthWriteWorkouts: true,
            SettingsKey.healthReadVitals: true,
            SettingsKey.healthBodyWeight: false,
            SettingsKey.watchAutoLaunch: true,
        ])
        weightUnit = WeightUnit(rawValue: defaults.string(forKey: SettingsKey.weightUnit) ?? "kg") ?? .kg
        hapticsEnabled = defaults.bool(forKey: SettingsKey.haptics)
        restTimerAutoStart = defaults.bool(forKey: SettingsKey.restTimerAutoStart)
        defaultRestSeconds = defaults.integer(forKey: SettingsKey.defaultRestSeconds)
        keepScreenAwake = defaults.bool(forKey: SettingsKey.keepScreenAwake)
        trackRPE = defaults.bool(forKey: SettingsKey.trackRPE)
        userName = defaults.string(forKey: SettingsKey.userName) ?? ""
        healthWriteWorkouts = defaults.bool(forKey: SettingsKey.healthWriteWorkouts)
        healthReadVitals = defaults.bool(forKey: SettingsKey.healthReadVitals)
        healthBodyWeight = defaults.bool(forKey: SettingsKey.healthBodyWeight)
        watchAutoLaunch = defaults.bool(forKey: SettingsKey.watchAutoLaunch)
    }

    // MARK: - Formatting helpers

    /// Formats a stored kilogram value in the user's chosen unit.
    func weight(_ kg: Double, showUnit: Bool = true, decimals: Int? = nil) -> String {
        weightUnit.format(kg, showUnit: showUnit, decimals: decimals)
    }

    /// Rounds a display-unit value to a clean increment.
    func snap(_ displayValue: Double) -> Double {
        weightUnit.snap(displayValue)
    }
}
