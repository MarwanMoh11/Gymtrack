import XCTest

/// Moving around the app: the four tabs, the Library search and Settings.
///
/// These are the screens a lifter passes through between sets, and each is
/// built from a different view stack, so a tab that opens blank or a search
/// field that stops filtering is easy to ship without noticing. The tests
/// start from an onboarded, empty install, so they hold on any weekday. Settings
/// is only opened, never exported from: the share sheet belongs to the system
/// and is not stable to drive. There is no legacy `Tests/*.swift` counterpart.
final class NavigationUITests: GymTrackUITestCase {

    private let exerciseCount = NSPredicate(format: "label MATCHES %@", "^[0-9]+ exercises?$")

    /// How long the first thing on the Library may take to appear after its
    /// tab is tapped.
    ///
    /// The Library is the slowest tab to open in the simulator, since it lays
    /// out the catalog's list, the search field and the filter menus at once.
    /// On an idle CI runner it appears about four and a half seconds after the
    /// tap, up to a second behind the other tabs; the app's own share is half
    /// a second, and the rest is the simulator and XCUITest. That leaves the
    /// usual ten seconds little room on a busy runner: in the two failed runs
    /// of #34 the simulator took 45 seconds to launch and 36 for one
    /// accessibility snapshot, and only the Library missed its wait. A minute
    /// outlasts such a snapshot, and a Library that never opens still fails.
    private let libraryFirstOpen: TimeInterval = 60

    func testEveryTabOpensItsScreen() throws {
        app = launchApp(onboarded: true)

        require(app.navigationBars["Today"], "the Today title")

        tap(app.tabBars.buttons["Plan"], "the Plan tab")
        require(app.navigationBars["Plan"], "the Plan title")

        tap(app.tabBars.buttons["Library"], "the Library tab")
        require(app.navigationBars["Library"], "the Library title", timeout: libraryFirstOpen)

        tap(app.tabBars.buttons["Progress"], "the Progress tab")
        require(app.navigationBars["Progress"], "the Progress title")

        tap(app.tabBars.buttons["Today"], "the Today tab")
        require(app.navigationBars["Today"], "the Today title after coming back")
    }

    /// A query has to leave fewer exercises than the whole library, and the
    /// matching one has to be among them.
    func testLibrarySearchNarrowsTheList() throws {
        app = launchApp(onboarded: true)
        tap(app.tabBars.buttons["Library"], "the Library tab")

        let count = require(app.staticTexts.matching(exerciseCount).firstMatch, "the exercise count",
                            timeout: libraryFirstOpen)
        let everything = count.label

        let search = require(app.searchFields.firstMatch, "the search field")
        search.tap()
        search.typeText("Barbell Back Squat")

        require(button(labelContains: "Barbell Back Squat"), "the matching exercise")
        let narrowed = require(app.staticTexts.matching(exerciseCount).firstMatch, "the narrowed count")
        XCTAssertNotEqual(narrowed.label, everything, "the search left the whole library listed")
    }

    /// A name the library does not have says so, and offers to add it, rather
    /// than showing an empty page.
    func testLibrarySearchWithNoMatchSaysSo() throws {
        app = launchApp(onboarded: true)
        tap(app.tabBars.buttons["Library"], "the Library tab")

        let search = require(app.searchFields.firstMatch, "the search field", timeout: libraryFirstOpen)
        search.tap()
        search.typeText("Zzqxj Machine")

        require(app.staticTexts["Nothing matches"], "the no-match message")
    }

    func testSettingsOpensFromTodayAndListsTheBackup() throws {
        app = launchApp(onboarded: true)

        tap(app.buttons["Settings"], "the Settings button")
        require(app.navigationBars["Settings"], "the Settings title")

        // The backup row is far down a list that builds only what is near the
        // screen, so it does not exist until it has been scrolled to.
        let backup = app.buttons["Export a backup"]
        scrollUntilVisible(backup, in: app)
        require(backup, "the Export a backup row")
    }
}
