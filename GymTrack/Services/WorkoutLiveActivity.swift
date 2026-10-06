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

    /// `Activity` isn't marked Sendable, but `update` and `end` are async calls
    /// that only message the system, and the Tasks below have always issued
    /// them from off the main actor. The `nonisolated(unsafe)` copies say so to
    /// the strict-concurrency checker; they change nothing at run time.
    private var activity: Activity<WorkoutActivity>?
    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack", category: "LiveActivity")

    /// False when the user has switched Live Activities off for GymTrack (or
    /// system-wide), and under test, where every `ActiveWorkout` a test built
    /// would leave a real activity on the simulator. Everything below is then
    /// a no-op.
    var isAvailable: Bool { !LaunchMode.isTesting && ActivityAuthorizationInfo().areActivitiesEnabled }

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
            nonisolated(unsafe) let card = stray
            Task { await card.end(nil, dismissalPolicy: .immediate) }
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
        nonisolated(unsafe) let card = activity
        Task { await card.update(content) }
    }

    /// Takes the card down. Passing the closing state lets it show the final
    /// numbers for the instant before it disappears.
    func end(with state: WorkoutActivity.ContentState?) {
        let running = Activity<WorkoutActivity>.activities
        activity = nil
        let content = state.map(Self.content(for:))
        for card in running {
            nonisolated(unsafe) let handle = card
            Task { await handle.end(content, dismissalPolicy: .immediate) }
        }
    }

    /// Clears anything left over from a previous run of the app.
    func endAll() {
        end(with: nil)
    }

    // MARK: - Content

    /// The card's state for a session read straight from the store, for the
    /// changes made with no logger on screen. With no rest dates it is the state
    /// a headless change publishes: that side runs no rest timer, and the wrist
    /// is counting the one that matters.
    ///
    /// `ActiveWorkout.activityState` builds through this, handing over its
    /// timer's dates, so the two can't come apart.
    static func state(for session: WorkoutSession,
                      restEndsAt: Date? = nil, restStartedAt: Date? = nil) -> WorkoutActivity.ContentState {
        let position = SessionPosition(session)
        let unit = AppSettings.shared.weightUnit
        return WorkoutActivity.ContentState(
            startedAt: session.startedAt,
            completedSets: position.completedCount,
            totalSets: position.totalCount,
            currentExercise: position.currentGroup?.name ?? "Freestyle",
            currentSetNumber: position.nextSetNumber,
            currentSetTotal: position.currentSetTotal,
            currentTarget: position.nextTargetLabel,
            upNext: position.upNextName,
            restEndsAt: restEndsAt,
            restStartedAt: restStartedAt,
            volumeLabel: "\(unit.fromKg(session.totalVolumeKg).compactVolume) \(unit.short)",
            elapsedLabel: session.duration.durationString,
            elapsedShort: session.duration.shortDurationString
        )
    }

    /// While resting, the rest end doubles as the stale date: when it passes,
    /// the widget flips to "rest done" on its own rather than waiting for the
    /// app to be woken up to say so.
    private static func content(for state: WorkoutActivity.ContentState) -> ActivityContent<WorkoutActivity.ContentState> {
        ActivityContent(state: state, staleDate: state.restEndsAt)
    }
}
