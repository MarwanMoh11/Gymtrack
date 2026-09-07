import SwiftUI
import SwiftData

@main
struct GymTrackApp: App {

    let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self,
                WorkoutSession.self, SetLog.self,
                CustomExerciseRecord.self, BodyMetric.self
            )
        } catch {
            // A store that can't be opened is unrecoverable; falling back to an
            // in-memory container keeps the app usable enough to export/reset.
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self,
                WorkoutSession.self, SetLog.self,
                CustomExerciseRecord.self, BodyMetric.self,
                configurations: config
            )
        }

        UIApplication.shared.isIdleTimerDisabled = AppSettings.shared.keepScreenAwake
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
        .modelContainer(container)
    }
}
