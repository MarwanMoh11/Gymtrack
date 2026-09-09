import ActivityKit
import Foundation
import os

/// Owns the Live Activity for the running session — the card on the Lock
/// Screen and the pill in the Dynamic Island.
///
/// Nothing here is on a schedule. The widget keeps its own clocks running from
/// the dates in the state, so this only pushes when the workout actually
/// changes: a set logged, a rest started or extended, an exercise added.
@MainActor
final class WorkoutLiveActivity {

    static let shared = WorkoutLiveActivity()
    private init() {}

    private var activity: Activity<WorkoutActivity>?
    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack", category: "LiveActivity")

    /// False when the user has switched Live Activities off for GymTrack (or
    /// system-wide). Everything below is then a no-op.
    var isAvailable: Bool { ActivityAuthorizationInfo().areActivitiesEnabled }

    // MARK: - Lifecycle

    /// Brings the Lock Screen in line with the session, whatever state it's in:
    /// adopts the card already running after a force-quit, raises one if there
    /// isn't one, and otherwise just updates.
    ///
    /// Every mutation goes through here rather than a plain update because
    /// `Activity.request` is refused while the app isn't visible — the request
    /// made during launch fails silently, and this is what heals it on the next
    /// thing the user does.
    func sync(sessionID: UUID, title: String, planName: String, state: WorkoutActivity.ContentState) {
        guard isAvailable else {
            log.debug("Live Activities are switched off for GymTrack")
            return
        }

        let running = Activity<WorkoutActivity>.activities
        if activity == nil {
            activity = running.first { $0.attributes.sessionID == sessionID }
        }
        // A card for a workout that already ended is worse than no card.
        for stray in running where stray.attributes.sessionID != sessionID {
            Task { await stray.end(nil, dismissalPolicy: .immediate) }
        }

        guard activity == nil else { return push(state) }

        do {
            activity = try Activity.request(
                attributes: WorkoutActivity(sessionID: sessionID, sessionTitle: title, planName: planName),
                content: Self.content(for: state),
                pushType: nil
            )
        } catch {
            log.debug("Live Activity not started: \(error.localizedDescription, privacy: .public)")
        }
    }

    func push(_ state: WorkoutActivity.ContentState) {
        guard let activity else { return }
        let content = Self.content(for: state)
        Task { await activity.update(content) }
    }

    /// Takes the card down. Passing the closing state lets it show the final
    /// numbers for the instant before it disappears.
    func end(with state: WorkoutActivity.ContentState?) {
        let running = Activity<WorkoutActivity>.activities
        activity = nil
        let content = state.map(Self.content(for:))
        for card in running {
            Task { await card.end(content, dismissalPolicy: .immediate) }
        }
    }

    /// Clears anything left over from a previous run of the app.
    func endAll() {
        end(with: nil)
    }

    // MARK: - Content

    /// While resting, the rest end doubles as the stale date: when it passes,
    /// the widget flips to "rest done" on its own rather than waiting for the
    /// app to be woken up to say so.
    private static func content(for state: WorkoutActivity.ContentState) -> ActivityContent<WorkoutActivity.ContentState> {
        ActivityContent(state: state, staleDate: state.restEndsAt)
    }
}
