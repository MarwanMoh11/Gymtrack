import Foundation
import SwiftData
import WatchConnectivity
import os

/// The phone's end of the watch link.
///
/// The phone is the source of truth: it pushes a mirror of the session after
/// every change and applies commands the watch sends back. Nothing is
/// negotiated — the watch never holds state the phone doesn't have, so a watch
/// that was out of range, asleep or reinstalled catches up with one payload.
///
/// Delivery uses both channels on purpose. `updateApplicationContext` always
/// carries the latest mirror and survives the watch app being asleep;
/// `sendMessage` goes out as well when the watch is reachable, because between
/// sets "instant" is the difference between useful and irritating.
@MainActor
@Observable
final class WatchBridge: NSObject {

    static let shared = WatchBridge()

    /// Set by whoever owns the running session — see `RootView`.
    @ObservationIgnored var commandHandler: ((WatchCommand) -> Void)?

    private(set) var isSupported = false
    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false
    /// Heart rate and energy as they arrive from the wrist.
    private(set) var liveMetrics: WatchWorkoutMetrics?
    private(set) var lastMirrorSentAt: Date?

    /// Sends nothing until `WatchCommandCenter.configure` has read the store —
    /// see `WatchMirrorState` for the mid-workout recording this protects.
    /// Readable so a test can see how the wrist was told a session ended: a
    /// test host never activates the link, so nothing it pushes leaves here.
    @ObservationIgnored private(set) var mirrorState = WatchMirrorState()
    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack", category: "WatchBridge")

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Called once at launch. Safe on devices with no watch — `isSupported`
    /// stays false and every push below is a no-op.
    /// A unit-test host stays unlinked too, so a test's push is the same no-op.
    func activate() {
        guard !LaunchMode.isUnitTestHost, WCSession.isSupported() else { return }
        isSupported = true
        let session = WCSession.default
        session.delegate = self
        session.activate()
        refreshStatus()
    }

    /// True when there's a watch worth talking to.
    var isLinked: Bool { isSupported && isPaired && isWatchAppInstalled }

    var statusDescription: String {
        guard isSupported else { return "This device can't pair with a watch" }
        guard isPaired else { return "No Apple Watch paired" }
        guard isWatchAppInstalled else { return "Install GymTrack on your watch from the Watch app" }
        return isReachable ? "Connected" : "Paired — the watch will catch up when it's nearby"
    }

