import Foundation
import Observation

/// LOG-12, the rest countdown. Run with scripts/test-rest-render.sh; no
/// simulator is needed.
///
/// The phone's rest timer used to write `remaining` four times a second, so
/// every view that read it was drawn again four times a second for the length
/// of the rest. Nothing observable may change between a rest's start and its
/// end; the clock is asked for by date instead. The end-of-rest behaviour (the
/// one `onChange` at the end, the chime rule, the notification) must be exactly
/// what it was.
final class Counter { var value = 0 }

final class RecordingNotifier: RestNotifying {
    var scheduled: [Int] = []
    var cancels = 0
    var permissionAsks = 0
    func schedule(in seconds: Int, id: String) { scheduled.append(seconds) }
    func cancel(id: String) { cancels += 1 }
    func requestPermission() { permissionAsks += 1 }
}

@main
struct RestTimerRenderTests {
    @MainActor static func main() {
        // The chime rule is untouched.
        let end = Date(timeIntervalSince1970: 1_000)
        precondition(RestChimeRules.lateTolerance == 2)
        precondition(RestChimeRules.chimesOnExpiry(endsAt: end, now: end.addingTimeInterval(2)))
        precondition(!RestChimeRules.chimesOnExpiry(endsAt: end, now: end.addingTimeInterval(2.01)))

        // remaining and progress are answered for a date, not stored.
        let idle = RestTimer(notifier: RecordingNotifier())
        precondition(idle.remaining(at: .now) == 0 && idle.progress(at: .now) == 0)
        precondition(idle.isRunning == false)

        let notifier = RecordingNotifier()
        let timer = RestTimer(notifier: notifier)
        precondition(notifier.cancels == 1, "a stale notification is cleared at start-up")
        var changes = 0
        timer.onChange = { changes += 1 }

        // A 1.2 s rest, watched the way a SwiftUI body watches it: everything a
        // view could read, in one tracking scope, re-armed after each firing.
        let started = Date()
        timer.restore(endingAt: started.addingTimeInterval(1.2), totalSeconds: 2)
        precondition(changes == 1 && timer.isRunning)
        precondition(notifier.permissionAsks == 1 && notifier.scheduled == [1], "\(notifier.scheduled)")
        precondition(abs(timer.remaining(at: started) - 1.2) < 0.001)
        precondition(abs(timer.progress(at: started.addingTimeInterval(0.5)) - (1 - 0.7 / 2)) < 0.001)
        precondition(timer.remaining(at: started.addingTimeInterval(5)) == 0, "never negative")

        let observed = Counter()
        func watch() {
            withObservationTracking {
                _ = timer.endsAt; _ = timer.startedAt; _ = timer.totalSeconds
                _ = timer.remaining; _ = timer.progress; _ = timer.isRunning
            } onChange: { observed.value += 1 }
        }
        watch()
        spin(for: 0.9)   // three or four old ticks
        precondition(observed.value == 0, "a running rest changed something observable \(observed.value) time(s)")
        precondition(timer.isRunning && changes == 1)

        // The end: one change, the rest is gone, and the watcher hears of it.
        spin(for: 0.6)
        precondition(!timer.isRunning && timer.endsAt == nil && timer.remaining == 0)
        precondition(changes == 2, "the end is announced once, got \(changes)")
        precondition(observed.value == 1, "the view learns the rest is over")

        // +30 s style extension: the end moves and the old end no longer fires.
        let extended = Date()
        timer.restore(endingAt: extended.addingTimeInterval(0.5), totalSeconds: 1)
        timer.add(seconds: 1)
        precondition(abs(timer.remaining(at: extended) - 1.5) < 0.05)
        precondition(notifier.scheduled.last == 2 || notifier.scheduled.last == 1,
                     "the notification follows the later end: \(notifier.scheduled)")
        spin(for: 0.8)
        precondition(timer.isRunning, "the earlier end must not stop an extended rest")
        spin(for: 1.0)
        precondition(!timer.isRunning, "the extended end stops it")

        // Cancelling stops the end timer from firing on a rest that is gone.
        let cancelled = changes
        timer.restore(endingAt: Date().addingTimeInterval(0.3), totalSeconds: 1)
        timer.stop()
        spin(for: 0.6)
        precondition(changes == cancelled + 2, "start and stop, and nothing at the old end")

        print("ok")
    }

    /// Runs the main run loop, where the timer's one-shot lives.
    @MainActor static func spin(for seconds: TimeInterval) {
        RunLoop.main.run(until: Date().addingTimeInterval(seconds))
    }
}
