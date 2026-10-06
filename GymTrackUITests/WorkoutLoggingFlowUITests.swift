import XCTest

/// The workout logger end to end: start, log, undo, minimise, finish, and the
/// unit the lifter chose showing up where the weight is typed.
///
/// The logger is used mid-set with a bar in the lifter's hands, so a broken Log
/// button or a minimise that loses the session is the failure that matters most
/// and the one a unit test cannot see. "Undo" is checked because an undone set
/// is not data: the counter has to drop back, not just the row change.
///
/// The freestyle flows start from a launch with no plan, so they pass on any
/// weekday. The planned-day flow offers a session by whichever Today card the
/// weekday produces, for the same reason. There is no legacy `Tests/*.swift`
/// counterpart.
final class WorkoutLoggingFlowUITests: GymTrackUITestCase {

    private let benchPress = "Barbell Bench Press"

    // MARK: - Freestyle

    /// Log two sets, undo one, finish: the counter must follow each step, and a
    /// finished session with a set in it is what Today then offers to view.
    ///
    /// The undo takes the second set rather than the only one: undoing the only
    /// logged set crashes the app today (issue #2), and a crash cannot be
    /// wrapped as a known issue because XCTest raises it outside the wrapper.
    func testFreestyleSetsCanBeLoggedUndoneAndTheWorkoutFinished() throws {
        app = launchApp(onboarded: true)

        tap(app.buttons["Start a freestyle session"], "Start a freestyle session")
        addExercise(named: benchPress)

        let progress = require(app.staticTexts[AccessibilityID.progress], "the set counter")
        expectLabel(progress, "0/3 sets")

        // A fresh install weighs in kilograms, which also shows that nothing a
        // previous run chose was left behind.
        require(element(labelBeginsWith: "kg"), "the kg caption under the weight field")

        tap(app.buttons[AccessibilityID.logSet], "Log set")
        expectLabel(progress, "1/3 sets")

        tap(app.buttons[AccessibilityID.logSet], "Log set, the second time")
        expectLabel(progress, "2/3 sets")

        let undo = app.buttons.matching(NSPredicate(format: "label == %@", "Undo this set"))
        require(undo.firstMatch, "Undo this set")
        undo.element(boundBy: undo.count - 1).tap()
        expectLabel(progress, "1/3 sets")

        tap(app.buttons[AccessibilityID.finish], "Finish")
        tap(app.alerts.buttons["Finish workout"], "the Finish workout confirmation")
        tap(app.buttons["Done"], "Done on the summary")

        require(app.buttons["View workout"], "View workout on Today")
    }

    /// The unit picked on the second onboarding screen has to reach the weight
    /// field, or a lifter who chose pounds logs a number he reads as kilos.
    func testPoundsChosenInOnboardingAreShownInTheLogger() throws {
        launchFirstRun()

        tap(app.buttons["Continue"], "Continue on the welcome step")
        tap(button(labelContains: "Pounds"), "the Pounds option")
        tap(app.buttons["Continue"], "Continue on the unit step")
        tap(button(labelContains: "Start from blank"), "Start from blank")
        tap(app.buttons["Start training"], "Start training")

        tap(app.buttons["Freestyle workout"], "Freestyle workout")
        addExercise(named: benchPress)
        require(app.buttons[AccessibilityID.logSet], "Log set")

        // The weight field's caption reads "lb · 5": the unit, then what one
        // tap of + is worth.
        require(element(labelBeginsWith: "lb"), "the lb caption under the weight field")
        XCTAssertFalse(element(labelBeginsWith: "kg").exists,
                       "a kg caption is still on screen after choosing pounds")
    }

    // MARK: - Planned day

    /// A session started from the plan opens the logger, can be put away to the
    /// dock without losing anything, and comes back from Today.
    func testPlannedDayCanBeMinimisedToTheDockAndResumed() throws {
        launchFirstRun()

        tap(app.buttons["Continue"], "Continue on the welcome step")
        tap(app.buttons["Continue"], "Continue on the unit step")
        tap(app.buttons["Start training"], "Start training with the default routine")

        // Which card Today shows depends on the weekday, and both carry a
        // button that opens the same list of days.
        let picker = app.buttons
            .matching(NSPredicate(format: "label IN %@", ["Train something else", "Pick a session"]))
            .firstMatch
        tap(picker, "the day picker button")

        tap(button(labelContains: "exercises ·"), "the first day in the list")
        require(app.buttons[AccessibilityID.logSet], "the logger's Log set")

        tap(app.buttons["Minimise workout"], "Minimise workout")
        require(element(labelContains: "workout in progress"), "the dock")

        tap(app.buttons["Back to workout"], "Back to workout")
        require(app.buttons[AccessibilityID.logSet], "the logger after coming back")
    }

    // MARK: - Steps

    /// Opens the picker from the logger's empty state, finds an exercise by
    /// name and taps it. The first match is used because the library ranks the
    /// exact name ahead of its variations, and any of them logs the same way.
    private func addExercise(named name: String) {
        // First match: the empty card and the list's footer both carry an
        // "Add exercise" button, and either one opens the same picker.
        tap(app.buttons["Add exercise"].firstMatch, "Add exercise")

        let search = require(app.searchFields.firstMatch, "the exercise search field")
        search.tap()
        search.typeText(name)

        let result = app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", name))
            .firstMatch
        tap(result, "the \(name) result")
    }
}
