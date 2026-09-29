import HealthKit
import SwiftUI
import WatchKit

@main
struct GymTrackWatchApp: App {

    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var connector = WatchConnector.shared
    @State private var recorder = WatchWorkoutRecorder.shared

    init() {
        WatchConnector.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView(connector: connector, recorder: recorder)
                .tint(Theme.accent)
        }
    }
}

/// Receives the two launches watchOS makes on a workout's behalf, neither of
/// which reaches a SwiftUI view.
///
/// After a crash mid-workout the system keeps the workout session running and
/// relaunches the app to take it back; unanswered, the recorder built a second
/// one beside it. When the phone starts a session it launches this app with a
/// workout configuration; unanswered, recording waited for the wrist to come
/// up, and the first sets had no heart rate.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    func handleActiveWorkoutRecovery() {
        Task { await WatchWorkoutRecorder.shared.recoverActiveWorkout() }
    }

    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchWorkoutRecorder.shared.startWhenPhoneSessionArrives()
    }
}
