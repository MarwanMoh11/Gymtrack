import Foundation

/// How an intent tells the app that it has left a note.
///
/// The note alone is not enough. With `openAppWhenRun` the system brings the
/// app forward and runs `perform()` in the same process, and it makes no
/// promise about which comes first. The app used to read the note only when it
/// became active, so an intent that ran second wrote to an inbox nobody was
/// about to check: "Start my GymTrack workout" opened the app and did nothing,
/// and the note started a workout unprompted the next time the app came
/// forward, or aged out.
///
/// Announcing every note in-process makes the order stop mattering. It stays
/// in-process on purpose: the announcement reaches nothing when an intent runs
/// in another process, and there the note left for the next activation is still
/// the only channel.
enum PendingActionHandoff {
    static let didRequest = Notification.Name("com.marwanmohamed.gymtrack.pendingActionRequested")

    /// Writes the note first and announces it second, so whoever hears the
    /// announcement finds the note already there. Announcing first would hand a
    /// listener an empty inbox, which is the race this exists to remove.
    static func hand(_ action: SharedStore.PendingAction, center: NotificationCenter = .default) {
        SharedStore.request(action)
        center.post(name: didRequest, object: nil)
    }

    /// The app's end of it: whoever reads the note goes through here.
    ///
    /// Closed at launch. An announcement can arrive before the app has adopted
    /// the session it was left with, and a start acted on then would begin a
    /// second workout beside the unfinished one. While closed the note is left
    /// where it is, untouched and unread, and the read that follows opening
    /// finds it. Taking is `SharedStore.takeAction`, which clears as it reads,
    /// so a note announced and then met again on activation starts one
    /// workout, not two.
    @MainActor
    final class Inbox {
        private var isOpen = false

        func open() { isOpen = true }

        func take() -> SharedStore.PendingAction? {
            isOpen ? SharedStore.takeAction() : nil
        }
    }
}

#if os(iOS)
import AppIntents

/// What Siri, Spotlight, the Action Button, a Shortcut and a widget button all
/// end up calling.
///
/// None of them can start a workout themselves: a session needs the app's
/// SwiftData store, the plan behind today, the progression that decides the
/// opening weights, a Live Activity and the watch link — and an intent runs in
/// a process that has none of those. So each one leaves a note in the shared
/// container and opens the app, which picks the note up the instant it comes to
/// the front. One code path, whichever surface asked.

@available(iOS 17.0, *)
struct StartTodayWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Today's Workout"
    static let description = IntentDescription(
        "Starts the session your routine has scheduled for today. On a rest day, or with no routine set up, it starts a freestyle session instead."
    )
    /// The app has to come forward: this finishes in the logger, with the first
    /// set already loaded.
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingActionHandoff.hand(.startToday)
        return .result()
    }
}

@available(iOS 17.0, *)
struct StartFreestyleWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Start a Freestyle Workout"
    static let description = IntentDescription(
        "Starts an empty session you fill in as you go, whatever your routine says about today."
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingActionHandoff.hand(.startFreestyle)
        return .result()
    }
}

@available(iOS 17.0, *)
struct OpenWorkoutIntent: AppIntent {
    static let title: LocalizedStringResource = "Open My Workout"
    static let description = IntentDescription(
        "Opens the session you have running, on the set you're about to do."
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingActionHandoff.hand(.openSession)
        return .result()
    }
}
#endif
