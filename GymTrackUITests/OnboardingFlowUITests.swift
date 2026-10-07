import XCTest

/// The first-run flow: welcome, unit, routine, then Today.
///
/// A lifter who cannot get past these three screens never logs anything, and
/// the screens are paged by a swipe-style `TabView`, which is exactly the kind
/// of control that breaks quietly when its footer button stops advancing. The
/// tests walk it with taps only. Nothing here is typed, so a runner's keyboard
/// settings cannot change the result. Unit tests cannot see a screen.
final class OnboardingFlowUITests: GymTrackUITestCase {

    /// The default path with a template chosen: the routine that comes out of
    /// it is the one the lifter picked, not the pre-selected one.
    func testChoosingAUnitAndATemplateEndsOnToday() throws {
        launchFirstRun()

        tap(app.buttons["Continue"], "Continue on the welcome step")
        tap(button(labelContains: "Pounds"), "the Pounds option")
        tap(app.buttons["Continue"], "Continue on the unit step")
        tap(button(labelContains: "Full Body"), "the Full Body template")
        tap(app.buttons["Start training"], "Start training")

        require(app.tabBars.buttons["Today"], "the Today tab")
        require(app.navigationBars["Today"], "the Today title")

        // The pre-selected template was Upper / Lower. Finding the chosen one
        // on the Plan tab shows the tap on the row took, not just the finish.
        tap(app.tabBars.buttons["Plan"], "the Plan tab")
        require(element(labelContains: "Full Body"), "the chosen routine on the Plan tab")
    }

    /// Starting blank gives an empty routine, for someone who already has a
    /// program and would only have a template to delete. Today then says so
    /// instead of offering a session that nobody scheduled.
    func testStartingBlankLeavesAnEmptyRoutine() throws {
        launchFirstRun()

        tap(app.buttons["Continue"], "Continue on the welcome step")
        tap(app.buttons["Continue"], "Continue on the unit step")
        tap(button(labelContains: "Start from blank"), "Start from blank")
        tap(app.buttons["Start training"], "Start training")

        require(app.navigationBars["Today"], "the Today title")
        require(app.staticTexts["Build your routine"], "the empty-routine card")
        require(app.buttons["Freestyle workout"], "the freestyle button")
    }
}
