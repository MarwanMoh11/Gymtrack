import UIKit

/// Thin wrapper so haptics can be muted globally from Settings without
/// sprinkling checks through the views.
enum Haptics {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: SettingsKey.haptics) as? Bool ?? true
    }

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notify = UINotificationFeedbackGenerator()

    /// Small tick for steppers and toggles.
    static func tick() {
        guard isEnabled else { return }
        light.impactOccurred(intensity: 0.7)
    }

    /// Confirming a set.
    static func log() {
        guard isEnabled else { return }
        medium.impactOccurred()
    }

    /// Rest timer finished, session finished.
    static func success() {
        guard isEnabled else { return }
        notify.notificationOccurred(.success)
    }

    /// A new personal record.
    static func celebrate() {
        guard isEnabled else { return }
        notify.notificationOccurred(.success)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            rigid.impactOccurred(intensity: 1.0)
        }
    }

    static func warn() {
        guard isEnabled else { return }
        notify.notificationOccurred(.warning)
    }
}
