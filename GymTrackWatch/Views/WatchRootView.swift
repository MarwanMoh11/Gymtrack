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

    @State private var rest = WatchRestTimer()
    @State private var page: Page = .log
    @State private var isEnding = false

    enum Page: Hashable { case controls, log, metrics }

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
        .task(id: connector.session?.sessionID) {
            await syncRecorder()
        }
        // Follow the phone's rest so both screens count to the same instant.
        .onChange(of: connector.session?.restEndsAt) { _, endsAt in
            rest.sync(endsAt: endsAt, total: connector.session?.restTotalSeconds ?? 0)
        }
        .onChange(of: connector.session?.sessionID) { _, id in
            // Land on the logger for a new session rather than wherever the
            // last one was left.
            if id != nil { page = .log }
        }
    }

    // MARK: - Recording

    private func syncRecorder() async {
        if let session = connector.session {
            rest.sync(endsAt: session.restEndsAt, total: session.restTotalSeconds)
            await recorder.startIfNeeded(for: session)
        } else if recorder.isRunning, !isEnding {
            // The phone ended the session. Save what the watch measured and
            // hand the phone the Health workout so it doesn't write a second.
            let metrics = await recorder.end(title: nil)
            rest.stop()
            if let metrics { connector.send(.metrics(metrics)) }
        }
    }

    // MARK: - Ending from the wrist

    private func end() {
        guard let session = connector.session, !isEnding else { return }
        isEnding = true
        WatchHaptics.finish()
        Task {
            let metrics = await recorder.end(
                title: session.title,
                sets: session.completedSets,
                volumeKg: session.volumeKg
            )
            rest.stop()
            connector.send(.finish(metrics: metrics))
            isEnding = false
        }
    }

    private func discard() {
        guard !isEnding else { return }
        isEnding = true
        Task {
            await recorder.end(discardingSamples: true)
            rest.stop()
            connector.send(.discard)
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
