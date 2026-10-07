import Foundation
import Testing
@testable import GymTrack

/// The settings a fresh install starts from, and the rule that decides when a
/// preference actually holds the screen awake.
///
/// The tests once ran with rest auto-start off while every lifter has it on, so
/// the path users take most was the one nothing exercised. `WorkoutBench` and
/// `PersistenceFixtures.pin` set a baseline before each test; these hold that
/// baseline to what `AppSettings` registers, so a test starts where a new
/// install does.
@MainActor @Suite(.serialized)
struct AppSettingsTests {

    /// What `AppSettings` registers, read from the registration domain rather
    /// than through the settings, which return whatever a test or an earlier
    /// run of the host stored.
    private func registered() -> [String: Any] {
        _ = AppSettings.shared
        return UserDefaults.standard.volatileDomain(forName: UserDefaults.registrationDomain)
    }

    // MARK: - A fresh install

    @Test func aFreshInstallWeighsInKilogramsRestsNinetySecondsAndAsksHowASetFelt() {
        let defaults = registered()
        #expect(defaults[SettingsKey.weightUnit] as? String == WeightUnit.kg.rawValue)
        #expect(defaults[SettingsKey.restTimerAutoStart] as? Bool == true)
        #expect(defaults[SettingsKey.defaultRestSeconds] as? Int == 90)
        #expect(defaults[SettingsKey.trackRPE] as? Bool == true)
        #expect(defaults[SettingsKey.watchAutoLaunch] as? Bool == true)
    }

    /// Health writes are left out on purpose: the bench turns them off so that
    /// no test's `finish` reaches Health.
    @Test func theLoggersBenchStartsFromAFreshInstallsSettings() throws {
        let defaults = registered()
        try WorkoutBench.run { _ in
            let settings = AppSettings.shared
            #expect(settings.weightUnit.rawValue == defaults[SettingsKey.weightUnit] as? String)
            #expect(settings.restTimerAutoStart == defaults[SettingsKey.restTimerAutoStart] as? Bool)
            #expect(settings.defaultRestSeconds == defaults[SettingsKey.defaultRestSeconds] as? Int)
            #expect(settings.trackRPE == defaults[SettingsKey.trackRPE] as? Bool)
        }
    }

    @Test func theBackupFixturesStartFromAFreshInstallsSettings() {
        let defaults = registered()
        let pin = PersistenceFixtures.pin()
        defer { pin.restore() }
        let settings = AppSettings.shared
        #expect(settings.weightUnit.rawValue == defaults[SettingsKey.weightUnit] as? String)
        #expect(settings.defaultRestSeconds == defaults[SettingsKey.defaultRestSeconds] as? Int)
    }

    // MARK: - Keeping the screen awake

    /// Every combination: the screen is held only for a lifter who wants it,
    /// has a workout open (minimised counts) and is looking at the app.
    @Test(arguments: [false, true], [false, true])
    func theScreenIsHeldAwakeOnlyDuringAnOpenWorkoutInView(setting: Bool, workoutOpen: Bool) {
        for appIsActive in [false, true] {
            let held = ScreenAwakeRules.holdsScreenAwake(setting: setting, workoutOpen: workoutOpen,
                                                         appIsActive: appIsActive)
            #expect(held == (setting && workoutOpen && appIsActive), "app active: \(appIsActive)")
        }
    }

    /// The case the review found: the setting is on by default, so a phone
    /// left open on Progress or Today never locked, draining the battery and
    /// leaving the last screen readable.
    @Test func withTheSettingOnThePhoneStillLocksWithNoWorkoutOrInTheBackground() {
        #expect(!ScreenAwakeRules.holdsScreenAwake(setting: true, workoutOpen: false, appIsActive: true))
        #expect(!ScreenAwakeRules.holdsScreenAwake(setting: true, workoutOpen: true, appIsActive: false))
    }
}
