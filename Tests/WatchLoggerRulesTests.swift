import Foundation
import Observation

/// Run with scripts/test-watch-logger-rules.sh; no simulator or watch needed.
///
/// The views themselves (the countdown subview, the inline effort card, the
/// exercise review) cannot be built here. What can be held to account is every
/// decision they make, and `WatchRestTimer`, which is compiled as it ships
/// against a stand-in for the haptics.
@main
struct WatchLoggerRulesTests {

    static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @MainActor static func main() {
        doubleTapLogsOnce()
        restBuzzesOnlyWhenItEndsInView()
        staleMirrorIsNotARest()
        theRestEndsOnceAndNothingTicksBeforeIt()
        ticksLandOnTheEnd()
        metadataSaysOnlyWhatTheWristHeard()
        finishedExercisesAreReviewedNotFocused()
        print("WatchLoggerRulesTests passed")
    }

    // MARK: - WATCH-13

    static func doubleTapLogsOnce() {
        // Log set as the view runs it: every tap asks, and only an accepted one
        // logs and starts the window.
        var last: Date?
        var logged = 0
        func tap(at seconds: TimeInterval) {
            let moment = now.addingTimeInterval(seconds)
            guard WatchLoggerRules.acceptsSetTap(lastLoggedAt: last, now: moment) else { return }
            last = moment
            logged += 1
        }
        tap(at: 0)
        tap(at: 0.15)
        tap(at: 0.59)
        precondition(logged == 1, "A double tap logged \(logged) sets")
        tap(at: 0.7)
        precondition(logged == 2, "The next deliberate tap, 0.7 s on, was refused")

        precondition(WatchLoggerRules.acceptsSetTap(lastLoggedAt: nil, now: now),
                     "The first tap of a session is always taken")
        precondition(!WatchLoggerRules.acceptsSetTap(lastLoggedAt: now, now: now.addingTimeInterval(0.599)))
        precondition(WatchLoggerRules.acceptsSetTap(lastLoggedAt: now, now: now.addingTimeInterval(0.6)))
        precondition(WatchLoggerRules.acceptsSetTap(lastLoggedAt: now, now: now.addingTimeInterval(-30)),
                     "A clock that went backwards must not leave the button dead")
    }

    // MARK: - WATCH-12

    static func restBuzzesOnlyWhenItEndsInView() {
        precondition(WatchRestRules.buzzesOnEnd(endsAt: now.addingTimeInterval(-0.2), now: now),
                     "A rest that ended a moment ago is felt")
        precondition(WatchRestRules.buzzesOnEnd(endsAt: now.addingTimeInterval(-2), now: now))
        precondition(!WatchRestRules.buzzesOnEnd(endsAt: now.addingTimeInterval(-2.1), now: now),
                     "Past the tolerance is not a rest ending in view")
        precondition(!WatchRestRules.buzzesOnEnd(endsAt: now.addingTimeInterval(-600), now: now),
                     "A rest that ended ten minutes ago must not buzz on arrival")
        // The watch's own timer for a rest it ran: a wake seconds late still
        // taps, one minutes late does not.
        precondition(WatchRestRules.buzzesOnExpiry(endsAt: now.addingTimeInterval(-8), now: now),
                     "A timer the wrist-down system woke late must still tap")
        precondition(!WatchRestRules.buzzesOnExpiry(endsAt: now.addingTimeInterval(-600), now: now),
                     "A rest that ended minutes before the wake is not tapped for")
        precondition(!WatchRestRules.isFollowable(endsAt: now.addingTimeInterval(-600), now: now))
        precondition(WatchRestRules.isFollowable(endsAt: now.addingTimeInterval(45), now: now))
    }

    @MainActor static func staleMirrorIsNotARest() {
        WatchHaptics.restOvers = 0
        let timer = WatchRestTimer()

        timer.sync(endsAt: now.addingTimeInterval(-600), total: 90, now: now)
        precondition(!timer.isRunning, "A rest that ended ten minutes ago is not a rest")
        precondition(WatchHaptics.restOvers == 0, "and it must not tap the wrist")

        timer.sync(endsAt: now.addingTimeInterval(60), total: 90, now: now)
        precondition(timer.isRunning && !timer.isLocal && WatchHaptics.restOvers == 0,
                     "A live phone rest runs quietly")
        // The phone's rest is replaced by a stale one it never stopped sending.
        timer.sync(endsAt: now.addingTimeInterval(-600), total: 90, now: now)
        precondition(!timer.isRunning && WatchHaptics.restOvers == 0,
                     "A stale mirror after a live one clears the rest, silently")

        // A rest that ended a moment before the mirror arrived is a rest the
        // lifter is still standing beside.
        timer.sync(endsAt: now.addingTimeInterval(-0.5), total: 90, now: now)
        precondition(!timer.isRunning && WatchHaptics.restOvers == 1, "A just-ended rest taps once")
        // ...and the phone going on to send that same end date is not a second rest.
        timer.sync(endsAt: now.addingTimeInterval(-0.5), total: 90, now: now.addingTimeInterval(0.4))
        precondition(!timer.isRunning && WatchHaptics.restOvers == 1,
                     "The same end date arriving again tapped the wrist a second time")
    }

