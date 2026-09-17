import SwiftUI
import SwiftData

@main
struct GymTrackApp: App {

    let container: ModelContainer

    /// Where the database lives, pinned rather than left to the default.
    ///
    /// SwiftData follows `NSPersistentContainer.defaultDirectoryURL()`, which
    /// silently moves to the *App Group* container the moment an app has the
    /// app-groups entitlement. Adding that entitlement for the widgets would
    /// therefore have pointed the app at a brand-new empty store and left every
    /// existing session sitting unread in the old location — the app would look
    /// like it had lost your training history. So the path is stated outright,
    /// and it is the one the app has always used.
    private static var storeURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }

    init() {
        do {
            // Core Data creates this directory itself, but not on every OS
            // version, and a missing one fails the open.
            try? FileManager.default.createDirectory(
                at: .applicationSupportDirectory, withIntermediateDirectories: true
            )
            container = try ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self,
                WorkoutSession.self, SetLog.self,
                CustomExerciseRecord.self, BodyMetric.self,
                ExerciseLoadPreference.self,
                configurations: ModelConfiguration(url: Self.storeURL)
            )
        } catch {
            // A store that can't be opened is unrecoverable; falling back to an
            // in-memory container keeps the app usable enough to export/reset.
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            container = try! ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self,
                WorkoutSession.self, SetLog.self,
                CustomExerciseRecord.self, BodyMetric.self,
                ExerciseLoadPreference.self,
                configurations: config
            )
        }

        Self.clearBakedRestOverrides(in: container)

        // How each machine is marked is read from everywhere — the logger, a
        // progression suggestion, the watch mirror — so the book is loaded once
        // here rather than fetched per screen.
        LoadScaleBook.shared.configure(container: container)

        // Before anything else can arrive: iOS wakes a terminated app in the
        // background to hand it a watch message, and the link has to be up and
        // able to apply it without a view hierarchy.
        WatchCommandCenter.shared.configure(container: container)

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
