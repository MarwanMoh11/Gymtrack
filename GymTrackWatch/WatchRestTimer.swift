import Foundation
import Observation

/// The rest countdown on the wrist.
///
/// The phone owns the rest — it starts one when a set is logged and pushes the
/// end date — and this follows it so both screens count down to the same
/// instant. When the phone is out of range the watch runs its own rest instead,
/// because the whole point of logging from the wrist is that it works without
/// the phone nearby.
///
/// The payoff is the tap: a rest that ends while the wrist is down is felt,
/// which is something the phone in a locker can't do.
@MainActor
@Observable
final class WatchRestTimer {

    private(set) var endsAt: Date?
    private(set) var totalSeconds: Int = 0
    /// True while the rest is the watch's own rather than the phone's.
    private(set) var isLocal = false

    /// One timer, set for the instant the rest ends. Nothing ticks in between:
    /// the countdown is drawn by a `TimelineView` from `endsAt`, so the only
    /// thing this has to do on its own is the tap. A ticker that wrote the time
    /// remaining four times a second re-evaluated everything that read the
    /// timer, the whole logger included, for the length of every rest.
    @ObservationIgnored private var expiry: Timer?
    /// When a local rest began, so a mirror that crosses it in flight doesn't
    /// cancel a rest the phone simply hasn't heard about yet.
    @ObservationIgnored private var localStartedAt: Date?
    /// The end of the last rest that ran out here. The phone keeps sending that
    /// end date until it notices the rest is over, and a mirror arriving after
    /// the wrist had already tapped for it played the tap a second time.
    @ObservationIgnored private var lastExpiredAt: Date?
    /// What a rest running out here plays on the wrist. Handed in so a test can
    /// count it: whether the same end taps twice rests on `lastExpiredAt`, and
    /// the tap is the only thing that shows it.
    @ObservationIgnored private let restOver: () -> Void

    init(restOver: @escaping () -> Void = WatchHaptics.restOver) {
        self.restOver = restOver
    }

    var isRunning: Bool { endsAt != nil }

    func remaining(at now: Date = .now) -> TimeInterval {
        guard let endsAt else { return 0 }
        return max(0, endsAt.timeIntervalSince(now))
    }

    func progress(at now: Date = .now) -> Double {
        guard totalSeconds > 0, isRunning else { return 0 }
        return min(1, max(0, 1 - remaining(at: now) / Double(totalSeconds)))
    }

    func label(at now: Date = .now) -> String {
        guard isRunning else { return "—" }
        return remaining(at: now).clockString
    }

    /// Follows the phone. A rest the phone has stopped stops here too.
    ///
    /// A rest that had already ended by the time it arrives is the phone
    /// saying there is none. It is not run, so it neither draws a countdown
    /// that is over nor taps the wrist for it: a watch app relaunched from a
    /// cached context buzzed for a rest that ended ten minutes earlier.
    ///
    /// - Parameter unknown: the phone built this mirror without knowing the
    ///   rest (see `WatchSessionSnapshot.restUnknown`). Its blank answer is not
    ///   "there is none", so whatever this timer is running is left alone;
    ///   clearing on it wiped a rest the lifter was standing in.
    func sync(endsAt: Date?, total: Int, unknown: Bool = false, now: Date = .now) {
        guard !unknown else { return }
        if let followed = followable(endsAt, now: now) {
            // The phone's rest supersedes a local one started a moment ago.
            guard followed != self.endsAt || isLocal else { return }
            self.endsAt = followed
            self.totalSeconds = max(total, 1)
            self.isLocal = false
            arm(now: now)
        } else if !isLocal {
            clear()
        } else if let started = localStartedAt, now.timeIntervalSince(started) > 3 {
            // The phone has had time to hear about this rest and still says
            // there isn't one — it was skipped over there. Follow it.
            clear()
        }
    }

    /// The phone's end date, if it is one to run: not already over, and not
    /// the rest that ran out here a moment ago.
    private func followable(_ endsAt: Date?, now: Date) -> Date? {
        guard let endsAt, endsAt != lastExpiredAt,
              WatchRestRules.isFollowable(endsAt: endsAt, now: now) else { return nil }
        return endsAt
    }

    /// Runs a rest that the phone hasn't confirmed — or can't, being out of
    /// range.
    func startLocal(seconds: Int, now: Date = .now) {
        guard seconds > 0 else { return }
        endsAt = now.addingTimeInterval(TimeInterval(seconds))
        totalSeconds = seconds
        isLocal = true
        localStartedAt = now
        arm(now: now)
    }

    /// - Parameter silently: true for a caller that is already playing a tap of
    ///   its own. Starting a set ends the rest and plays the start haptic, and
    ///   two taps a frame apart read as a stutter rather than as two things
    ///   having happened.
    func stop(silently: Bool = false) {
        clear()
        if !silently { WatchHaptics.tick() }
    }

    func add(seconds: Int) {
        guard let endsAt else { return }
        self.endsAt = endsAt.addingTimeInterval(TimeInterval(seconds))
        totalSeconds += seconds
        arm(now: .now)
        WatchHaptics.tick()
    }

    private func clear() {
        expiry?.invalidate()
        expiry = nil
        endsAt = nil
        totalSeconds = 0
        isLocal = false
    }

    /// Sets the timer for the end of the rest, or ends it now if it is already
    /// there. An `add` re-arms it for the later end.
    private func arm(now: Date) {
        expiry?.invalidate()
        expiry = nil
        guard let endsAt else { return }
        guard endsAt > now else { return expire(now: now) }
        let timer = Timer(fire: endsAt, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.expireIfDue() }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiry = timer
    }

    /// The timer's own call. Guarded because the timer's hop onto the main
    /// actor can land after an `add` has moved the end further out. Internal,
    /// with the moment passed in, so a test can run the expiry the timer runs
    /// without waiting for a real one to fire.
    func expireIfDue(now: Date = .now) {
        guard let endsAt, endsAt <= now else { return }
        expire(now: now)
    }

    /// The rest has run out. The tap is only for a rest that ends while it is
    /// being watched: a timer the system held suspended long past the end
    /// finds a rest that ended minutes ago and clears it without a word. A
    /// wake a few seconds late, which the wrist-down system does routinely,
    /// still taps; see `WatchRestRules.lateExpiryTolerance`.
    private func expire(now: Date) {
        guard let endsAt else { return }
        let buzzes = WatchRestRules.buzzesOnExpiry(endsAt: endsAt, now: now)
        lastExpiredAt = endsAt
        clear()
        if buzzes { restOver() }
    }
}
