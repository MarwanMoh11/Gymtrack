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

        Self.clearBakedRestOverrides(in: container)

        UIApplication.shared.isIdleTimerDisabled = AppSettings.shared.keepScreenAwake
    }

    /// Plan exercises used to copy the default rest length in at the moment they
    /// were added, which left the Settings value with nothing to govern. Rest is
    /// now a genuine override, so clear those copies once and let every existing
    /// exercise fall back to the default until the user tunes it deliberately.
    private static func clearBakedRestOverrides(in container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: SettingsKey.didClearBakedRest) else { return }
        let context = ModelContext(container)
        guard let items = try? context.fetch(FetchDescriptor<PlanItem>()) else { return }
        for item in items { item.restSeconds = nil }
        try? context.save()
        UserDefaults.standard.set(true, forKey: SettingsKey.didClearBakedRest)
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
