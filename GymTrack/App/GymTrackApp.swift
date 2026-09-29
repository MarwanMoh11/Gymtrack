import SwiftUI
import SwiftData
import SQLite3

@main
struct GymTrackApp: App {

    @State private var storeState: StoreState

    /// A failed open cannot borrow a temporary database: the logger would then
    /// appear to save workouts that disappear as soon as the app restarts.
    private enum StoreState {
        case ready(ModelContainer)
        case failed(String)
    }

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
        // Before the store is opened, because opening it is what drops the
        // column these rows are identified by.
        Self.dropWarmupSets()

        let initialState = Self.openStore()
        _storeState = State(initialValue: initialState)
        if case .ready(let container) = initialState {
            Self.configureServices(container: container)
        }
    }

    private static func openStore() -> StoreState {
        do {
            // Core Data creates this directory itself, but not on every OS
            // version, and a missing one fails the open.
            try FileManager.default.createDirectory(
                at: .applicationSupportDirectory, withIntermediateDirectories: true
            )
            let container = try ModelContainer(
                for: Plan.self, PlanDay.self, PlanItem.self,
                WorkoutSession.self, SetLog.self, ExerciseNote.self,
                CustomExerciseRecord.self, BodyMetric.self,
                ExerciseLoadPreference.self, HiddenExerciseRecord.self,
                configurations: ModelConfiguration(url: Self.storeURL)
            )
            return .ready(container)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    private static func configureServices(container: ModelContainer) {
        clearBakedRestOverrides(in: container)

        // Here and not only in RootView, which never runs on a background
        // launch. A watch command that starts a workout reads each slot's
        // tracking and load scale from the catalog, and an unloaded custom
        // exercise would be built into weight × reps rows it can never leave.
        ExerciseCatalog.shared.loadLibrary(from: ModelContext(container))

        // How each machine is marked is read from everywhere — the logger, a
        // progression suggestion, the watch mirror — so the book is loaded once
        // here rather than fetched per screen.
        LoadScaleBook.shared.configure(container: container)
        HealthKitService.shared.configure(container: container)

        // Before anything else can arrive: iOS wakes a terminated app in the
        // background to hand it a watch message, and the link has to be up and
        // able to apply it without a view hierarchy.
        WatchCommandCenter.shared.configure(container: container)
    }

    private func retryStore() {
        let retriedState = Self.openStore()
        if case .ready(let container) = retriedState {
            Self.configureServices(container: container)
        }
        storeState = retriedState
    }

    /// Sets logged as warm-ups, from when the app had a warm-up feature.
    ///
    /// The flag they were marked with is gone from the model, so opening the
    /// store drops the column — and every ramp rung left behind would come back
    /// as an ordinary working set. That isn't a cosmetic difference: a 40 kg
    /// rung would become "set 1" of the exercise, and next session's suggestion
    /// would read it as a collapse and offer a deload off a warm-up.
    ///
    /// They are deleted rather than kept anywhere. A warm-up isn't a result —
    /// it's preparation, the same three rungs under whatever you're about to
    /// lift, derivable from the working weight by anything that ever wants it.
    /// Keeping rows that mean nothing, some of which are only the residue of a
    /// mis-tap on a one-tap button, would put noise in a record whose whole
    /// value is that everything in it actually happened.
    ///
    /// It has to go through SQLite rather than SwiftData, because by the time
    /// SwiftData can be asked, the column no longer exists. Every step may fail
    /// quietly: a store already migrated, or one that never had the column, has
    /// nothing to do here.
    private static func dropWarmupSets() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: SettingsKey.didDropWarmupSets) else { return }
        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            // No store at all: a fresh install, which never had warm-ups.
            defaults.set(true, forKey: SettingsKey.didDropWarmupSets)
            return
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return
        }
        defer { sqlite3_close(db) }

        // A store from before the column existed answers this with an error,
        // which is the signal to leave it alone rather than a failure.
        guard sqlite3_exec(db, "DELETE FROM ZSETLOG WHERE ZISWARMUP = 1;", nil, nil, nil) == SQLITE_OK
        else { return }
        defaults.set(true, forKey: SettingsKey.didDropWarmupSets)
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
            Group {
                switch storeState {
                case .ready(let container):
                    RootView()
                        .modelContainer(container)
                case .failed(let detail):
                    StoreRecoveryView(detail: detail, onRetry: retryStore)
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
    }
}

/// Keeps every data-writing surface closed until the original store opens.
private struct StoreRecoveryView: View {
    let detail: String
    let onRetry: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(Theme.warning)

                Text("Training data unavailable")
                    .font(Theme.rounded(30, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text("GymTrack couldn't open its saved data. Workout logging is paused so new sets won't appear saved and then disappear after a restart.")
                    .foregroundStyle(Theme.textSecondary)

                Text("The app has not reset your training database. Check that your iPhone has free storage, then try again. Keep GymTrack installed while you recover the data.")
                    .foregroundStyle(Theme.textSecondary)

                Button("Try again", action: onRetry)
                    .buttonStyle(PrimaryButtonStyle())

                Text("Error details: \(detail)")
                    .font(Theme.rounded(12))
                    .foregroundStyle(Theme.textTertiary)
                    .textSelection(.enabled)
            }
            .padding(24)
            .frame(maxWidth: 520, alignment: .leading)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .gtScreenBackground()
    }
}
