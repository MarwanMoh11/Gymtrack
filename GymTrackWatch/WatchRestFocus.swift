import Foundation
import Observation

/// Brings a rest's countdown back in front of a lifter who has stopped using
/// the watch.
///
/// Logging a set scrolls the logger to the countdown, but only as the rest
/// begins. A lifter who then scrolled down to dial the next weight, or swiped
/// across to their heart rate, and dropped their wrist came back to whatever
/// they had last touched, and had to go looking for the clock in the one
/// moment the screen exists to show it. Once the watch has gone untouched for
/// `idleDelay`, the logger page and its countdown come back.
///
/// This only ever moves the screen. When a rest starts, how long it runs and
/// when it taps the wrist all belong to `WatchRestTimer`, which nothing here
/// writes to.
@MainActor
@Observable
final class WatchRestFocus {

    /// How long the watch goes untouched before the countdown comes back.
    ///
    /// Long enough to read the next set's target, or to glance at the bar and
    /// back, without the screen moving under you. Short enough that a wrist
    /// raised after any real pause finds the clock.
    static let idleDelay: TimeInterval = 8

    /// How often the observed `touchedAt` may move. A scroll reports every
    /// frame it moves, and each change to `touchedAt` restarts the wait that is
    /// keyed on it.
    static let touchGranularity: TimeInterval = 1

    /// The last time the lifter touched the watch, to within
    /// `touchGranularity`. Nil once the countdown has been brought back and
    /// nothing has moved since.
    private(set) var touchedAt: Date?

    /// Counts each time the countdown is brought back. The logger scrolls to
    /// it and the root swipes to the logger whenever it changes.
    private(set) var returns = 0

    /// True while the effort question waits below Log set. Scrolling to the
    /// countdown takes the question off the screen, the same reason
    /// `WatchLoggerRules.scrollsToTop` holds off for it, so the countdown waits
    /// until it has been answered or has folded away.
    var questionWaiting = false

    /// The exact moment of the last touch, which the delay counts from. Not
    /// observed, so the frames of a scroll re-evaluate nothing.
    @ObservationIgnored private(set) var lastTouch: Date?

    /// The lifter scrolled, swiped, dialled or answered something, or a rest
    /// started or was extended. Each one starts the wait again.
    func touch(at now: Date) {
        lastTouch = now
        if let touchedAt, now >= touchedAt, now.timeIntervalSince(touchedAt) < Self.touchGranularity { return }
        touchedAt = now
    }

    /// When the countdown is next due back in front, or nil when nothing is to
    /// be done: no rest running, the effort question waiting, or nothing
    /// touched since the countdown was last put back.
    ///
    /// A last touch stamped after `now` means the clock has gone backwards
    /// since. It is moved back to `now`, so the countdown comes back a delay
    /// from here rather than staying out of sight until the clock catches up.
    func returnDue(resting: Bool, now: Date) -> Date? {
        guard resting, !questionWaiting, let touch = lastTouch else { return nil }
        if touch > now { lastTouch = now }
        return min(touch, now).addingTimeInterval(Self.idleDelay)
    }

    /// Counts a return if one is due by `now`, and reports whether it did. The
    /// countdown is then where it should be, and nothing is owed until the
    /// watch is touched again.
    func bringBackIfDue(resting: Bool, now: Date) -> Bool {
        guard let due = returnDue(resting: resting, now: now), due <= now else { return false }
        lastTouch = nil
        touchedAt = nil
        returns += 1
        return true
    }
}
