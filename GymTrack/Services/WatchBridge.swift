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

    private var revision = 0
    private var idle: WatchIdleSnapshot = .empty
    private var sessionSnapshot: WatchSessionSnapshot?
    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack", category: "WatchBridge")

    private override init() {
        super.init()
    }

    // MARK: - Lifecycle

    /// Called once at launch. Safe on devices with no watch — `isSupported`
    /// stays false and every push below is a no-op.
    func activate() {
        guard WCSession.isSupported() else { return }
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
        guard idle != snapshot else { return }
        idle = snapshot
        push()
    }

    /// The running session, or `nil` once it ends.
    func update(session snapshot: WatchSessionSnapshot?) {
        guard sessionSnapshot != snapshot else { return }
        // A session ending is also the moment the watch should stop its own
        // workout, so that transition is always worth a push.
        sessionSnapshot = snapshot
        if snapshot == nil { liveMetrics = nil }
        push()
    }

    /// Re-sends the current mirror — for a watch that just asked, or that just
    /// became reachable.
    func resend() { push() }

    private func push() {
        guard isSupported, WCSession.default.activationState == .activated else { return }
        revision += 1
        let mirror = WatchMirror(
            revision: revision,
            sentAt: .now,
            idle: idle,
            session: sessionSnapshot,
            healthEnabled: AppSettings.shared.healthWriteWorkouts
        )
        let payload = mirror.watchPayload(key: WatchLink.mirrorKey)
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

    // MARK: - Receiving

    private func handle(_ payload: [String: Any]) {
        guard let command = WatchCommand.fromWatchPayload(payload, key: WatchLink.commandKey) else { return }
        if case .metrics(let metrics) = command {
            liveMetrics = merge(metrics)
        }
        if case .finish(let metrics) = command, let metrics {
            liveMetrics = merge(metrics)
        }
        commandHandler?(command)
    }

    /// The watch sends whatever it has to hand; keep the best of both so a
    /// payload carrying only a current heart rate doesn't wipe the average.
    private func merge(_ incoming: WatchWorkoutMetrics) -> WatchWorkoutMetrics {
        var result = liveMetrics ?? WatchWorkoutMetrics()
        if let value = incoming.currentHeartRate { result.currentHeartRate = value }
        if let value = incoming.averageHeartRate { result.averageHeartRate = value }
        if let value = incoming.maxHeartRate { result.maxHeartRate = max(value, result.maxHeartRate ?? 0) }
        if let value = incoming.activeEnergyKcal { result.activeEnergyKcal = value }
        if let value = incoming.healthWorkoutID { result.healthWorkoutID = value }
        return result
    }

    func clearMetrics() { liveMetrics = nil }
}

// MARK: - WCSessionDelegate

extension WatchBridge: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        Task { @MainActor in
            self.refreshStatus()
            if state == .activated { self.push() }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Switching to a different watch hands us a fresh session to activate.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshStatus()
            self.push()
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in
            self.refreshStatus()
            // A watch that just came back may have missed everything.
            if session.isReachable { self.push() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in self.handle(message) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveMessage message: [String: Any],
                             replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            self.handle(message)
            replyHandler([WatchLink.ackKey: true])
        }
    }

    /// Queued delivery — what a set logged out of range arrives on.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        Task { @MainActor in self.handle(userInfo) }
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
        let today = plan?.day(for: .now)
        let calendar = Calendar.current
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .distantPast
        let last = finished.max { $0.startedAt < $1.startedAt }

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
            sessionsThisWeek: finished.filter { $0.startedAt >= weekStart }.count,
            lastSessionTitle: last?.title,
            lastSessionDate: last?.startedAt,
            unit: AppSettings.shared.weightUnit
        )
    }
}
