import Foundation
import Testing
@testable import GymTrack

/// What an intent's `perform()` hands to the app, in both of the orders the
/// system may run it and the app's activation in. A start that went missing
/// left "Start my GymTrack workout" opening the app and doing nothing; one that
/// was read twice started two workouts; one read before the unfinished session
/// was adopted began a second workout beside it.
///
/// Each test announces on a center of its own, standing in for `RootView`
/// hearing it, and reads the real note in `SharedStore`'s App Group, which an
/// unsigned test host keeps like any other suite. Every test clears the note
/// before and after, because one left behind would start a workout the next
/// time the host's app came forward.
@MainActor @Suite(.serialized)
struct PendingActionHandoffTests {

    /// What the listener took from the inbox. A class because the observer
    /// closure is `@Sendable` and cannot mutate a captured local.
    private final class Started: @unchecked Sendable {
        var actions: [SharedStore.PendingAction] = []
    }

    /// Runs `body` with no note waiting, a fresh inbox, and a listener that
    /// reads the inbox whenever `center` announces, and clears the note after.
    private func withHandoff(open: Bool,
                             _ body: (NotificationCenter, PendingActionHandoff.Inbox, Started) -> Void) {
        _ = SharedStore.takeAction()
        let center = NotificationCenter()
        let inbox = PendingActionHandoff.Inbox()
        if open { inbox.open() }
        let started = Started()
        let listener = center.addObserver(forName: PendingActionHandoff.didRequest, object: nil, queue: nil) { _ in
            MainActor.assumeIsolated {
                if let action = inbox.take() { started.actions.append(action) }
            }
        }
        defer {
            center.removeObserver(listener)
            _ = SharedStore.takeAction()
        }
        body(center, inbox, started)
    }

    @Test func aNoteIsReadWhicheverOfItAndTheAppComingForwardArrivesFirst() {
        withHandoff(open: true) { center, inbox, started in
            // The app came forward first, the order that used to lose the
            // start: its read finds nothing, and `perform()` then runs.
            #expect(inbox.take() == nil)
            PendingActionHandoff.hand(.startToday, center: center)
            #expect(started.actions == [.startToday])

            // `perform()` first: the note is there when the app comes forward.
            SharedStore.request(.startFreestyle)
            #expect(inbox.take() == .startFreestyle)
        }
    }

    @Test func aNoteHeardAndThenMetAgainOnActivationStartsOneWorkout() {
        withHandoff(open: true) { center, inbox, started in
            PendingActionHandoff.hand(.startToday, center: center)
            if let action = inbox.take() { started.actions.append(action) }
            #expect(started.actions == [.startToday])
        }
    }

    @Test func aNoteAnnouncedBeforeTheAppIsReadyWaitsForIt() {
        withHandoff(open: false) { center, inbox, started in
            // `RootView` has not adopted the unfinished session yet, and acting
            // now would begin a second workout beside it.
            PendingActionHandoff.hand(.startToday, center: center)
            #expect(started.actions.isEmpty)

            inbox.open()
            #expect(inbox.take() == .startToday, "the note is still there once the app can read it")
            #expect(inbox.take() == nil)
        }
    }
}
