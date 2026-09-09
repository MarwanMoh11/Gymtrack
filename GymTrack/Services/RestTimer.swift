import Foundation
import SwiftUI
import UserNotifications
import AudioToolbox

/// Counts down between sets. Driven off an end `Date` rather than a tick count,
/// so backgrounding the app (or locking the phone mid-set) doesn't drift.
@Observable
final class RestTimer {
    private(set) var endsAt: Date?
    /// When the current rest began. The Live Activity needs both ends of the
    /// interval to draw a countdown that runs without the app.
    private(set) var startedAt: Date?
    private(set) var totalSeconds: Int = 0
    private(set) var remaining: TimeInterval = 0

    /// Fired whenever the rest state changes in a way the Lock Screen cares
    /// about — started, extended, cancelled, or run out.
    var onChange: (() -> Void)?

    private var ticker: Timer?
    private let notificationID = "gymtrack.rest"

    var isRunning: Bool { endsAt != nil }

    var progress: Double {
        guard totalSeconds > 0, isRunning else { return 0 }
        return 1 - (remaining / Double(totalSeconds))
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        Self.requestNotificationPermissionIfNeeded()
        totalSeconds = seconds
        startedAt = .now
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        remaining = TimeInterval(seconds)
        scheduleTicker()
        scheduleNotification(in: seconds)
        onChange?()
    }

    func add(seconds: Int) {
        guard let endsAt else { return }
        let newEnd = endsAt.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > .now else { return stop() }
        self.endsAt = newEnd
        totalSeconds += seconds
        refresh()
        cancelNotification()
        scheduleNotification(in: Int(remaining))
        onChange?()
        Haptics.tick()
    }

    func stop() {
        ticker?.invalidate()
        ticker = nil
        let wasRunning = endsAt != nil
        endsAt = nil
        startedAt = nil
        remaining = 0
        totalSeconds = 0
        cancelNotification()
        if wasRunning { onChange?() }
    }

    private func scheduleTicker() {
        ticker?.invalidate()
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    private func refresh() {
        guard let endsAt else { return }
        remaining = max(0, endsAt.timeIntervalSinceNow)
        if remaining <= 0 {
            finish()
        }
    }

    private func finish() {
        stop()
        Haptics.success()
        AudioServicesPlaySystemSound(1057)   // short, non-intrusive alert
    }

    // MARK: - Notifications

    /// Fires only if the app isn't in the foreground when the rest ends.
    private func scheduleNotification(in seconds: Int) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Next set is up."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: notificationID,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func cancelNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [notificationID])
    }

    /// Asked for the first time a rest actually starts — a permission prompt on
    /// the launch screen, before the user knows what it's for, gets denied.
    private static var hasAskedForPermission = false

    static func requestNotificationPermissionIfNeeded() {
        guard !hasAskedForPermission else { return }
        hasAskedForPermission = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
