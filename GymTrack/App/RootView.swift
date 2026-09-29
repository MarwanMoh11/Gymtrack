import SwiftUI
import SwiftData

enum AppTab: Hashable {
    case today, plan, library, progress
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query private var customExercises: [CustomExerciseRecord]
    @Query private var hiddenExercises: [HiddenExerciseRecord]
    @Query private var sessions: [WorkoutSession]
    @Query(sort: \Plan.createdAt) private var plans: [Plan]

    @AppStorage(SettingsKey.hasOnboarded) private var hasOnboarded = false
    /// Remembers that the user chose to put the session away, so relaunching
    /// doesn't drop them back into the logger they deliberately left.
    @AppStorage(SettingsKey.sessionMinimised) private var sessionMinimised = false

    @State private var selectedTab: AppTab = .today
    @State private var activeWorkout: ActiveWorkout?
    @State private var isSessionExpanded = false
    /// Bumped by `WatchIdleSync` each time the idle snapshot it watches
    /// changes, so the widgets follow it from here, where the running
    /// workout is known.
    @State private var watchIdleRevision = 0
    @State private var showingSummary: WorkoutSession?
    @State private var confirmingDockFinish = false
    @State private var confirmingDockDiscard = false
    /// True while a heart-rate backfill over recent sessions is running. See
    /// `backfillRecentHeartRate`.
    @State private var isBackfillingRecentSessions = false
    /// Where a Siri, Shortcut or Action Button start is read. Closed until the
    /// first `.task` has adopted whatever session was left open: a start read
    /// before then finds no `activeWorkout` and begins a second session beside
    /// the unfinished one. A class, so opening it is visible to every closure
    /// at once instead of to the next copy of the view.
    @State private var pendingInbox = PendingActionHandoff.Inbox()

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
            syncHiddenExercises()
            resumeUnfinishedSession()
            seedSampleDataIfRequested()
            connectWatch()
            syncBodyWeightFromHealth()
            publishWidgets()
            pendingInbox.open()
            runPendingAction()
            backfillRecentHeartRate()
        }
        .onChange(of: hasOnboarded) { _, done in
            if done { seedSampleDataIfRequested() }
        }
        .onChange(of: customExercises.count) { _, _ in syncCustomExercises() }
        .onChange(of: hiddenExercises.count) { _, _ in syncHiddenExercises() }
        // Watched as the whole snapshot rather than as two counts.
        //
        // The counts moved only when a plan or a session was created or
        // deleted, and almost nothing that changes what the wrist should say
        // does that: marking today as a rest day, renaming it, moving it to
        // another weekday, swapping an exercise or changing its sets all leave
        // both counts exactly where they were. So the watch went on offering a
        // session that was no longer scheduled — a workout on a rest day, which
        // is the app inventing training — until something unrelated happened to
        // restamp the mirror.
        //
        // Comparing what is about to be sent is also the only version of this
        // that stays correct when a field is added to the snapshot, rather than
        // needing a new trigger alongside it.
        //
        // The comparison lives in `WatchIdleSync`, a view of its own. Made
        // here, it was rebuilt — the streak and the rotation over every
        // finished session — on every pass of this body, and this body runs
        // for a tab switch or a sheet as much as for a change to the data.
        .background { WatchIdleSync(revision: $watchIdleRevision).equatable() }
        .onChange(of: watchIdleRevision) { _, _ in publishWidgets() }
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
        .onChange(of: AppSettings.shared.trackRPE) { _, _ in
            activeWorkout?.pushToWatch()
        }
        // The wrist reads its unit and whether to start a rest from the
        // session mirror, and Settings stays reachable mid-workout. Without a
        // push the phone showed 225 lb while the wrist turned kg, and a rest
        // switched off here still started after the next wrist log.
        .onChange(of: AppSettings.shared.weightUnit) { _, _ in
            activeWorkout?.pushToWatch()
        }
        .onChange(of: AppSettings.shared.restTimerAutoStart) { _, _ in
            activeWorkout?.pushToWatch()
        }
        // Restamp the card on the way out — that's the moment it becomes the
        // thing the user is looking at — and on the way back in, since the rest
        // timer can't tick while the app is suspended.
        .onChange(of: scenePhase) { _, phase in
            // A warm resume never runs `.task`, so a session left open
            // overnight is retired here too — before anything restamps the
            // Lock Screen or the wrist with it.
            let retired = phase == .active && retireStaleSession()
            if !retired { activeWorkout?.pushLiveActivity() }
            if phase == .active {
                if !retired { activeWorkout?.pushToWatch() }
                pushWatchIdle()
                publishWidgets()
                // Siri, a Shortcut, the Action Button or a widget button can
                // only leave a note and bring the app forward — this is where
                // the note gets read if it was already there. One written
                // after the app came to the front is read on its announcement
                // below.
                runPendingAction()
                backfillRecentHeartRate()
                // A workout Health refused to remove, or could not look up
                // while the phone was locked, waits on the list until
                // something asks again. A cold launch can be days away.
                Task { await HealthKitService.shared.retryPendingWorkoutCleanup() }
            }
        }
        // The intent runs in this process, and the system may bring the app to
        // the front before or after `perform()` has left its note. Reading
        // only on activation lost the second order: the note was written
        // after the read, waited for the next activation, and either started a
        // workout minutes late or aged out. The intent announces every note,
        // so the read happens whichever came first. A note is taken once, so
        // hearing about it twice starts nothing twice.
        .onReceive(NotificationCenter.default.publisher(for: PendingActionHandoff.didRequest)
            .receive(on: DispatchQueue.main)) { _ in
            runPendingAction()
        }
        // One decision for every way it can change: the setting, a session
        // starting or ending, the app leaving the screen. `initial` covers a
        // launch straight into a resumed session.
        .onChange(of: holdsScreenAwake, initial: true) { _, awake in
            UIApplication.shared.isIdleTimerDisabled = awake
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
                        // A Finish with nothing logged discards the session,
                        // and a deleted session has no summary to open.
                        if let finished, !finished.isGoneFromStore { showingSummary = finished }
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
        // `ActiveWorkout.finish` discards an empty session, and "Every set
        // logged" was the message for a workout with no sets in it.
        if workout.completedCount == 0 { return "Nothing was logged, so this session won't be kept." }
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

    /// - Parameter moment: when the session ended. Now, for the phone's own
    ///   Finish; the wrist's tap, for one that came from the watch.
    private func finishSession(at moment: Date = .now) {
        guard let workout = activeWorkout else { return }
        let session = workout.session
        let kept = workout.finish(at: moment)
        closeSession()
        if kept { showingSummary = session }
        pushWatchIdle()
    }

    private func discardSession() {
        activeWorkout?.discard()
        closeSession()
        pushWatchIdle()
    }

    // MARK: - Screen

    /// Held only while a workout is open and the app is on screen. The
    /// preference alone used to keep the phone awake for as long as the app
    /// was open.
    private var holdsScreenAwake: Bool {
        ScreenAwakeRules.holdsScreenAwake(
            setting: AppSettings.shared.keepScreenAwake,
            workoutOpen: activeWorkout != nil,
            appIsActive: scenePhase == .active
        )
    }

    // MARK: - Starting from outside the app

    /// Siri, a Shortcut, the Action Button and the widgets all land here. None
    /// of them can build a session themselves — see `GymTrackIntents` — so they
    /// leave a note and bring the app forward, and this reads it.
    private func runPendingAction() {
        switch pendingInbox.take() {
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
        if let day = plan?.nextDay(on: .now, after: history) {
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
        // The session first, for the same reason `WatchCommandCenter` does
        // it: an idle update sent ahead of it carries whatever session the
        // bridge held before.
        activeWorkout?.pushToWatch()
        pushWatchIdle()
    }

    /// What the watch's idle screen is built from — today's prescription, the
    /// streak and the last thing trained. Computed rather than stored so every
    /// send is made from the store as it is at that moment. Nothing here reads
    /// it during a body pass; see `WatchIdleSync`.
    private var watchIdle: WatchIdleSnapshot {
        WatchMirrorBuilder.idle(plans: plans, sessions: sessions)
    }

    private func pushWatchIdle() {
        WatchBridge.shared.update(idle: watchIdle)
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
            if let day = plan?.nextDay(on: .now, after: sessions) {
                startFromWatch {
                    ActiveWorkout.start(day: day, plan: plan, context: context,
                                        history: sessions.filter { !$0.isActive })
                }
            } else {
                startFromWatch {
                    ActiveWorkout.startFreestyle(context: context,
                                                 history: sessions.filter { !$0.isActive })
                }
            }
            return true

        case .startFreestyle:
            startFromWatch {
                ActiveWorkout.startFreestyle(context: context,
                                             history: sessions.filter { !$0.isActive })
            }
            return true

        case .finishSession(let batch, _):
            if let workout = activeWorkout, workout.session.id == batch.sessionID {
                workout.session.applyWatchFinish(batch)
                try? context.save()
                finishSession(at: workout.session.wristFinishMoment(batch.endedAt))
                return true
            }
            // A session this view isn't holding is one the store-side path
            // either adopts or has already seen closed. A closed one may still
            // be owed the logs in this batch — the phone's Finish can beat the
            // wrist's — and those and the metrics are written in one context
            // and one save there, rather than half of them here.
            return false

        case .logSet, .undoSet:
            // The running logger had no row for it. With nothing running the
            // store-side path takes it whole; with a logger on screen, it may
            // only reach a session already finished, never the one this view
            // is writing to.
            guard activeWorkout != nil else { return false }
            WatchCommandCenter.shared.applyToFinishedSession(command)
            return true

        case .finish(let metrics):
            // A queued command from an older watch has no independent session
            // ID. Its metrics may identify one; without them, closing the
            // current workout would risk ending a different session.
            guard let metrics, let id = metrics.sessionID else { return true }
            if activeWorkout?.session.id == id {
                finishSession()
                return true
            }
            return applyLateMetrics(metrics, final: true)

        case .metrics(let metrics):
            // Reaches here only for a session the logger isn't running: most
            // often the watch handing over the workout it saved to Health
            // after the phone finished, and now and then a live reading that
            // landed after the close, which `takeWatchMetrics` turns away.
            return applyLateMetrics(metrics, final: false)

        case .discardSession(let id):
            guard activeWorkout?.session.id == id else { return false }
            discardSession()
            return true

        case .discard:
            // The old payload cannot identify its target. Ignore it rather
            // than letting a delayed Discard delete the next workout.
            return true

        case .requestMirror:
            // A background start can reach the store before this view adopts
            // it. Let the headless path read it instead of replying as idle.
            guard activeWorkout != nil else { return false }
            pushWatchIdle()
            activeWorkout?.pushToWatch()
            // Both of those only push when something changed, and a watch asks
            // precisely when it suspects it is holding something stale — a
            // mirror built yesterday says the same thing today and would be
            // answered with silence.
            WatchBridge.shared.resend()
            return true

        default:
            // A set logged against a session this view isn't holding.
            return false
        }
    }

    /// A session started from the wrist opens minimised: the phone is usually
    /// in a bag when this happens, and springing the logger open would mean
    /// finding it in that state later.
    private func startFromWatch(_ makeWorkout: () -> ActiveWorkout) {
        // Yesterday's session, held since the app was last on screen, would
        // count as the one already running and be handed back to a wrist that
        // will not draw it — every Start ended on "Starting…" and nothing more.
        let retired = retireStaleSession()
        // A live message can also be queued after its send fails, then arrive
        // twice. Check before building: an already-built workout has inserted
        // a second active session into the store even if we decline to show it.
        if !retired, let activeWorkout {
            activeWorkout.pushToWatch()
            WatchBridge.shared.resend()
            return
        }
        // SwiftUI may not have rendered a background start yet. Read the
        // store before creating anything so a retry also adopts that session.
        let stored = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? sessions
        let workout: ActiveWorkout
        if let open = stored.first(where: \.isActive) {
            workout = ActiveWorkout(session: open, context: context, history: stored)
        } else {
            workout = makeWorkout()
        }
        workout.session.wasWatchDriven = true
        try? context.save()
        activeWorkout = workout
        isSessionExpanded = false
        pushWatchIdle()
    }

    /// Heart rate, energy and the Health workout the watch saved can land
    /// after the phone has already filed the session — the watch takes a few
    /// seconds to close a workout out. Match them back up by session ID.
    ///
    /// - Parameter final: true for the metrics a Finish carried. Anything else
    ///   reaches a closed session only as the Health hand-over.
    @discardableResult
    private func applyLateMetrics(_ metrics: WatchWorkoutMetrics, final: Bool) -> Bool {
        guard let id = metrics.sessionID else { return false }
        guard let session = sessions.first(where: { $0.id == id }) else {
            discardOrphanWorkout(of: metrics)
            return false
        }
        // The query can still hand back a session an erase, a restore or the
        // wrist deleted through another context a moment ago. Linking a watch
        // workout to it would file the ID on a row no later erase can find.
        // Not handled here, so the store-side path looks the ID up afresh: a
        // restore may have put the same session back, and a session that is
        // really gone is turned away there. The watch's workout is queued for
        // removal from Health first, if the store confirms no session holds
        // it; otherwise nothing would ever find it.
        guard !session.isGone(fromStore: FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.id == id })) else {
            discardOrphanWorkout(of: metrics)
            return false
        }
        // Handled either way: a reading turned away here has nowhere better
        // to go, and the store-side path would only turn it away again.
        guard session.takeWatchMetrics(metrics, final: final) else { return true }
        session.stampWatchVitals(average: metrics.averageHeartRate, max: metrics.maxHeartRate, energy: metrics.activeEnergyKcal)
        if let workoutID = metrics.healthWorkoutID {
            HealthKitService.shared.acceptWatchWorkout(workoutID, for: session, context: context)
        }
        try? context.save()
        return true
    }

    /// Queues the Health workout a watch report names, when no session holds
    /// it any more. A session the user deleted while the wrist was still
    /// saving leaves the watch's workout in Fitness with nothing in the app
    /// pointing at it. Health does the checking, against the store rather
    /// than this view's query, so a session that is only late to appear in
    /// the query keeps its workout.
    private func discardOrphanWorkout(of metrics: WatchWorkoutMetrics) {
        guard let id = metrics.sessionID, let workoutID = metrics.healthWorkoutID else { return }
        HealthKitService.shared.discardOrphanWorkout(workoutID, sessionID: id)
    }

    // MARK: - Health

    /// Pulls weigh-ins recorded elsewhere — a connected scale, the Health app —
    /// into the app's own history.
    private func syncBodyWeightFromHealth() {
        guard AppSettings.shared.healthBodyWeight else { return }
        Task { await HealthKitService.shared.importBodyMass(into: context) }
    }

    /// Gives recent sets the heart rate a headless finish couldn't read. A
    /// workout finished on the wrist with the phone locked is filed with no
    /// view on screen, every Health read then fails, and no summary is ever
    /// shown to try again, so the next unlock is the first chance.
    ///
    /// One pass at a time. A trip to Control Center brings the scene back to
    /// active while a slow pass is still waiting on Health, and a second pass
    /// over the same sessions would only ask the same questions again.
    private func backfillRecentHeartRate() {
        guard !isBackfillingRecentSessions else { return }
        isBackfillingRecentSessions = true
        Task {
            await HealthKitService.shared.backfillRecentSessions(in: context)
            isBackfillingRecentSessions = false
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
    ///
    /// Also gives their plan slots the record of how each is measured, which
    /// only new slots and the editor's delete used to write. A failure here
    /// costs nothing: the next launch or the next change asks again.
    private func syncCustomExercises() {
        let custom = customExercises.map(\.asCatalogExercise)
        ExerciseCatalog.shared.setCustom(custom)
        _ = try? context.snapshotCustomSlotTracking(of: custom)
    }

    /// Applies the user's trimmed-down view of the library. Hidden exercises
    /// stay resolvable by ID — this only governs what browsing and search show.
    private func syncHiddenExercises() {
        ExerciseVisibility.sync(from: hiddenExercises)
    }

    /// Picks up a session left open by a crash or a force-quit.
    private func resumeUnfinishedSession() {
        guard activeWorkout == nil,
              let open = WatchSessionRecovery.discardUntouchedOverlaps(sessions, in: context)
                  .first(where: { $0.isActive })
        else {
            // Nothing to come back to — make sure no Live Activity is left
            // stranded on the Lock Screen from a previous run.
            WorkoutLiveActivity.shared.endAll()
            sessionMinimised = false
            return
        }

        // Stale — close it out rather than dropping the user back into
        // yesterday's workout.
        if let end = WatchCommandCenter.shared.retire(open, in: context) {
            WorkoutLiveActivity.shared.endAll()
            if openSessions.isEmpty { WatchBridge.shared.update(session: nil, ended: end) }
            sessionMinimised = false
            return
        }

        activeWorkout = ActiveWorkout(session: open, context: context, history: sessions)
        isSessionExpanded = !sessionMinimised
    }

    /// The twelve-hour rule — `WorkoutSession.closeIfStale` — for the paths
    /// that never pass through `resumeUnfinishedSession`: a warm resume, and a
    /// wrist asking for a workout while the app has been resident since
    /// yesterday. Without it the dock went on offering a session the watch
    /// refuses to draw, and Finish recorded the whole night.
    ///
    /// A session this view holds is taken down the way a finish takes it down
    /// — rest timer, Lock Screen, the wrist, the logger, and Health for one
    /// that kept sets; see `WatchCommandCenter.retire`. Returns true when it
    /// was, so the caller knows not to use the workout it was holding.
    @discardableResult
    private func retireStaleSession() -> Bool {
        if let workout = activeWorkout {
            guard workout.session.isStale() else { return false }
            workout.restTimer.onChange = nil
            workout.restTimer.stop()
            let end = WatchCommandCenter.shared.retire(workout.session, in: context)
            WorkoutLiveActivity.shared.endAll()
            WatchBridge.shared.update(session: nil, ended: end)
            WatchBridge.shared.clearMetrics()
            WidgetPublisher.updateSession(nil)
            closeSession()
            pushWatchIdle()
            return true
        }

        // A session started in the background that this view never adopted.
        let stale = openSessions.filter { $0.isStale() }.sorted { $0.startedAt < $1.startedAt }
        guard !stale.isEmpty else { return false }
        let ends = stale.compactMap { WatchCommandCenter.shared.retire($0, in: context) }
        // A session opened since is still running, and the Lock Screen and
        // the wrist are about that one. Otherwise the latest is the one a
        // wrist could still be recording.
        if openSessions.isEmpty {
            WorkoutLiveActivity.shared.endAll()
            WatchBridge.shared.update(session: nil, ended: ends.last)
        }
        pushWatchIdle()
        return false
    }

    /// Read from the store rather than `sessions`, which a session started in
    /// the background may not have reached yet. Only the open ones: this runs
    /// on every return to the foreground, and the history is the whole store.
    private var openSessions: [WorkoutSession] {
        let open = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.endedAt == nil })
        return (try? context.fetch(open)) ?? sessions.filter(\.isActive)
    }
}

/// Sends the watch's idle screen whenever what it would say changes.
///
/// A view of its own, with its own queries, so that the streak and the
/// rotation are recomputed when the plans or sessions change and not on every
/// pass of `RootView`'s body. Its `==` is always true and it is applied with
/// `.equatable()`, so a pass of the parent that changed nothing here does not
/// evaluate it again; a change to its queries still does, which is the only
/// time the answer can differ.
private struct WatchIdleSync: View, Equatable {
    @Query private var sessions: [WorkoutSession]
    @Query(sort: \Plan.createdAt) private var plans: [Plan]
    @Binding var revision: Int

    static func == (lhs: WatchIdleSync, rhs: WatchIdleSync) -> Bool { true }

    private var idle: WatchIdleSnapshot {
        WatchMirrorBuilder.idle(plans: plans, sessions: sessions)
    }

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onChange(of: idle) { _, snapshot in
                WatchBridge.shared.update(idle: snapshot)
                revision &+= 1
            }
    }
}
