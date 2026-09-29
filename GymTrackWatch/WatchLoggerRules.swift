import Foundation

/// The decisions the wrist logger makes about taps and exercises, kept free of
/// SwiftUI and WatchKit so the test harness can hold them to account without
/// a watch.
enum WatchLoggerRules {

    /// How long after a set is logged that another tap which would change the
    /// record is taken for the same tap arriving twice.
    ///
    /// A chalked, sweaty thumb double-taps. The mirror is updated in the same
    /// call that logs, so by the second tap the button is already bound to the
    /// next set: without this the same numbers went onto set 4 as onto set 3,
    /// or the tap landed on whatever the rest card slid under the thumb. Six
    /// tenths is longer than any double tap and shorter than anything a person
    /// does on purpose after a set: nobody walks to the bar, announces the next
    /// set and undoes the last one inside it.
    static let doubleTapWindow: TimeInterval = 0.6

    /// Whether the logger scrolls back to its top when the rest timer changes.
    ///
    /// Only on the way in, and not while the effort card is waiting for an
    /// answer. Logging a set starts the rest in the same call that raises the
    /// card, so scrolling to the countdown carried the question off the screen
    /// before it could be read. Once the card is answered or has folded into
    /// the "Rate last set" button, the next rest scrolls as it always did.
    static func scrollsToTop(whenRestBecomes resting: Bool, effortCardWaiting: Bool) -> Bool {
        resting && !effortCardWaiting
    }

    /// Whether a tap that logs, starts or undoes a set is a tap the lifter
    /// meant, given when the last set was logged from this screen.
    ///
    /// A clock that has gone backwards since the last log accepts the tap. The
    /// alternative is a button that stays dead until the clock catches up.
    static func acceptsSetTap(lastLoggedAt: Date?, now: Date) -> Bool {
        guard let lastLoggedAt else { return true }
        let elapsed = now.timeIntervalSince(lastLoggedAt)
        return elapsed < 0 || elapsed >= doubleTapWindow
    }

    /// What a tap on an exercise in the wrist's list means.
    enum ExerciseTap: Equatable {
        /// "I am lifting this now": the session moves onto it, and the phone,
        /// the Lock Screen and the dock follow.
        case focus
        /// Only looking at what was logged. Moves nothing, and sends nothing to
        /// the phone.
        case review
    }

    /// A finished exercise is only ever reviewed.
    ///
    /// The phone's working position skips a finished pick and falls back to the
    /// first unfinished exercise in plan order, so a focus sent for one threw
    /// away the exercise the lifter had chosen out of order: the phone, the
    /// Lock Screen and the dock jumped to one nobody was doing, and a set
    /// logged from the wrist without looking went onto it.
    static func tap(on exercise: WatchExerciseSnapshot) -> ExerciseTap {
        exercise.isComplete ? .review : .focus
    }

    /// Whether the connector may move the phone's working position onto an
    /// exercise. The list already offers a review rather than a focus for a
    /// finished one, but the connector is the last stop before the phone hears
    /// it, and a second caller that forgot the check would drag the phone, the
    /// Lock Screen and the dock off the exercise being lifted.
    ///
    /// An exercise the mirror doesn't hold is let through: refusing it is the
    /// phone's call, and the wrist's pick is dropped once a mirror shows it gone.
    static func allowsFocus(on catalogID: String, in exercises: [WatchExerciseSnapshot]) -> Bool {
        let matches = exercises.filter { $0.id == catalogID }
        return matches.isEmpty || matches.contains { tap(on: $0) == .focus }
    }
}

/// When the wrist buzzes for a rest, and where its countdown ticks.
enum WatchRestRules {

    /// How late a rest's end may be noticed and still be buzzed for.
    ///
    /// The buzz is for a rest that ends while the lifter is looking at, or
    /// standing beside, its countdown. Anything later than this was not that:
    /// a mirror carrying a rest that ended ten minutes ago, a relaunch from a
    /// cached context, an app the system held suspended past the end. Buzzing
    /// then is a tap for something that is long over.
    static let buzzTolerance: TimeInterval = 2

    /// Whether a rest that has ended at `endsAt` is still fresh enough to tap
    /// the wrist for.
    static func buzzesOnEnd(endsAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(endsAt) <= buzzTolerance
    }

    /// How late the watch's own timer may fire for a rest it was running and
    /// still tap the wrist.
    ///
    /// Wider than `buzzTolerance` on purpose. That one judges a rest that
    /// *arrives* already over, which nobody was waiting on. This one judges a
    /// rest the lifter watched count down: with the wrist down the system
    /// coalesces timers and can wake the app seconds late, and a tap then is
    /// still the one they are waiting for. Only a wake long after the end, an
    /// app held suspended for minutes, is past the point of being useful.
    static let lateExpiryTolerance: TimeInterval = 60

    /// Whether a rest this watch was running, whose timer has just fired or
    /// been found overdue, still earns its tap.
    static func buzzesOnExpiry(endsAt: Date, now: Date) -> Bool {
        now.timeIntervalSince(endsAt) <= lateExpiryTolerance
    }

    /// Whether a rest that the phone says ends at `endsAt` is one to follow.
    ///
    /// One that ended more than the tolerance ago is not a rest at all, and is
    /// treated as the phone saying there is none. It is not run, so it neither
    /// shows a countdown that is already over nor plays the tap for it.
    static func isFollowable(endsAt: Date, now: Date) -> Bool {
        buzzesOnEnd(endsAt: endsAt, now: now)
    }

    /// Where the countdown's `TimelineView` draws its ticks from.
    ///
    /// Anchored back from the end by whole seconds, so every tick lands exactly
    /// on a second boundary of the rest and the number changes when it should,
    /// not up to a second late. Far enough back to cover the whole rest: a
    /// periodic schedule isn't promised to tick before the date it runs from.
    static func tickAnchor(endsAt: Date, totalSeconds: Int, now: Date) -> Date {
        let span = max(Double(totalSeconds), endsAt.timeIntervalSince(now).rounded(.up), 0) + 1
        return endsAt.addingTimeInterval(-span.rounded(.up))
    }
}

/// What a watch-saved Health workout says about the GymTrack session it
/// belongs to.
///
/// Every field but the session's identity is optional, and an absent one is
/// left out of the metadata rather than written as a stand-in. A workout saved
/// because the phone finished the session can only say what the wrist last
/// heard, and a zero written where nothing was heard would read as a session
/// that lifted nothing.
struct WatchWorkoutMetadata: Equatable {
    var sessionID: UUID?
    var title: String?
    var sets: Int?
    var volumeKg: Double?

    /// What the wrist can honestly say about `recording` from the last session
    /// snapshot it holds.
    ///
    /// A snapshot of another session says nothing about this one: it is
    /// ignored whole, because its title and totals would be somebody else's.
    /// A total of nothing is left out rather than kept: no sets logged, and a
    /// volume of zero, are both what an unheard-from session looks like, and
    /// this cannot tell the two apart.
    init(recording: UUID?, snapshot: WatchSessionSnapshot?) {
        sessionID = recording
        guard let snapshot, snapshot.sessionID == recording else { return }
        let title = snapshot.title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.title = title.isEmpty ? nil : title
        sets = snapshot.completedSets > 0 ? snapshot.completedSets : nil
        volumeKg = snapshot.volumeKg > 0 ? snapshot.volumeKg : nil
    }
}
