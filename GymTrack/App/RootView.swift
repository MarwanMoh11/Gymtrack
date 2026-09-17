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
    @Query(sort: \Plan.createdAt) private var plans: [Plan]

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
            connectWatch()
            syncBodyWeightFromHealth()
            publishWidgets()
            runPendingAction()
        }
        .onChange(of: hasOnboarded) { _, done in
            if done { seedSampleDataIfRequested() }
        }
        .onChange(of: customExercises.count) { _, _ in syncCustomExercises() }
        // The watch's idle screen is built from the plan and the history, so
        // it has to be restamped whenever either moves.
        .onChange(of: sessions.count) { _, _ in pushWatchIdle(); publishWidgets() }
        .onChange(of: plans.count) { _, _ in pushWatchIdle(); publishWidgets() }
        // Derived rather than set at each call site — the session can be put
        // away or brought back from the logger, the dock, the Today card and a
        // Live Activity tap, and every one of them has to agree.
        .onChange(of: isSessionMinimised) { _, minimised in
            sessionMinimised = minimised
        }
        // Reading `activeWorkout` back inside the closure that just assigned it
        // hands you the previous value — it's `@State`, and the write isn't
        // visible through this copy of the view. So the widgets are republished
        // off a change the view has already settled, rather than at each of the
        // six call sites that start or end a session.
        .onChange(of: activeWorkout?.session.id) { _, _ in publishWidgets() }
        // Restamp the card on the way out — that's the moment it becomes the
        // thing the user is looking at — and on the way back in, since the rest
        // timer can't tick while the app is suspended.
        .onChange(of: scenePhase) { _, phase in
            activeWorkout?.pushLiveActivity()
            if phase == .active {
                activeWorkout?.pushToWatch()
                pushWatchIdle()
                publishWidgets()
                // Siri, a Shortcut, the Action Button or a widget button can
                // only leave a note and bring the app forward — this is where
                // the note gets read.
                runPendingAction()
            }
        }
        .onOpenURL { url in
            switch url.host {
            case "session": expandSession()
            case "start-today": startScheduledSession()
            case "start-freestyle": startFreestyleSession()
            default: break
            }
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
        pushWatchIdle()
    }

    private func discardSession() {
        activeWorkout?.discard()
        closeSession()
        pushWatchIdle()
    }

    // MARK: - Starting from outside the app

    /// Siri, a Shortcut, the Action Button and the widgets all land here. None
    /// of them can build a session themselves — see `GymTrackIntents` — so they
    /// leave a note and bring the app forward, and this reads it.
    private func runPendingAction() {
        switch SharedStore.takeAction() {
        case .startToday: startScheduledSession()
        case .startFreestyle: startFreestyleSession()
        case .openSession: expandSession()
        case nil: break
        }
    }

    /// Today's prescribed session, or a freestyle one when today isn't a
    /// training day. Asking to start a workout on a rest day is still asking to
    /// start a workout, and refusing would be the wrong answer to a button the
    /// user deliberately pressed.
    private func startScheduledSession() {
        guard activeWorkout == nil else { return expandSession() }
        let plan = plans.first(where: \.isActive) ?? plans.first
        let history = sessions.filter { !$0.isActive }
        if let day = plan?.day(for: .now) {
            present(ActiveWorkout.start(day: day, plan: plan, context: context, history: history))
        } else {
            present(ActiveWorkout.startFreestyle(context: context, history: history))
        }
    }

    private func startFreestyleSession() {
        guard activeWorkout == nil else { return expandSession() }
        present(ActiveWorkout.startFreestyle(context: context,
                                             history: sessions.filter { !$0.isActive }))
    }

    /// Opens the logger straight away — unlike a session started from the
    /// wrist, whoever pressed this was holding the phone.
    private func present(_ workout: ActiveWorkout) {
        activeWorkout = workout
        isSessionExpanded = true
        pushWatchIdle()
    }

    // MARK: - Widgets

    /// Restamps what the Home Screen and Lock Screen draw. Called from the same
    /// places the watch's idle mirror is, because it's built from the same two
    /// things: the active plan and the finished sessions.
    private func publishWidgets() {
        WidgetPublisher.publish(plans: plans, sessions: sessions, running: activeWorkout)
    }

    // MARK: - Apple Watch

    /// Claims what the watch sends for as long as this view is alive. The link
    /// itself came up at launch — see `WatchCommandCenter` — and goes back to
    /// applying commands headlessly if the app is never brought on screen.
    private func connectWatch() {
        WatchCommandCenter.shared.uiHandler = { command in
            handleWatchCommand(command)
        }
        pushWatchIdle()
        activeWorkout?.pushToWatch()
    }

    private func pushWatchIdle() {
        WatchBridge.shared.update(idle: WatchMirrorBuilder.idle(plans: plans, sessions: sessions))
    }

    /// Anything the running session knows how to do, it does. What's left is
    /// session lifecycle, which lives here.
    ///
    /// Returns false for anything this view is in no position to serve — a set
    /// logged against a session it isn't holding — so `WatchCommandCenter`
    /// applies it to the store instead of dropping it.
    private func handleWatchCommand(_ command: WatchCommand) -> Bool {
        if let workout = activeWorkout, workout.apply(command) { return true }

        switch command {
        case .startToday:
            let plan = plans.first(where: \.isActive) ?? plans.first
            if let day = plan?.day(for: .now) {
                startFromWatch(ActiveWorkout.start(day: day, plan: plan, context: context,
                                                   history: sessions.filter { !$0.isActive }))
            } else {
                startFromWatch(ActiveWorkout.startFreestyle(context: context,
                                                            history: sessions.filter { !$0.isActive }))
            }
            return true

        case .startFreestyle:
            startFromWatch(ActiveWorkout.startFreestyle(context: context,
                                                        history: sessions.filter { !$0.isActive }))
            return true

        case .finish(let metrics):
            if activeWorkout != nil {
                finishSession()
                return true
            }
            // The watch ended a session the phone had already closed out.
            if let metrics { return applyLateMetrics(metrics) }
            return false

        case .metrics(let metrics):
            // Only reaches here with no session running: the watch saving its
            // workout to Health after the phone finished.
            return applyLateMetrics(metrics)

        case .discard:
            guard activeWorkout != nil else { return false }
            discardSession()
            return true

        case .requestMirror:
            pushWatchIdle()
            activeWorkout?.pushToWatch()
            return true

        default:
            // A set logged against a session this view isn't holding.
            return false
        }
    }

    /// A session started from the wrist opens minimised: the phone is usually
    /// in a bag when this happens, and springing the logger open would mean
    /// finding it in that state later.
    private func startFromWatch(_ workout: ActiveWorkout) {
        guard activeWorkout == nil else { return }
        workout.session.wasWatchDriven = true
        activeWorkout = workout
        isSessionExpanded = false
        pushWatchIdle()
    }

    /// Heart rate, energy and the Health workout the watch saved can land
    /// after the phone has already filed the session — the watch takes a few
    /// seconds to close a workout out. Match them back up by session ID.
    @discardableResult
    private func applyLateMetrics(_ metrics: WatchWorkoutMetrics) -> Bool {
        guard let id = metrics.sessionID,
              let session = sessions.first(where: { $0.id == id })
        else { return false }

        session.wasWatchDriven = true
        if let average = metrics.averageHeartRate { session.averageHeartRate = average }
        if let max = metrics.maxHeartRate { session.maxHeartRate = max }
        if let energy = metrics.activeEnergyKcal, energy > 0 { session.activeEnergyKcal = energy }
        if let workoutID = metrics.healthWorkoutID { session.healthWorkoutID = workoutID }
        try? context.save()
        return true
    }

    // MARK: - Health

    /// Pulls weigh-ins recorded elsewhere — a connected scale, the Health app —
    /// into the app's own history.
    private func syncBodyWeightFromHealth() {
        guard AppSettings.shared.healthBodyWeight else { return }
        Task { await HealthKitService.shared.importBodyMass(into: context) }
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
