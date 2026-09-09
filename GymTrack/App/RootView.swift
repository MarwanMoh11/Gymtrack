import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case today, plan, library, progress
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var customExercises: [CustomExerciseRecord]
    @Query private var sessions: [WorkoutSession]

    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    /// Remembers that the user chose to put the session away, so relaunching
    /// doesn't drop them back into the logger they deliberately left.
    @AppStorage(SettingsKey.sessionMinimised) private var sessionMinimised = false

    @State private var selectedTab: AppTab = .today
    @State private var activeWorkout: ActiveWorkout?
    @State private var isSessionExpanded = false
    @State private var showingSummary: WorkoutSession?
    @State private var confirmingDockFinish = false
    @State private var confirmingDockDiscard = false

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
        // Derived rather than set at each call site — the session can be put
        // away or brought back from the logger, the dock, the Today card and a
        // Live Activity tap, and every one of them has to agree.
        .onChange(of: isSessionMinimised) { _, minimised in
            sessionMinimised = minimised
        }
        // Restamp the card on the way out — that's the moment it becomes the
        // thing the user is looking at — and on the way back in, since the rest
        // timer can't tick while the app is suspended.
        .onChange(of: scenePhase) { _, _ in
            activeWorkout?.pushLiveActivity()
        }
        .onOpenURL { url in
            if url.host == "session" { expandSession() }
        }
    }

    private var mainInterface: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                docked(TodayView(activeWorkout: $activeWorkout,
                                 isSessionExpanded: $isSessionExpanded))
                    .tabItem { Label("Today", systemImage: "bolt.horizontal.fill") }
                    .tag(AppTab.today)

                docked(PlansView())
                    .tabItem { Label("Plan", systemImage: "list.bullet.rectangle.portrait.fill") }
                    .tag(AppTab.plan)

                docked(LibraryView())
                    .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                    .tag(AppTab.library)

                docked(ProgressDashboardView())
                    .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
                    .tag(AppTab.progress)
            }

            if let workout = activeWorkout, isSessionExpanded {
                ActiveWorkoutView(
                    workout: workout,
                    onMinimise: minimiseSession,
                    onClose: { finished in
                        closeSession()
                        if let finished { showingSummary = finished }
                    }
                )
                .transition(.move(edge: .bottom))
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: isSessionExpanded)
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: activeWorkout == nil)
        .sheet(item: $showingSummary) { session in
            SessionSummaryView(session: session)
        }
        // Both of these end the session from a context menu, well away from the
        // logger — neither should be one stray tap.
        .alert("Finish this workout?", isPresented: $confirmingDockFinish) {
            Button("Keep going", role: .cancel) {}
            Button("Finish workout") { finishSession() }
        } message: {
            Text(dockFinishMessage)
        }
        .alert("Discard this workout?", isPresented: $confirmingDockDiscard) {
            Button("Keep the workout", role: .cancel) {}
            Button("Discard", role: .destructive) { discardSession() }
        } message: {
            Text("Every set logged in this session is deleted. Leaving it minimised costs nothing.")
        }
    }

    private var dockFinishMessage: String {
        guard let workout = activeWorkout else { return "" }
        let remaining = workout.totalCount - workout.completedCount
        return remaining > 0
            ? "\(remaining) set\(remaining == 1 ? "" : "s") not logged — they'll be dropped from the record."
            : "Every set logged. Nice work."
    }

    // MARK: - Session presentation

    /// Puts the dock bar inside each tab so it rides above the tab bar rather
    /// than covering it.
    private func docked<V: View>(_ tab: V) -> some View {
        tab.sessionDock(
            activeWorkout,
            isExpanded: isSessionExpanded,
            onResume: expandSession,
            onFinish: { confirmingDockFinish = true },
            onDiscard: { confirmingDockDiscard = true }
        )
    }

    /// A session that exists but isn't on screen.
    private var isSessionMinimised: Bool {
        activeWorkout != nil && !isSessionExpanded
    }

    private func expandSession() {
        guard activeWorkout != nil else { return }
        isSessionExpanded = true
    }

    private func minimiseSession() {
        isSessionExpanded = false
    }

    private func closeSession() {
        isSessionExpanded = false
        activeWorkout = nil
        sessionMinimised = false
    }

    private func finishSession() {
        guard let workout = activeWorkout else { return }
        let session = workout.session
        workout.finish()
        closeSession()
        showingSummary = session
    }

    private func discardSession() {
        activeWorkout?.discard()
        closeSession()
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
        else {
            // Nothing to come back to — make sure no Live Activity is left
            // stranded on the Lock Screen from a previous run.
            WorkoutLiveActivity.shared.endAll()
            sessionMinimised = false
            return
        }

        // Anything older than 12 hours is stale — close it out rather than
        // dropping the user back into yesterday's workout.
        if open.startedAt.timeIntervalSinceNow < -12 * 3600 {
            if open.completedSets.isEmpty {
                context.delete(open)
            } else {
                open.endedAt = open.completedSets.compactMap(\.completedAt).max() ?? open.startedAt
            }
            try? context.save()
            WorkoutLiveActivity.shared.endAll()
            sessionMinimised = false
            return
        }

        activeWorkout = ActiveWorkout(session: open, context: context, history: sessions)
        isSessionExpanded = !sessionMinimised
    }
}
