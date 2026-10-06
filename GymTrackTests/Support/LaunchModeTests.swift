import Testing
@testable import GymTrack

/// The host must know it is hosting tests, or the app's launch opens the
/// lifter's on-disk store and binds every singleton to it before a test runs.
struct LaunchModeTests {
    @Test func hostKnowsItIsUnderTest() {
        #expect(LaunchMode.isUnitTestHost)
        #expect(!LaunchMode.isUITesting)
    }
}
