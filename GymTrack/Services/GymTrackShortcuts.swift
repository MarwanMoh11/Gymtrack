import AppIntents

/// The phrases Siri answers to, and the rows that appear in Shortcuts and in
/// Spotlight without anyone having to build anything.
///
/// Lives in the app target rather than in the shared folder on purpose: the
/// provider is discovered once per bundle, and a second copy inside the widget
/// extension would offer the same three shortcuts twice.
///
/// Every phrase has to contain the app name — that's the rule Siri matches on —
/// so they're written to read like something a person would actually say on the
/// way into a gym.
@available(iOS 17.0, *)
struct GymTrackShortcuts: AppShortcutsProvider {

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartTodayWorkoutIntent(),
            phrases: [
                "Start my \(.applicationName) workout",
                "Start today's workout in \(.applicationName)",
                "Begin my \(.applicationName) session",
            ],
            shortTitle: "Start Today's Workout",
            systemImageName: "bolt.horizontal.fill"
        )
        AppShortcut(
            intent: StartFreestyleWorkoutIntent(),
            phrases: [
                "Start a freestyle workout in \(.applicationName)",
                "Start an empty \(.applicationName) session",
            ],
            shortTitle: "Freestyle Workout",
            systemImageName: "figure.strengthtraining.traditional"
        )
        AppShortcut(
            intent: OpenWorkoutIntent(),
            phrases: [
                "Open my \(.applicationName) workout",
                "Show my set in \(.applicationName)",
            ],
            shortTitle: "Open My Workout",
            systemImageName: "list.bullet.rectangle.portrait.fill"
        )
    }
}
