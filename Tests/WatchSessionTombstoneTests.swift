import Foundation

/// Run with scripts/test-watch-session-tombstone.sh; no simulator or Health
/// access needed.
///
/// `Wrist` plays the part of `WatchConnector` and `WatchRootView` across a
/// relaunch: it loads the tombstone from defaults the way the connector's
/// init does, settles it on every mirror the way `receive` does, and asks the
/// same two questions the view and the recorder ask before a Health workout
/// starts.
@main
struct WatchSessionTombstoneTests {

    struct Wrist {
        let defaults: UserDefaults
        var mirror = WatchMirror.placeholder
        var awaitingFreshMirror = false
        var tombstone: WatchSessionTombstone

        init(defaults: UserDefaults) {
            self.defaults = defaults
            tombstone = WatchSessionTombstone(defaults: defaults)
        }

        var session: WatchSessionSnapshot? {
            tombstone.liveSession(in: mirror, awaitingFreshMirror: awaitingFreshMirror)
        }

        /// What `syncRecorder` and `startIfNeeded` together decide.
        var startsRecorder: Bool {
            guard let session else { return false }
            return tombstone.admits(session.sessionID)
        }

        mutating func end(_ id: UUID) {
            tombstone.mark(id)
            tombstone.save(to: defaults)
        }

        /// Every mirror goes through the wire format, as the cached context does.
        mutating func receive(_ incoming: WatchMirror, fromCache: Bool = false) {
            let payload = incoming.watchPayload(key: WatchLink.mirrorKey)
            guard let decoded = WatchMirror.fromWatchPayload(payload, key: WatchLink.mirrorKey) else {
                fatalError("Mirror did not survive the wire")
            }
            guard decoded.sentAt >= mirror.sentAt else { return }
            mirror = decoded
            tombstone.settle(with: decoded, fromCache: fromCache)
            tombstone.save(to: defaults)
        }
    }

    static func main() {
        let suite = "WatchSessionTombstoneTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { fatalError("No defaults suite") }
        defer { defaults.removePersistentDomain(forName: suite) }

        let start = Date().addingTimeInterval(-40 * 60)
        let s = snapshot(start)
        let t = snapshot(Date().addingTimeInterval(-60))
        let sMirror = mirror(s, sentAt: start.addingTimeInterval(30 * 60))

        // The wrist is showing S when the lifter taps Finish out of range.
        var wrist = Wrist(defaults: defaults)
        wrist.receive(sMirror)
        precondition(wrist.session?.sessionID == s.sessionID && wrist.startsRecorder)
        wrist.end(s.sessionID)
        precondition(wrist.session == nil, "A session ended on the wrist must leave the screen at once")

        // Terminated on the walk back, relaunched with the phone still away:
        // the cached context describes S as live.
        var relaunched = Wrist(defaults: defaults)
        precondition(relaunched.tombstone.sessionID == s.sessionID, "The tombstone must survive a relaunch")
        relaunched.receive(sMirror, fromCache: true)
        precondition(relaunched.session == nil, "A cached mirror of an ended session must not show it")
        precondition(!relaunched.startsRecorder, "A cached mirror of an ended session must not start Health")
        precondition(!relaunched.tombstone.admits(s.sessionID), "The recorder must refuse the ended session")
        precondition(relaunched.tombstone.sessionID == s.sessionID,
                     "A cached context proves nothing about whether the phone heard the Finish")

        // Back in range, the reply to requestMirror overtakes the queued Finish.
        relaunched.receive(mirror(s, sentAt: Date()))
        precondition(relaunched.session == nil && !relaunched.startsRecorder,
                     "A reply that still calls the session live must not revive it")
        precondition(relaunched.tombstone.sessionID == s.sessionID)

        // Without the tombstone, the same cached mirror is exactly the bug.
        var untouched = Wrist(defaults: UserDefaults(suiteName: suite + ".bare")!)
        untouched.receive(sMirror, fromCache: true)
        precondition(untouched.startsRecorder, "The harness must reproduce the unguarded restart")
        UserDefaults().removePersistentDomain(forName: suite + ".bare")

        // A new session T shows and records while S's tombstone is still set,
        // even from a cached context that cannot retire it.
        var next = Wrist(defaults: defaults)
        next.receive(mirror(t, sentAt: Date().addingTimeInterval(1)), fromCache: true)
        precondition(next.tombstone.sessionID == s.sessionID)
        precondition(next.session?.sessionID == t.sessionID && next.startsRecorder,
                     "A later session must not be hidden by the one before it")

        // The phone's answer without S retires the tombstone, and it stays
        // retired across the next relaunch.
        next.receive(mirror(nil, sentAt: Date().addingTimeInterval(2)))
        precondition(next.tombstone.sessionID == nil, "A mirror without S must clear the tombstone")
        precondition(defaults.string(forKey: WatchSessionTombstone.defaultsKey) == nil,
                     "A cleared tombstone must leave no key behind")
        precondition(Wrist(defaults: defaults).tombstone.sessionID == nil)

        var switched = Wrist(defaults: defaults)
        switched.end(s.sessionID)
        switched.receive(mirror(t, sentAt: Date().addingTimeInterval(3)))
        precondition(switched.tombstone.sessionID == nil, "A mirror carrying a different session must clear it")

        // Still guarded by the twelve-hour rule it replaced in the connector.
        var stale = Wrist(defaults: defaults)
        stale.receive(mirror(snapshot(Date().addingTimeInterval(-13 * 3600)), sentAt: Date().addingTimeInterval(4)))
        precondition(stale.session == nil)
        var waiting = Wrist(defaults: defaults)
        waiting.awaitingFreshMirror = true
        waiting.receive(mirror(t, sentAt: Date().addingTimeInterval(5)), fromCache: true)
        precondition(waiting.session == nil)

        linkRule()
        print("WatchSessionTombstoneTests passed")
    }

    /// `HealthKitService.acceptWatchWorkout` retires only the phone's own save.
    static func linkRule() {
        let phone = UUID(), first = UUID(), second = UUID()
        precondition(WatchWorkoutLink.decide(current: nil, incoming: first, phoneWritten: [phone]) == .link)
        precondition(WatchWorkoutLink.decide(current: first, incoming: first, phoneWritten: []) == .alreadyLinked)
        precondition(WatchWorkoutLink.decide(current: phone, incoming: first, phoneWritten: [phone])
                     == .replacePhoneFallback(phone),
                     "A late watch save must still replace the phone's fallback")
        precondition(WatchWorkoutLink.decide(current: first, incoming: second, phoneWritten: [phone])
                     == .keepExisting,
                     "A second watch workout must not replace the first")
        precondition(WatchWorkoutLink.decide(current: first, incoming: second, phoneWritten: []) == .keepExisting,
                     "An ID the phone never wrote is not the phone's to retire")
    }

    static func snapshot(_ startedAt: Date) -> WatchSessionSnapshot {
        WatchSessionSnapshot(
            sessionID: UUID(), title: "Push", planName: "", startedAt: startedAt,
            exercises: [WatchExerciseSnapshot(id: "bench", name: "Bench", order: 0, tracking: .weightReps,
                                              restSeconds: 90, sets: [])],
            restTotalSeconds: 0, restAutoStart: true, volumeKg: 0, unit: .kg
        )
    }

    static func mirror(_ session: WatchSessionSnapshot?, sentAt: Date) -> WatchMirror {
        var mirror = WatchMirror.placeholder
        mirror.sentAt = sentAt
        mirror.session = session
        return mirror
    }
}
