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
    static var title: LocalizedStringResource = "Start Today's Workout"
    static var description = IntentDescription(
        "Starts the session your routine has scheduled for today. On a rest day, or with no routine set up, it starts a freestyle session instead."
    )
    /// The app has to come forward: this finishes in the logger, with the first
    /// set already loaded.
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedStore.request(.startToday)
        return .result()
    }
}

@available(iOS 17.0, *)
struct StartFreestyleWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Start a Freestyle Workout"
    static var description = IntentDescription(
        "Starts an empty session you fill in as you go, whatever your routine says about today."
    )
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedStore.request(.startFreestyle)
        return .result()
    }
}

@available(iOS 17.0, *)
struct OpenWorkoutIntent: AppIntent {
    static var title: LocalizedStringResource = "Open My Workout"
    static var description = IntentDescription(
        "Opens the session you have running, on the set you're about to do."
    )
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        SharedStore.request(.openSession)
        return .result()
    }
}
#endif
