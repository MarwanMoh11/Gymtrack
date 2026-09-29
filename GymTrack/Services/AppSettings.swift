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
    /// One-shot marker for the cleanup that removed sets logged as warm-ups
    /// back when the app had them.
    static let didDropWarmupSets = "settings.didDropWarmupSets"

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

/// When the phone is kept from locking.
///
/// The setting used to be applied the moment it was read, at launch and on
/// every toggle, so a phone left open on Progress or Today never locked: the
/// battery drained and the last screen stayed readable on an unlocked phone.
/// The preference is only half the answer. The screen is held awake for a
/// lifter who is mid-workout and looking at the app, and for nobody else.
enum ScreenAwakeRules {
    /// Whether `isIdleTimerDisabled` should be on right now. `workoutOpen` is a
    /// session that has begun and not been finished or discarded, whether or
    /// not its logger is expanded: putting the logger away to look at the plan
    /// does not end the workout. `appIsActive` is false in the background and
    /// while the app is inactive (Control Center, an incoming call), where the
    /// system's own timer should apply.
    static func holdsScreenAwake(setting: Bool, workoutOpen: Bool, appIsActive: Bool) -> Bool {
        setting && workoutOpen && appIsActive
    }
}

/// App-wide preferences. Backed by `UserDefaults` so views can read them with
/// `@AppStorage` and non-view code can read them statically.
@Observable
final class AppSettings {
    /// `nonisolated(unsafe)` because the compiler cannot see why this is safe.
    /// Every write is on the main actor (Settings, onboarding, a backup
    /// restore). The readers that are not, the model's rest fallback, the
    /// stats and the Health gates, take one flag or number at a time and act on
    /// it once, so a read racing a toggle sees the old value or the new one and
    /// the lifter who flipped it a moment ago cannot tell which. Isolating the
    /// type to the main actor would put `await` into the pure model and stats
    /// code for nothing.
    nonisolated(unsafe) static let shared = AppSettings()

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
    /// Only the preference. Whether the screen is actually held awake is
    /// `ScreenAwakeRules`' decision, made by `RootView` where the workout and
    /// the scene are both known; applying it here would hold the phone awake
    /// on Progress or Today for as long as the app was open.
    var keepScreenAwake: Bool {
        didSet { defaults.set(keepScreenAwake, forKey: SettingsKey.keepScreenAwake) }
    }
    var userName: String {
        didSet { defaults.set(userName, forKey: SettingsKey.userName) }
    }
    /// Ask how each set felt, and let the answer steer the progression. The
    /// question rides on the rest bar and never blocks the next set, so leaving
    /// it unanswered costs nothing — which is what makes it safe to have on by
    /// default.
    ///
    /// The key keeps its old `trackRPE` name so that turning the question off
    /// once still means off after this rename.
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
