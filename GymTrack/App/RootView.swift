import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case today, plan, library, progress
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Query private var customExercises: [CustomExerciseRecord]
    @Query private var sessions: [WorkoutSession]

    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false

    @State private var selectedTab: AppTab = .today
    @State private var activeWorkout: ActiveWorkout?
    @State private var showingSummary: WorkoutSession?

    var body: some View {
        Group {
            if hasOnboarded {
                mainInterface
            } else {
                OnboardingView { hasOnboarded = true }
            }
        }
        .gtScreenBackground()
        .task {
            syncCustomExercises()
            resumeUnfinishedSession()
            seedSampleDataIfRequested()
        }
        .onChange(of: hasOnboarded) { _, done in
            if done { seedSampleDataIfRequested() }
        }
        .onChange(of: customExercises.count) { _, _ in syncCustomExercises() }
    }

    private var mainInterface: some View {
        TabView(selection: $selectedTab) {
            TodayView(activeWorkout: $activeWorkout)
                .tabItem { Label("Today", systemImage: "bolt.horizontal.fill") }
                .tag(AppTab.today)

            PlansView()
                .tabItem { Label("Plan", systemImage: "list.bullet.rectangle.portrait.fill") }
                .tag(AppTab.plan)

            LibraryView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(AppTab.library)

            ProgressDashboardView()
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                .tag(AppTab.progress)
        }
        .fullScreenCover(isPresented: Binding(
            get: { activeWorkout != nil },
            set: { if !$0 { activeWorkout = nil } }
        )) {
            if let workout = activeWorkout {
                ActiveWorkoutView(workout: workout) { finished in
                    activeWorkout = nil
                    if let finished { showingSummary = finished }
                }
            }
        }
        .sheet(item: $showingSummary) { session in
            SessionSummaryView(session: session)
        }
    }

    private func seedSampleDataIfRequested() {
        #if DEBUG
        if SampleData.isRequestedAtLaunch, sessions.isEmpty {
            SampleData.generate(context: context)
        }
        #endif
    }

    /// Mirrors user-created exercises into the shared catalog so the rest of the
    /// app can resolve them by ID like any bundled exercise.
    private func syncCustomExercises() {
        ExerciseCatalog.shared.setCustom(customExercises.map(\.asCatalogExercise))
    }

    /// Picks up a session left open by a crash or a force-quit.
    private func resumeUnfinishedSession() {
        guard activeWorkout == nil,
              let open = sessions.first(where: { $0.isActive })
        else { return }

        // Anything older than 12 hours is stale — close it out rather than
        // dropping the user back into yesterday's workout.
        if open.startedAt.timeIntervalSinceNow < -12 * 3600 {
            if open.completedSets.isEmpty {
                context.delete(open)
            } else {
                open.endedAt = open.completedSets.compactMap(\.completedAt).max() ?? open.startedAt
            }
            try? context.save()
            return
        }

        activeWorkout = ActiveWorkout(session: open, context: context, history: sessions)
    }
}
