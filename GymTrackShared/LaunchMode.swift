import Foundation

/// Whether this process is running for a test rather than for the lifter.
///
/// A unit-test bundle is hosted inside the real app, so the app's launch runs
/// before the first test: it would open the lifter's store, load his machine
/// scales into every progression suggestion, and bring up the watch link. A UI
/// test launches the app fresh and needs it empty and free of system alerts, or
/// a "Allow Notifications" prompt sits on top of the logger and swallows taps.
/// Both cases are decided here, once, so the production path can stay exactly
/// as it was whenever neither is true.
enum LaunchMode {
    /// Passed by `GymTrackUITests` when it launches the app.
    static let uiTestingArgument = "-GTUITesting"

    static let isUITesting = ProcessInfo.processInfo.arguments.contains(uiTestingArgument)

    /// XCTest sets the configuration path in the host's environment; the class
    /// check covers a runner that does not.
    static let isUnitTestHost = !isUITesting
        && (ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil)

    static var isTesting: Bool { isUITesting || isUnitTestHost }
}
