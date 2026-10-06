import XCTest

/// How every UI test starts the app, and the small waiting helpers they share.
///
/// `-GTUITesting` is what makes a launch safe to repeat: the app opens an
/// in-memory store, wipes its own defaults and skips the notification prompt
/// that would otherwise sit on top of the logger and swallow taps. Language and
/// locale are pinned so that a runner set to another region still reads
/// "Pounds" and "0/3 sets" the same way.
///
/// Every wait here has a timeout and no test sleeps: a flow that is slow on a
/// loaded CI runner gets ten seconds per step, and a flow that is broken fails
/// at the step that broke rather than at the end.

/// Identifiers the app sets for the few controls that have no stable visible
/// text. Everything else the tests reach through its on-screen words.
enum AccessibilityID {
    static let startWorkout = "today.startWorkout"
    static let logSet = "session.logSet"
    static let progress = "session.progress"
    static let finish = "session.finish"
}

/// Launches the app fresh. With `onboarded` the lifter lands on Today with no
/// plan and no history; without it the first-run screens come up.
///
/// `-settings.hasOnboarded YES` goes through the argument domain, which
/// `@AppStorage` reads, so no UI is needed to skip the welcome flow.
func launchApp(onboarded: Bool, extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    var arguments = ["-GTUITesting", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
    if onboarded {
        arguments += ["-settings.hasOnboarded", "YES"]
    }
    app.launchArguments = arguments + extra
    app.launch()
    return app
}

/// Base class: stops a test at its first failed step, because every later step
/// would only be a tap on a screen that never appeared.
class GymTrackUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app = nil
    }

    /// Launches as a first run and waits for the welcome step.
    ///
    /// The one way this fails without a bug in the app is a simulator whose
    /// device-level preferences already hold `settings.hasOnboarded`, for
    /// example from an earlier `simctl spawn ... defaults write` made to skip
    /// the welcome flow. The app wipes its own container's defaults at launch
    /// but cannot reach that file, so the test says so rather than reporting a
    /// missing button.
    func launchFirstRun() {
        app = launchApp(onboarded: false)
        if !app.buttons["Continue"].waitForExistence(timeout: 10), app.tabBars.firstMatch.exists {
            XCTFail("The app skipped onboarding. This simulator's device-level preferences hold "
                    + "settings.hasOnboarded; clear them with `xcrun simctl spawn <udid> defaults "
                    + "delete com.marwanmohamed.gymtrack settings.hasOnboarded`.")
        }
    }

    /// Waits for `element` and fails the test, naming it, if it never shows.
    @discardableResult
    func require(_ element: XCUIElement, _ name: String,
                 timeout: TimeInterval = 10,
                 file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout),
                      "\(name) never appeared", file: file, line: line)
        return element
    }

    /// Waits for `element` and taps it.
    func tap(_ element: XCUIElement, _ name: String,
             file: StaticString = #filePath, line: UInt = #line) {
        require(element, name, file: file, line: line).tap()
    }

    /// Waits until `element`'s label equals `text`. Used for the "x/y sets"
    /// counter, which changes a beat after the tap that caused it.
    func expectLabel(_ element: XCUIElement, _ text: String,
                     file: StaticString = #filePath, line: UInt = #line) {
        let matches = NSPredicate(format: "label == %@", text)
        let wait = XCTNSPredicateExpectation(predicate: matches, object: element)
        let result = XCTWaiter().wait(for: [wait], timeout: 10)
        XCTAssertEqual(result, .completed,
                       "expected label \"\(text)\", found \"\(element.label)\"",
                       file: file, line: line)
    }

    /// Any element, whatever its type, whose label starts with `prefix`. A
    /// combined SwiftUI control (the dock, a stepper) can report as a button or
    /// as a plain element depending on the OS, so the type is not part of the
    /// question.
    func element(labelBeginsWith prefix: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", prefix))
            .firstMatch
    }

    func element(labelContains text: String) -> XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    /// A button whose label contains `text`.
    func button(labelContains text: String) -> XCUIElement {
        app.buttons
            .matching(NSPredicate(format: "label CONTAINS %@", text))
            .firstMatch
    }

    /// Swipes up a bounded number of times until `element` is on screen. A
    /// grouped list builds only the rows near the viewport, so a row far down
    /// does not exist at all until it has been scrolled to.
    func scrollUntilVisible(_ element: XCUIElement, in container: XCUIElement,
                            maxSwipes: Int = 8,
                            file: StaticString = #filePath, line: UInt = #line) {
        var swipes = 0
        while !(element.exists && element.isHittable) && swipes < maxSwipes {
            container.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(element.exists, "scrolling never reached the element",
                      file: file, line: line)
    }
}