    @MainActor static func theRestEndsOnceAndNothingTicksBeforeIt() {
        WatchHaptics.restOvers = 0
        let timer = WatchRestTimer()
        timer.startLocal(seconds: 1)
        precondition(timer.isRunning && timer.isLocal)

        // The countdown is drawn from the end date by a TimelineView, so
        // nothing the logger reads may change between the start and the end.
        // The old ticker wrote `remaining` four times a second.
        nonisolated(unsafe) var changed = false
        withObservationTracking {
            _ = timer.endsAt
            _ = timer.totalSeconds
            _ = timer.isRunning
            _ = timer.isLocal
        } onChange: { changed = true }
        RunLoop.main.run(until: Date().addingTimeInterval(0.6))
        precondition(!changed, "The rest changed observable state before it ended")
        precondition(timer.isRunning, "The rest ended early")

        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        precondition(!timer.isRunning, "The rest never ended")
        precondition(WatchHaptics.restOvers == 1, "A rest that ends in view taps exactly once, not \(WatchHaptics.restOvers)")
        precondition(changed, "Ending the rest is a change the logger has to hear")

        precondition(timer.remaining(at: now) == 0 && timer.label(at: now) == "—")
    }

    static func ticksLandOnTheEnd() {
        for (ends, total) in [(90.0, 90), (37.4, 90), (200.0, 120)] {
            let endsAt = now.addingTimeInterval(ends)
            let anchor = WatchRestRules.tickAnchor(endsAt: endsAt, totalSeconds: total, now: now)
            precondition(anchor <= now, "The anchor is after now, so the first ticks would be missed")
            let span = endsAt.timeIntervalSince(anchor)
            precondition(span == span.rounded(), "Ticks would drift off the whole seconds of the rest")
        }
    }

    // MARK: - WATCH-15

    static func metadataSaysOnlyWhatTheWristHeard() {
        let id = UUID()
        func set(_ done: Bool) -> WatchSetSnapshot {
            WatchSetSnapshot(id: UUID(), index: 0, weightKg: 60, reps: 8, seconds: 0,
                             targetRepsLow: 8, targetRepsHigh: 8, isCompleted: done,
                             completedAt: done ? now : nil)
        }
        func snapshot(id: UUID, title: String = "Push", sets: [WatchSetSnapshot], volume: Double)
            -> WatchSessionSnapshot {
            WatchSessionSnapshot(
                sessionID: id, title: title, planName: "", startedAt: now,
                exercises: [WatchExerciseSnapshot(id: "bench", name: "Bench", order: 0, tracking: .weightReps,
                                                   restSeconds: 90, sets: sets)],
                restTotalSeconds: 0, restAutoStart: true, volumeKg: volume, unit: .kg)
        }

        let full = WatchWorkoutMetadata(recording: id, snapshot: snapshot(id: id, sets: [set(true), set(true), set(false)],
                                                                          volume: 960))
        precondition(full == WatchWorkoutMetadata(recording: id, snapshot: snapshot(id: id, sets: [set(true), set(true), set(false)], volume: 960)),
                     "Metadata is a value")
        precondition(full.sessionID == id && full.title == "Push" && full.sets == 2 && full.volumeKg == 960,
                     "A phone-finished session gets the same metadata as a wrist Finish")

        let none = WatchWorkoutMetadata(recording: id, snapshot: nil)
        precondition(none.sessionID == id, "The session UUID is there even with no snapshot")
        precondition(none.title == nil && none.sets == nil && none.volumeKg == nil,
                     "With nothing heard, no title, sets or volume, and no zero stand-ins")

        let other = WatchWorkoutMetadata(recording: id, snapshot: snapshot(id: UUID(), sets: [set(true)], volume: 60))
        precondition(other.sessionID == id && other.title == nil && other.sets == nil && other.volumeKg == nil,
                     "Another session's snapshot must not name this one's workout")

        let bare = WatchWorkoutMetadata(recording: id, snapshot: snapshot(id: id, title: "  ", sets: [set(false)], volume: 0))
        precondition(bare.title == nil && bare.sets == nil && bare.volumeKg == nil,
                     "A blank title, no completed sets and a zero volume are all left out, not written as zeros")
    }

    // MARK: - LOG-01

    static func finishedExercisesAreReviewedNotFocused() {
        func exercise(_ done: [Bool]) -> WatchExerciseSnapshot {
            WatchExerciseSnapshot(
                id: "x", name: "X", order: 0, tracking: .weightReps, restSeconds: 90,
                sets: done.enumerated().map {
                    WatchSetSnapshot(id: UUID(), index: $0.offset, weightKg: 60, reps: 8, seconds: 0,
                                     targetRepsLow: 8, targetRepsHigh: 8, isCompleted: $0.element)
                })
        }
        precondition(WatchLoggerRules.tap(on: exercise([true, true])) == .review,
                     "Tapping a finished exercise must review it, which sends no focus")
        precondition(WatchLoggerRules.tap(on: exercise([true, false])) == .focus)
        precondition(WatchLoggerRules.tap(on: exercise([false, false])) == .focus)
        precondition(WatchLoggerRules.tap(on: exercise([])) == .focus,
                     "An exercise with no sets is not finished")
    }
}
