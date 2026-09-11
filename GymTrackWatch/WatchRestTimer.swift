import Foundation
import WatchKit

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
    private(set) var remaining: TimeInterval = 0
    /// True while the rest is the watch's own rather than the phone's.
    private(set) var isLocal = false

    private var ticker: Timer?
    /// When a local rest began, so a mirror that crosses it in flight doesn't
    /// cancel a rest the phone simply hasn't heard about yet.
    private var localStartedAt: Date?

    var isRunning: Bool { endsAt != nil }

    var progress: Double {
        guard totalSeconds > 0, isRunning else { return 0 }
        return min(1, max(0, 1 - remaining / Double(totalSeconds)))
    }

    var label: String {
        guard isRunning else { return "—" }
        return remaining.clockString
    }

    /// Follows the phone. A rest the phone has stopped stops here too.
    func sync(endsAt: Date?, total: Int) {
        if let endsAt {
            // The phone's rest supersedes a local one started a moment ago.
            guard endsAt != self.endsAt || isLocal else { return }
            self.endsAt = endsAt
            self.totalSeconds = max(total, 1)
            self.isLocal = false
            refresh()
            startTicker()
        } else if !isLocal {
            clear()
        } else if let started = localStartedAt, Date().timeIntervalSince(started) > 3 {
            // The phone has had time to hear about this rest and still says
            // there isn't one — it was skipped over there. Follow it.
            clear()
        }
    }

    /// Runs a rest that the phone hasn't confirmed — or can't, being out of
    /// range.
    func startLocal(seconds: Int) {
        guard seconds > 0 else { return }
        endsAt = Date().addingTimeInterval(TimeInterval(seconds))
        totalSeconds = seconds
        isLocal = true
        localStartedAt = .now
        refresh()
        startTicker()
    }

    func stop() {
        clear()
        WatchHaptics.tick()
    }

    func add(seconds: Int) {
        guard let endsAt else { return }
        self.endsAt = endsAt.addingTimeInterval(TimeInterval(seconds))
        totalSeconds += seconds
        refresh()
        WatchHaptics.tick()
    }

    private func clear() {
        ticker?.invalidate()
        ticker = nil
        endsAt = nil
        totalSeconds = 0
        remaining = 0
        isLocal = false
    }

    private func startTicker() {
        guard ticker == nil else { return }
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
            clear()
            WatchHaptics.restOver()
        }
    }
}
