import Foundation
import SwiftUI

enum SettingsKey {
    static let weightUnit = "settings.weightUnit"
    static let haptics = "settings.haptics"
    static let restTimerAutoStart = "settings.restTimerAutoStart"
    static let restTimerSound = "settings.restTimerSound"
    static let defaultRestSeconds = "settings.defaultRestSeconds"
    static let keepScreenAwake = "settings.keepScreenAwake"
    static let hasSeeded = "settings.hasSeeded"
    static let hasOnboarded = "settings.hasOnboarded"
    static let userName = "settings.userName"
    static let activeSessionID = "settings.activeSessionID"
    /// Whether the user tucked the running session away rather than closing it.
    static let sessionMinimised = "settings.sessionMinimised"
    /// One-shot marker for the migration that turned per-exercise rest into a
    /// real override rather than a copy of the default.
    static let didClearBakedRest = "settings.didClearBakedRest"
}

enum WeightUnit: String, CaseIterable, Identifiable {
    case kg, lb
    var id: String { rawValue }
    var label: String { self == .kg ? "Kilograms" : "Pounds" }
    var short: String { rawValue }

    /// Smallest sensible increment when stepping a weight in this unit.
    var step: Double { self == .kg ? 2.5 : 5 }

    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * 2.20462262 }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value / 2.20462262 }
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

    private init() {
        defaults.register(defaults: [
            SettingsKey.weightUnit: WeightUnit.kg.rawValue,
            SettingsKey.haptics: true,
            SettingsKey.restTimerAutoStart: true,
            SettingsKey.defaultRestSeconds: 90,
            SettingsKey.keepScreenAwake: true,
        ])
        weightUnit = WeightUnit(rawValue: defaults.string(forKey: SettingsKey.weightUnit) ?? "kg") ?? .kg
        hapticsEnabled = defaults.bool(forKey: SettingsKey.haptics)
        restTimerAutoStart = defaults.bool(forKey: SettingsKey.restTimerAutoStart)
        defaultRestSeconds = defaults.integer(forKey: SettingsKey.defaultRestSeconds)
        keepScreenAwake = defaults.bool(forKey: SettingsKey.keepScreenAwake)
        userName = defaults.string(forKey: SettingsKey.userName) ?? ""
    }

    // MARK: - Formatting helpers

    /// Formats a stored kilogram value in the user's chosen unit.
    func weight(_ kg: Double, showUnit: Bool = true, decimals: Int? = nil) -> String {
        let value = weightUnit.fromKg(kg)
        let places = decimals ?? (value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)
        let number = String(format: "%.\(places)f", value)
        return showUnit ? "\(number) \(weightUnit.short)" : number
    }

    /// Rounds a display-unit value to a clean increment.
    func snap(_ displayValue: Double) -> Double {
        let step = weightUnit == .kg ? 0.5 : 1.0
        return (displayValue / step).rounded() * step
    }
}

extension Double {
    /// Compact volume label — 12,400 kg becomes "12.4k".
    var compactVolume: String {
        if self >= 1000 { return String(format: "%.1fk", self / 1000) }
        return String(format: "%.0f", self)
    }
}

extension TimeInterval {
    /// mm:ss, or h:mm:ss past an hour.
    var clockString: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1h 12m" / "48m" — for summaries rather than live counters.
    var durationString: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }
}
