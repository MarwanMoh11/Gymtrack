import SwiftUI

/// The watch app.
///
/// Two states, and the app is only ever in one of them: nothing running, in
/// which case it offers today's session; or a session in progress, laid out
/// like the Workout app — controls to the left, logging in the middle,
/// what your body is doing to the right.
struct WatchRootView: View {

    var connector: WatchConnector
    var recorder: WatchWorkoutRecorder

    @Environment(\.scenePhase) private var scenePhase

    @State private var rest = WatchRestTimer()
    @State private var page: Page = .log
    @State private var isEnding = false

    enum Page: Hashable { case controls, log, metrics }

    private struct RecorderSyncKey: Hashable {
        var sessionID: UUID?
        var healthEnabled: Bool
        var endedSession: WatchSessionEnd?
        /// The phone's own word, before this wrist filters it. A recording
        /// the app recovered after a crash is closed only once the phone has
        /// spoken, and a first answer of "no session" changes nothing else
        /// here.
        var mirroredSessionID: UUID?
        var heardFromPhone: Bool
    }

    private var recorderSyncKey: RecorderSyncKey {
        RecorderSyncKey(sessionID: connector.session?.sessionID,
                        healthEnabled: connector.mirror.healthEnabled,
                        endedSession: connector.mirror.endedSession,
                        mirroredSessionID: connector.mirror.session?.sessionID,
                        heardFromPhone: connector.hasEverReceivedMirror)
    }

    var body: some View {
        Group {
            if let session = connector.session {
                // Horizontal pages, like the Workout app. Deliberately not the
                // vertical style: that hands the Digital Crown to paging, and
                // the crown belongs to the weight and reps.
                TabView(selection: $page) {
                    NavigationStack {
                        WatchControlsView(session: session, connector: connector, rest: rest,
                                          onEnd: end, onDiscard: discard)
                    }
                    .tag(Page.controls)

                    NavigationStack {
                        WatchLoggerView(session: session, connector: connector, rest: rest)
                    }
                    .tag(Page.log)

                    NavigationStack {
                        WatchMetricsView(session: session, recorder: recorder)
                    }
                    .tag(Page.metrics)
                }
                .tabViewStyle(.page)
            } else {
                NavigationStack {
                    WatchIdleView(connector: connector)
                }
            }
        }
        .overlay {
            if isEnding { EndingOverlay() }
        }
        // A session appearing or disappearing is what starts and stops the
        // heart rate recording — however it happened, on either device.
        .task(id: recorderSyncKey) {
            await syncRecorder()
        }
        // Follow the phone's rest so both screens count to the same instant.
        .onChange(of: connector.session?.restEndsAt) { _, endsAt in
            rest.sync(endsAt: endsAt, total: connector.session?.restTotalSeconds ?? 0,
                      unknown: connector.session?.restUnknown == true)
        }
        .onChange(of: connector.session?.sessionID) { _, id in
            // Land on the logger for a new session rather than wherever the
            // last one was left.
            if id != nil { page = .log }
        }
        // A raised wrist is the moment the watch is most likely to be holding
        // something out of date — the app can sit on one screen for a day, and
        // the idle screen's every line answers "today". The idle view asks on
        // the way in, which covers a launch but not a wrist coming back up to
        // a view that never went away.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            connector.requestMirror()
            // The idle rule's own loop can be held up while the system keeps
            // the app suspended, and a raised wrist is when a session left
            // open would otherwise be put back in front of the lifter.
            recorder.finishIfIdle()
        }
    }

    // MARK: - Recording

    private func syncRecorder() async {
        if let session = connector.session {
            rest.sync(endsAt: session.restEndsAt, total: session.restTotalSeconds,
                      unknown: session.restUnknown == true)
            // Whether or not the workout is saved to Health. The workout
            // session is the app's only runtime with the wrist down: without
            // it the rest-over tap never fired, the watch face came back
            // between sets, and no heart rate was collected. Saving off only
            // means every end discards.
            await recorder.startIfNeeded(for: session)
        } else if !isEnding {
            // Before the recorder, and whether or not one ran: with nothing
            // recording, a Finish on the phone left the countdown to buzz
            // after the workout was over.
            if rest.isRunning { rest.stop() }
            if recorder.isStarting {
                await recorder.end(discardingSamples: true)
            } else {
                await recorder.closeIfSessionOver()
            }
        }
    }

    // MARK: - Ending from the wrist

    private func end() {
        guard let session = connector.session, !isEnding else { return }
        isEnding = true
        // The batch and the mark are taken inside this call, before anything
        // can suspend. The Finish may sit in the queue for as long as the
        // phone is in a locker, and every mirror until it lands still calls
        // this session live; unmarked, a relaunch in that window started a
        // second Health workout for it. See `WatchWorkoutRecorder.finishOnWrist`,
        // which the idle rule goes through too.
        let finishing = recorder.finishOnWrist(session)
        WatchHaptics.finish()
        Task {
            await finishing.value
            rest.stop()
            isEnding = false
        }
    }

    private func discard() {
        guard let session = connector.session, !isEnding else { return }
        let sessionID = session.sessionID
        isEnding = true
        connector.markEndedLocally(sessionID)
        Task {
            await recorder.end(discardingSamples: true)
            rest.stop()
            connector.send(.discardSession(id: sessionID))
            isEnding = false
        }
    }
}

/// Covers the screen for the second it takes Health to close a workout out, so
/// the last thing tapped can't be tapped twice.
private struct EndingOverlay: View {
    var body: some View {
        ZStack {
            Theme.background.opacity(0.94).ignoresSafeArea()
            SessionPhase.done.bloom(strength: 1.4).ignoresSafeArea()
            VStack(spacing: 9) {
                ProgressView()
                    .tint(SessionPhase.done.tint)
                Text("Saving")
                    .font(Theme.rounded(13, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("Closing the workout in Health")
                    .font(Theme.rounded(10, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 12)
        }
    }
}
