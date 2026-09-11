import SwiftUI

@main
struct GymTrackWatchApp: App {

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
