import ActivityKit
import Foundation

/// The contract between the app and the Live Activity that shows up on the
/// Lock Screen and in the Dynamic Island.
///
/// Compiled into both targets. The widget never reaches into SwiftData — every
/// string it draws is prepared here by the app, which is also why the
/// unit-dependent values (weights, volume) arrive pre-formatted: the extension
/// has no access to the user's kg/lb preference.
struct WorkoutActivity: ActivityAttributes {

    /// Everything that changes while the session runs.
    struct ContentState: Codable, Hashable {

        /// Session start. The widget derives the running clock from this with
        /// `Text(timerInterval:)`, so the minutes tick over on their own — we
        /// only push when something actually happens.
        var startedAt: Date

        var completedSets: Int
        var totalSets: Int

        /// The exercise the logger is sitting on.
        var currentExercise: String
        /// 1-based position of the next unlogged set within that exercise.
        var currentSetNumber: Int
        var currentSetTotal: Int
        /// What's prescribed for it — "60 kg × 8–12", "45s", "12 reps".
        var currentTarget: String
        /// The exercise after this one. Empty on the last one.
        var upNext: String

        /// Set for the length of a rest. The widget counts it down itself.
        var restEndsAt: Date?
        var restStartedAt: Date?

        /// Pre-formatted in the user's unit — "4.2k kg".
        var volumeLabel: String

        /// "48m" / "1h 12m", stamped at push time. Shown in place of the live
        /// session clock while a rest countdown is running: WidgetKit will only
        /// animate one timer per activity, and between sets the countdown is
        /// the one that matters.
        var elapsedLabel: String

        // MARK: Derived

        var isResting: Bool { restEndsAt != nil }

        var progress: Double {
            totalSets > 0 ? min(1, Double(completedSets) / Double(totalSets)) : 0
        }

        var setsRemaining: Int { max(0, totalSets - completedSets) }

        /// How far through the current rest we are, 0 → 1.
        var restProgress: Double {
            guard let restEndsAt, let restStartedAt else { return 0 }
            let total = restEndsAt.timeIntervalSince(restStartedAt)
            guard total > 0 else { return 1 }
            return min(1, max(0, -restEndsAt.timeIntervalSinceNow / total))
        }

        /// One line describing where the lifter is, used wherever there's room
        /// for a sentence rather than a stack of numbers.
        var statusLine: String {
            if isResting { return "Then \(currentExercise) · set \(currentSetNumber)" }
            if completedSets >= totalSets && totalSets > 0 { return "Every set logged" }
            return "Set \(currentSetNumber) of \(currentSetTotal) · \(currentTarget)"
        }
    }

    /// Fixed for the life of the session.
    var sessionID: UUID
    var sessionTitle: String
    var planName: String
}

extension WorkoutActivity {
    /// Deep link the Live Activity opens — lands straight back in the logger.
    static let deepLink = URL(string: "gymtrack://session")!
}
