import Foundation
import SwiftUI
import UserNotifications
import AudioToolbox

/// Whether a rest that has just been found over still earns the chime.
///
/// The end is announced twice on the phone: by the end-of-rest timer, if the
/// app is in front, and by the "Rest over" notification, if it is not. A timer
/// that wakes minutes after the end (the app was suspended, and the notification
/// has long since been delivered) used to play the sound and the haptic as
/// well, mid-set, for a rest that had ended before the lifter unlocked the
/// phone.
///
/// The tolerance is short because it only has to cover a timer that runs
/// late in the foreground, which is a matter of milliseconds, so anything
/// later than a couple of seconds means the app was not running at the end and
/// the notification did the announcing. The watch keeps 60 s
/// (`WatchRestRules.lateExpiryTolerance`) because it posts no notification,
/// so for it a tap that is late is still the only announcement.
enum RestChimeRules {
    static let lateTolerance: TimeInterval = 2

    static func chimesOnExpiry(endsAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(endsAt) <= lateTolerance
    }
}

/// The "Rest over" notification, behind a seam so a test can run a real timer
/// in a process that has no app bundle, where the system centre traps.
protocol RestNotifying {
    func schedule(in seconds: Int, id: String)
    func cancel(id: String)
    func requestPermission()
}

/// The real thing: local notifications through `UNUserNotificationCenter`.
struct SystemRestNotifier: RestNotifying {
    func schedule(in seconds: Int, id: String) {
        guard seconds > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = "Rest over"
        content.body = "Next set is up."
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    /// Clears the delivered banner as well as the pending request. A rest that
    /// ended while the phone was locked leaves its "Rest over" on the Lock
    /// Screen, and it is stale the moment the lifter is back in the app.
    func cancel(id: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}

/// Counts down between sets. Driven off an end `Date` rather than a tick count,
/// so backgrounding the app (or locking the phone mid-set) doesn't drift.
///
/// Nothing observable changes between a rest's start and its end. The clock
/// used to be a `remaining` property written four times a second, and every
/// view that read it (the rest bar, the dock, and through them the logger)
/// was drawn again four times a second for the length of the rest, with a
/// minimised session doing dozens of exercise-group rebuilds a second on top.
/// The countdown text and ring now ask `remaining(at:)` from a `TimelineView`
/// of their own, so only those few glyphs are redrawn, and the timer's one job
/// is to fire once at the end. The watch does the same
/// (`WatchRestTimer.expiry`).
@MainActor
@Observable
final class RestTimer {
    private(set) var endsAt: Date?
    /// When the current rest began. The Live Activity needs both ends of the
    /// interval to draw a countdown that runs without the app.
    private(set) var startedAt: Date?
    private(set) var totalSeconds: Int = 0

    /// Not stored, so reading it in a view body does not subscribe the view to
    /// a value that changes every tick; it answers as of the moment it is read.
    var remaining: TimeInterval { remaining(at: .now) }

    func remaining(at moment: Date) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(moment))
    }

    /// Fired whenever the rest state changes in a way the Lock Screen cares
    /// about — started, extended, cancelled, or run out.
    var onChange: (() -> Void)?

    /// A one-shot at the end of the rest, not a ticker.
    @ObservationIgnored private var expiry: Timer?
    private let notificationID = "gymtrack.rest"
    @ObservationIgnored private let notifier: RestNotifying

    /// Nothing is running yet, so a "Rest over" still pending under this id
    /// belongs to a rest that died with the previous process: the OS or a
    /// force-quit ended the app mid-rest, and the rest itself is not stored
    /// anywhere to put back. Left alone, its notification fires at the old end
    /// while the logger shows no rest at all.
    init(notifier: RestNotifying = SystemRestNotifier()) {
        self.notifier = notifier
        cancelNotification()
    }

    var isRunning: Bool { endsAt != nil }

    var progress: Double { progress(at: .now) }

    func progress(at moment: Date) -> Double {
        guard totalSeconds > 0, isRunning else { return 0 }
        return 1 - (remaining(at: moment) / Double(totalSeconds))
    }

    func start(seconds: Int) {
        guard seconds > 0 else { return }
        requestNotificationPermission()
        totalSeconds = seconds
        startedAt = .now
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        arm()
        scheduleNotification(in: seconds)
        onChange?()
    }

    func add(seconds: Int) {
        guard let endsAt else { return }
        let newEnd = endsAt.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > .now else { return stop() }
        self.endsAt = newEnd
        totalSeconds += seconds
        arm()
        cancelNotification()
        scheduleNotification(in: Int(remaining))
        onChange?()
        Haptics.tick()
    }

    /// Puts a rest back where it actually is, rather than starting a fresh one
    /// from now.
    ///
    /// Two callers, and both of them know when the rest began better than this
    /// clock does. A start announced by mis-tap and taken back has to leave the
    /// screen reading as it did a second earlier — a countdown that resumes at
    /// 1:12 when it was stopped at 1:12, not one that begins again at 1:30. And
    /// a set logged on the wrist out of range began its rest when it was
    /// logged, which may have been minutes before the phone heard about it. A
    /// rest whose end has already gone past is simply over, and there is
    /// nothing to put back.
    func restore(endingAt end: Date, totalSeconds total: Int) {
        guard total > 0, end > .now else { return }
        // Asked here as well as in `start`, because a rest that begins with a
        // set logged on the wrist reaches the countdown through this door and
        // never through that one. Without it a lifter who rests by way of the
        // watch would never be asked, and "Rest over" would silently never
        // arrive.
        requestNotificationPermission()
        totalSeconds = total
        startedAt = end.addingTimeInterval(-TimeInterval(total))
        endsAt = end
        arm()
        scheduleNotification(in: Int(remaining.rounded()))
        onChange?()
    }

    func stop() {
        expiry?.invalidate()
        expiry = nil
        let wasRunning = endsAt != nil
        endsAt = nil
        startedAt = nil
        totalSeconds = 0
        cancelNotification()
        if wasRunning { onChange?() }
    }

    /// Sets the timer for the end of the rest. An `add` re-arms it for the
    /// later end.
    private func arm() {
        expiry?.invalidate()
        expiry = nil
        guard let endsAt else { return }
        let timer = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.expireIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }

    /// The timer's own call. Guarded because its hop onto the main actor can
    /// land after an `add` has moved the end further out, and because a timer
    /// can fire a hair before its date, which would otherwise leave a rest
    /// running with nothing left to end it.
    private func expireIfDue() {
        guard let endsAt else { return }
        guard endsAt <= .now else { return arm() }
        finish(endedAt: endsAt)
    }

    private func finish(endedAt end: Date) {
        stop()
        guard RestChimeRules.chimesOnExpiry(endsAt: end, now: .now) else { return }
        Haptics.success()
        AudioServicesPlaySystemSound(1057)   // short, non-intrusive alert
    }

    // MARK: - Notifications

    /// Fires only if the app isn't in the foreground when the rest ends.
    private func scheduleNotification(in seconds: Int) {
        notifier.schedule(in: seconds, id: notificationID)
    }

    private func cancelNotification() {
        notifier.cancel(id: notificationID)
    }

    private func requestNotificationPermission() {
        Self.requestNotificationPermissionIfNeeded(using: notifier)
    }

    /// Asked for the first time a rest actually starts — a permission prompt on
    /// the launch screen, before the user knows what it's for, gets denied.
    private static var hasAskedForPermission = false

    static func requestNotificationPermissionIfNeeded(using notifier: RestNotifying = SystemRestNotifier()) {
        guard !hasAskedForPermission else { return }
        hasAskedForPermission = true
        notifier.requestPermission()
    }
}