    private func refreshStatus() {
        guard isSupported else { return }
        let session = WCSession.default
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    // MARK: - Pushing state

    /// The idle screen's contents — today's session, streak, last workout.
    func update(idle snapshot: WatchIdleSnapshot) {
        guard mirrorState.update(idle: snapshot) else { return }
        push()
    }

    /// The running session, or `nil` once it ends.
    func update(session snapshot: WatchSessionSnapshot?, ended end: WatchSessionEnd? = nil) {
        // A session ending is also the moment the watch should stop its own
        // workout, so that transition is always worth a push.
        guard mirrorState.update(session: snapshot, ended: end) else { return }
        if snapshot == nil { liveMetrics = nil }
        push()
    }

    /// Restamps a finished mirror if the phone wrote the Health fallback after
    /// its first end push. A delayed watch must then discard its own samples.
    func notePhoneHealthWorkout(_ workoutID: UUID, for sessionID: UUID) {
        guard mirrorState.notePhoneHealthWorkout(workoutID, for: sessionID) else { return }
        push()
    }

    /// Re-sends the current mirror — for a watch that just asked, or that just
    /// became reachable.
    func resend() { push() }

    private func push() {
        guard isSupported, WCSession.default.activationState == .activated else { return }
        let payload = mirrorPayload()
        guard !payload.isEmpty else { return }

        do {
            try WCSession.default.updateApplicationContext(payload)
            lastMirrorSentAt = .now
        } catch {
            log.debug("Application context refused: \(error.localizedDescription, privacy: .public)")
        }
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(payload, replyHandler: nil) { [weak self] error in
                self?.log.debug("Live mirror failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Replies carry the same state as pushes, stamped after the command has
    /// finished so an earlier idle context cannot undo a successful start.
    /// Empty until the phone has said what is running.
    private func mirrorPayload() -> [String: Any] {
        guard let mirror = mirrorState.nextMirror(healthEnabled: AppSettings.shared.healthWriteWorkouts)
        else { return [:] }
        return mirror.watchPayload(key: WatchLink.mirrorKey)
    }

    // MARK: - Receiving

    /// Internal rather than private so a test can feed a payload through the
    /// same verdict the delegate callbacks reach.
    func handle(_ payload: [String: Any]) {
        guard let command = WatchCommand.fromWatchPayload(payload, key: WatchLink.commandKey) else { return }
        // Judged before anything reads it, headless or not: this is the one
        // place both routes share. A refused command still costs a mirror, so
        // the wrist is put back on what the phone actually has open instead of
        // being left waiting for a start that will never happen.
        let verdict = WatchCommandDelivery(payload: payload)
            .verdict(for: command, openSessionID: mirrorState.session?.sessionID)
        guard verdict == .apply else {
            log.debug("Watch command refused: \(String(describing: verdict), privacy: .public)")
            push()
            return
        }
        if case .metrics(let metrics) = command,
           metrics.sessionID == mirrorState.session?.sessionID {
            adoptLive(metrics)
        }
        if case .finish(let metrics) = command, let metrics,
           metrics.sessionID == mirrorState.session?.sessionID {
            adoptLive(metrics)
        }
        if case .finishSession(let batch, let metrics) = command, let metrics,
           metrics.sessionID == batch.sessionID,
           metrics.sessionID == mirrorState.session?.sessionID {
            adoptLive(metrics)
        }
        commandHandler?(command)
    }

    /// Assigns only a reading that changes what is held; see
    /// `WatchWorkoutMetrics.merged`.
    private func adoptLive(_ metrics: WatchWorkoutMetrics) {
        guard let merged = WatchWorkoutMetrics.merged(metrics, into: liveMetrics) else { return }
        liveMetrics = merged
    }

    func clearMetrics() { liveMetrics = nil }
}

/// Hands a WatchConnectivity delegate callback to the main actor in the order
/// it arrived.
///
/// The callbacks come in on the session's own queue, and a `Task` per callback
/// promises no order between two of them: a live message and the queued one
/// behind it could apply the wrong way round, so the mirror ordering guard saw
/// the newer one first and dropped the older, or a wrist log landed after the
/// Finish that closed its session. The main queue runs its blocks in the order
/// they were submitted.
private func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
    DispatchQueue.main.async { MainActor.assumeIsolated { body() } }
}

// MARK: - WCSessionDelegate

extension WatchBridge: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        onMain {
            self.refreshStatus()
            // Sends nothing if the store has not been read yet; the empty
            // state a fresh process starts with is not something to report.
            if state == .activated { self.push() }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to a different watch hands us a fresh session to activate.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        onMain {
            self.refreshStatus()
            self.push()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        // Read on the session's queue, where the callback is, so the answer is
        // the one the callback announced and not whatever it is after the hop.
        let reachable = session.isReachable
        onMain {
            self.refreshStatus()
            // A watch that just came back may have missed everything.
            if reachable { self.push() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let delivered = WatchDelivered(message)
        onMain { self.handle(delivered.value) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        let delivered = WatchDelivered(message)
        let reply = WatchDelivered(replyHandler)
        onMain {
            self.handle(delivered.value)
            // A watch can wake a suspended phone to start a workout. Return
            // the workout on that same conversation instead of relying on a
            // separate push to get the watch off its start screen.
            // With nothing established the reply is a bare acknowledgement,
            // which the watch decodes as no mirror at all rather than as none
            // running.
            var payload = self.mirrorPayload()
            let carriesMirror = !payload.isEmpty
            payload[WatchLink.ackKey] = true
            reply.value(payload)
            if carriesMirror { self.lastMirrorSentAt = .now }
        }
    }

    /// Queued delivery — what a set logged out of range arrives on.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        let delivered = WatchDelivered(userInfo)
        onMain { self.handle(delivered.value) }
    }
}

/// Bridges the app's full tracking mode onto the slimmed-down one the watch
/// understands — the watch has no exercise catalog to resolve.
extension WatchTracking {
    init(_ mode: TrackingMode) {
        switch mode {
        case .weightReps: self = .weightReps
        case .bodyweightReps: self = .bodyweightReps
        case .duration: self = .duration
        }
    }
}

// MARK: - Building the idle snapshot

enum WatchMirrorBuilder {

    /// What the watch shows when no session is running: today's prescription,
    /// the streak, and the last thing that was trained.
    @MainActor
    static func idle(plans: [Plan], sessions: [WorkoutSession]) -> WatchIdleSnapshot {
        let finished = sessions.filter { !$0.isActive }
        let plan = plans.first(where: \.isActive) ?? plans.first
        let today = plan?.nextDay(on: .now, after: finished)
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .distantPast
        // A session closed with nothing logged is not the last thing trained,
        // and not one of the week's sessions: the phone's week count and
        // streak leave it out, and the wrist should agree with them.
        let last = finished.sorted { $0.startedAt > $1.startedAt }.first(where: TrainingStats.isTrained)
        // Asked of the plan the way the phone's Today card asks it, so the
        // wrist never calls "Today" a day the phone calls "Next up".
        let todayIsRotation = today != nil && plan?.day(for: .now) == nil

        return WatchIdleSnapshot(
            // What the rest of this describes. The watch compares it with its
            // own clock, because nothing wakes the phone at midnight to say the
            // training day is over and a wrist raised on a rest day was being
            // shown yesterday's session as today's.
            day: calendar.startOfDay(for: .now),
            todayTitle: today?.name,
            todayExerciseCount: today?.items.count ?? 0,
            todaySetCount: today?.totalSets ?? 0,
            todayMuscles: (today?.targetedMuscles.prefix(3).map(\.name)) ?? [],
            streak: TrainingStats.streak(from: finished).current,
            sessionsThisWeek: finished.filter { $0.startedAt >= weekStart && TrainingStats.isTrained($0) }.count,
            lastSessionTitle: last?.title,
            lastSessionDate: last?.startedAt,
            unit: AppSettings.shared.weightUnit,
            todayIsRotation: todayIsRotation
        )
    }
}
