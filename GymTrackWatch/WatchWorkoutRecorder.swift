import Foundation
import HealthKit
import Observation
import os

/// Runs a real `HKWorkoutSession` on the watch for the length of a GymTrack
/// session.
///
/// This is what makes the watch worth wearing for lifting: it takes the heart
/// rate sensor off its idle sampling rate, keeps the app alive between sets
/// with the wrist down, lights the always-on display with the set that's up,
/// and — when the session ends — saves the workout to Health so the rings move
/// and the beat-by-beat record is kept.
///
/// The phone is told the numbers as they change, and is handed the saved
/// workout's ID at the end so it knows not to write a second copy.
@MainActor
@Observable
final class WatchWorkoutRecorder: NSObject {

    static let shared = WatchWorkoutRecorder()

    private(set) var isRunning = false
    private(set) var startedAt: Date?
    private(set) var heartRate: Double?
    private(set) var averageHeartRate: Double?
    private(set) var maxHeartRate: Double?
    private(set) var activeEnergyKcal: Double?
    private(set) var authorizationDenied = false

    /// The GymTrack session this recording belongs to, so a workout that ends
    /// on the phone while the watch is asleep doesn't leave a session running.
    private(set) var sessionID: UUID?

    private let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var lastMetricsSentAt: Date = .distantPast
    /// Set synchronously while a start is in flight. See `startIfNeeded`.
    private(set) var isStarting = false
    /// Set by `end` when it lands while a start is still waiting on Health, so
    /// the start closes what it built instead of committing it.
    private var startCancelled = false
    /// Set while a workout watchOS kept through a crash is being taken back.
    /// Starts wait it out: a second session built beside the recovered one
    /// fails, or orphans it.
    private var isRecovering = false
    /// What watchOS launched the app to do. See `followConnector`.
    private var launchDuty: LaunchDuty?
    /// The loop that asks the idle rule while a recording runs. See
    /// `watchForIdle`.
    private var idleCheck: Task<Void, Never>?
    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack.watchkitapp", category: "Workout")

    private override init() { super.init() }

    // MARK: - Authorization

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier: HKQuantityTypeIdentifier in [.heartRate, .activeEnergyBurned, .basalEnergyBurned] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        return types
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            authorizationDenied = false
            return true
        } catch {
            log.error("Health authorization failed: \(error.localizedDescription, privacy: .public)")
            authorizationDenied = true
            return false
        }
    }

    // MARK: - Starting

    /// Starts recording for a session. Safe to call on every mirror — it does
    /// nothing if this session is already being recorded, and hands over
    /// cleanly if a different one has started.
    func startIfNeeded(for snapshot: WatchSessionSnapshot) async {
        // A session ended on this wrist already has its workout, or was thrown
        // away. The stale mirror that names it after a relaunch must not buy
        // it a second one, backdated to its start.
        guard WatchConnector.shared.admitsRecording(of: snapshot.sessionID) else { return }
        if isRunning, sessionID == snapshot.sessionID { return }
        // Claimed before the first `await`. @MainActor is re-entrant — the
        // actor is released at every suspension — so without this flag two
        // overlapping calls both pass the `isRunning` check above, both build
        // an HKWorkoutSession, and the second orphans the first while it is
        // still running and still holding an extended runtime assertion.
        guard !isStarting, !isRecovering else { return }
        isStarting = true
        defer { isStarting = false }

        var next: WatchSessionSnapshot? = snapshot
        while let target = next {
            await start(target)
            next = sessionToHandOverTo(after: target.sessionID)
        }
    }

    /// One attempt at recording a session. Each `await` below is followed by
    /// `stillWanted`, because each can outlast the session it is for.
    private func start(_ snapshot: WatchSessionSnapshot) async {
        let id = snapshot.sessionID
        startCancelled = false
        if session != nil { await closeAsPhoneEnded() }
        guard stillWanted(id), HKHealthStore.isHealthDataAvailable() else { return }
        guard await mayRunWorkoutSession(), stillWanted(id) else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        var opened: (session: HKWorkoutSession, builder: HKLiveWorkoutBuilder)?
        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            // Backdate to when the session actually began on the phone, so the
            // workout covers the sets logged before the watch caught up.
            let start = min(snapshot.startedAt, .now)
            WatchRecordingRecord(sessionID: id, startedAt: start).save(to: defaults)
            session.startActivity(with: start)
            opened = (session, builder)
            try await builder.beginCollection(at: start)

            // Finish or Discard can be tapped, on either device, while this
            // start still waits on Health. `end` found nothing to close then,
            // so the recording would run on for a session that is over, and
            // be saved as a second workout or feed its readings to the
            // finished one.
            guard stillWanted(id) else {
                abandon(session, builder)
                return
            }

            self.session = session
            self.builder = builder
            self.sessionID = id
            self.startedAt = start
            self.isRunning = true
            watchForIdle()
            log.info("Workout recording started")
        } catch {
            // A session whose collection never began has nothing worth
            // keeping, and left running it holds the sensor and the runtime
            // with nothing reading them.
            if let opened { abandon(opened.session, opened.builder) }
            log.error("Couldn't start the workout session: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func stillWanted(_ id: UUID) -> Bool {
        let connector = WatchConnector.shared
        return WatchRecordingRules.stillWanted(id, liveSessionID: connector.session?.sessionID,
                                               admitted: connector.admitsRecording(of: id),
                                               cancelled: startCancelled)
    }

    private func sessionToHandOverTo(after attempted: UUID?) -> WatchSessionSnapshot? {
        guard let live = WatchConnector.shared.session,
              WatchRecordingRules.handsOver(from: attempted, toLive: live.sessionID, recording: sessionID)
        else { return nil }
        return live
    }

    private func mayRunWorkoutSession() async -> Bool {
        let granted = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        switch WatchRecordingRules.permission(healthEnabled: WatchConnector.shared.mirror.healthEnabled,
                                              workoutSharingAuthorized: granted) {
        case .ask: return await requestAuthorization()
        case .granted: return true
        case .withheld: return false
        }
    }

    /// Ends a session this recorder built but never took on, leaving nothing
    /// in Health.
    private func abandon(_ session: HKWorkoutSession, _ builder: HKLiveWorkoutBuilder) {
        session.end()
        builder.discardWorkout()
        WatchRecordingRecord.clear(from: defaults)
    }

    // MARK: - Ending

    /// Ends the recording. Saving returns the Health workout's ID, which the
    /// phone uses to avoid writing its own copy of the same session.
    @discardableResult
    func end(discardingSamples discard: Bool = false) async -> WatchWorkoutMetrics? {
        // A start still waiting on Health has built nothing this could close.
        // Left alone, it went on to record a session that had just ended;
        // marked, it closes what it built as soon as the wait is over.
        if isStarting { startCancelled = true }
        return await close(discardingSamples: discard, snapshot: WatchConnector.shared.lastMirroredSession)
    }

    /// Closes the recording if the phone has said its session is over. Called
    /// whenever the phone's session disappears from the wrist.
    func closeIfSessionOver() async {
        guard let recording = sessionID, phoneHasEnded(recording) else { return }
        await closeAsPhoneEnded()
    }

    private func phoneHasEnded(_ recording: UUID) -> Bool {
        let connector = WatchConnector.shared
        return WatchRecordingRules.sessionIsOver(recording: recording,
                                                 liveSessionID: connector.session?.sessionID,
                                                 mirroredSessionID: connector.mirror.session?.sessionID,
                                                 heardFromPhone: connector.hasEverReceivedMirror,
                                                 admitted: connector.admitsRecording(of: recording))
    }

    private func closeAsPhoneEnded() async {
        guard let recording = sessionID else { return }
        let connector = WatchConnector.shared
        let plan = WatchRecordingRules.closeAfterPhoneEnd(connector.mirror.endedSession, recording: recording,
                                                          healthEnabled: connector.mirror.healthEnabled)
        // The last snapshot the wrist holds is all it can say about a session
        // the phone has ended: the phone's own summary never comes.
        let metrics = await close(discardingSamples: plan.discards, endingAt: idleEnd(of: recording),
                                  snapshot: connector.lastMirroredSession)
        if plan.reportsMetrics, let metrics { connector.send(.metrics(metrics)) }
    }

    /// Where a recording the phone ended stops, if the session had gone idle.
    ///
    /// The phone closes a session left open at its last set, and says only
    /// that it finished. A recording still running then, from a wrist whose
    /// idle rule never got the chance, saved a workout ending on arrival:
    /// hours past the last set, and linked in place of the phone's own.
    private func idleEnd(of recording: UUID) -> Date? {
        guard let last = WatchConnector.shared.lastMirroredSession, last.sessionID == recording,
              case .finish(let moment) = WatchRecordingRules.idleVerdict(for: last, now: .now)
        else { return nil }
        return moment
    }

    /// A recording the recorder has let go of: the builder still to be saved
    /// or discarded, and the figures it had reached.
    private struct Release {
        var builder: HKLiveWorkoutBuilder
        var metrics: WatchWorkoutMetrics
    }

    /// Lets go of the running recording without suspending, so nothing else
    /// can close it twice.
    private func release() -> Release? {
        guard let session, let builder else { return nil }
        let released = Release(builder: builder, metrics: currentMetrics)
        // Let go before the first suspension. A second end arriving while
        // Health saves, from a mirror that changed again, found the same
        // builder still held and raced a discard against the save.
        reset()
        session.end()
        return released
    }

    private func close(discardingSamples discard: Bool, endingAt: Date? = nil,
                       snapshot: WatchSessionSnapshot? = nil) async -> WatchWorkoutMetrics? {
        await save(release(), discarding: discard, endingAt: endingAt, snapshot: snapshot)
    }

    private func save(_ released: Release?, discarding discard: Bool, endingAt: Date?,
                      snapshot: WatchSessionSnapshot?) async -> WatchWorkoutMetrics? {
        guard let released else { return nil }
        let builder = released.builder
        var metrics = released.metrics
        let end = WatchRecordingRules.recordingEnd(requested: endingAt, recordingStartedAt: builder.startDate,
                                                   now: .now)

        if discard {
            builder.discardWorkout()
        } else {
            do {
                // Every save says which GymTrack session it is, however the
                // session ended: the external UUID is the only link from a
                // Health workout back to its session if the metrics hand-over
                // is lost. The title and totals are only what the last
                // snapshot held, and an absent one is left out.
                let said = WatchWorkoutMetadata(recording: metrics.sessionID, snapshot: snapshot)
                try await builder.addMetadata(Self.healthMetadata(said))
                try await builder.endCollection(at: end)
                let workout = try await builder.finishWorkout()
                metrics.healthWorkoutID = workout?.uuid
                if endingAt != nil { metrics = Self.measured(metrics, by: workout) }
                log.info("Workout saved to Health")
            } catch {
                log.error("Couldn't save the workout: \(error.localizedDescription, privacy: .public)")
            }
        }
        return metrics
    }

    /// The workout's metadata as Health keys it. The brand and the indoor flag
    /// are facts about this app's recording; everything else is written only
    /// when the wrist has it.
    private static func healthMetadata(_ said: WatchWorkoutMetadata) -> [String: Any] {
        var metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: true,
            HKMetadataKeyWorkoutBrandName: "GymTrack",
        ]
        if let id = said.sessionID { metadata[HKMetadataKeyExternalUUID] = id.uuidString }
        if let title = said.title { metadata["Session"] = title }
        if let sets = said.sets { metadata["Sets"] = sets }
        if let volume = said.volumeKg { metadata["Volume (kg)"] = volume }
        return metadata
    }

    /// The heart rate and energy of a workout that ended before now, read off
    /// the workout as saved.
    ///
    /// The sensor's running figures include every idle minute after the last
    /// set, and sent as the session's numbers they would describe a workout
    /// that never ended. What Health cannot say is left out rather than filled
    /// from them.
    private static func measured(_ metrics: WatchWorkoutMetrics, by workout: HKWorkout?) -> WatchWorkoutMetrics {
        var result = metrics
        let beats = HKUnit.count().unitDivided(by: .minute())
        let heart = HKQuantityType.quantityType(forIdentifier: .heartRate).flatMap { workout?.statistics(for: $0) }
        let energy = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
            .flatMap { workout?.statistics(for: $0) }
        result.averageHeartRate = heart?.averageQuantity()?.doubleValue(for: beats)
        result.maxHeartRate = heart?.maximumQuantity()?.doubleValue(for: beats)
        result.activeEnergyKcal = energy?.sumQuantity()?.doubleValue(for: .kilocalorie())
        return result
    }

    // MARK: - Ending on the wrist

    /// Ends the session on this wrist: the lifter's Finish, or the idle rule's
    /// on their behalf, which has to be the same thing down to the order.
    ///
    /// Everything up to the returned task happens at the call, before anything
    /// can suspend: the batch is the wrist's state at the tap, and the session
    /// is marked ended before a mirror still calling it live can arrive and
    /// start it recording again. The recording is let go before the mark, so
    /// the view seeing the session vanish finds nothing left to close; closed
    /// from there, it would have been closed as a phone end and discarded.
    ///
    /// - Parameter endingAt: when the lifter stopped, for a session the idle
    ///   rule ends; `nil` for a Finish tapped now.
    @discardableResult
    func finishOnWrist(_ snapshot: WatchSessionSnapshot, endingAt: Date? = nil) -> Task<Void, Never> {
        let connector = WatchConnector.shared
        var batch = connector.finishBatch(for: snapshot.sessionID)
        if let endingAt { batch.endedAt = endingAt }
        let discard = WatchRecordingRules.discardsOnWristFinish(healthEnabled: connector.mirror.healthEnabled,
                                                                setsLogged: snapshot.completedSets)
        // A start still waiting on Health has built nothing to release. Left
        // alone, it went on to record a session that had just ended; marked,
        // it closes what it built as soon as the wait is over.
        if isStarting { startCancelled = true }
        let released = release()
        connector.markEndedLocally(snapshot.sessionID)
        return Task {
            let metrics = await save(released, discarding: discard, endingAt: endingAt, snapshot: snapshot)
            // A Finish with nothing logged still goes as a Finish, never as a
            // Discard. The phone holds the truth about what was logged, and
            // deletes the session only if it agrees nothing was; a Discard
            // from a wrist that missed a set logged on the phone deleted it.
            connector.send(.finishSession(batch, metrics: metrics))
        }
    }

    /// Finishes the recorded session if nobody has logged or started a set in
    /// it for `WatchRecordingRules.idleFinishAfter`. No prompt and no tap: a
    /// question on the wrist is exactly what a lifter who has gone home will
    /// not answer.
    func finishIfIdle(now: Date = .now) {
        guard isRunning, !isStarting, let recording = sessionID,
              let live = WatchConnector.shared.session, live.sessionID == recording
        else { return }
        switch WatchRecordingRules.idleVerdict(for: live, now: now) {
        case .keepRecording:
            return
        case .finish(let moment):
            log.info("Idle session finished at its last set")
            finishOnWrist(live, endingAt: moment)
        case .discard:
            log.info("Idle session with nothing logged discarded")
            finishOnWrist(live, endingAt: WatchRecordingRules.lastActivity(in: live))
        }
    }

    /// Asks the idle rule once a minute for as long as this recording runs.
    ///
    /// A timer rather than a check on each builder update, because updates
    /// come from the sensor, and a watch taken off the wrist and left in a bag
    /// stops sending them: the recording nobody is wearing is the one that
    /// most needs ending. The workout session keeps the app running in the
    /// background, so the loop runs with the screen off.
    private func watchForIdle() {
        idleCheck?.cancel()
        idleCheck = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(WatchRecordingRules.idleCheckInterval))
                guard !Task.isCancelled, let self else { return }
                self.finishIfIdle()
            }
        }
    }

    private func reset() {
        idleCheck?.cancel()
        idleCheck = nil
        session = nil
        builder = nil
        sessionID = nil
        isRunning = false
        startedAt = nil
        heartRate = nil
        averageHeartRate = nil
        maxHeartRate = nil
        activeEnergyKcal = nil
        lastMetricsSentAt = .distantPast
        WatchRecordingRecord.clear(from: defaults)
    }

    // MARK: - Launched by watchOS

    /// Work watchOS launched the app for. It cannot wait for a view's task:
    /// a launch in the background may never draw one.
    private enum LaunchDuty {
        /// The phone started a workout and woke this app to record it.
        case startPhoneWorkout
        /// A recovered workout waits for the phone to say whether its session
        /// is still going.
        case settleRecovery
    }

    /// Called when the phone launches the app for a workout. Which session it
    /// is arrives with the phone's mirror, so recording begins the moment that
    /// lands rather than at the next wrist raise, which left the first sets
    /// with no heart rate.
    func startWhenPhoneSessionArrives() {
        launchDuty = .startPhoneWorkout
        followConnector()
    }

    /// Picks up the workout watchOS kept running while the app crashed.
    ///
    /// Without this, the relaunched app built a second session backdated to
    /// the same start while the system still held the first, whose samples
    /// were never finished.
    func recoverActiveWorkout() async {
        guard !isStarting, !isRecovering, session == nil else { return }
        isRecovering = true
        await takeBackRecoveredSession()
        isRecovering = false
        // A start turned away while the recovery ran is not asked again.
        if let live = sessionToHandOverTo(after: nil) {
            await startIfNeeded(for: live)
        }
    }

    private func takeBackRecoveredSession() async {
        let recovered: HKWorkoutSession?
        do {
            recovered = try await store.recoverActiveWorkoutSession()
        } catch {
            log.error("Couldn't recover the workout session: \(error.localizedDescription, privacy: .public)")
            recovered = nil
        }
        guard let recovered else {
            WatchRecordingRecord.clear(from: defaults)
            return
        }
        let builder = recovered.associatedWorkoutBuilder()
        let record = WatchRecordingRecord(defaults: defaults)
        switch WatchRecordingRules.recovery(of: record, admits: { WatchConnector.shared.admitsRecording(of: $0) }) {
        case .discard:
            abandon(recovered, builder)
            log.info("Recovered workout discarded")
        case .adopt(let record):
            recovered.delegate = self
            builder.delegate = self
            if builder.dataSource == nil {
                builder.dataSource = HKLiveWorkoutDataSource(healthStore: store,
                                                             workoutConfiguration: recovered.workoutConfiguration)
            }
            session = recovered
            self.builder = builder
            sessionID = record.sessionID
            startedAt = builder.startDate ?? record.startedAt
            isRunning = true
            watchForIdle()
            log.info("Workout recording recovered")
            launchDuty = .settleRecovery
            followConnector()
        }
    }

    /// Carries out `launchDuty` once the connector knows enough, and re-arms
    /// on every change to it until then.
    private func followConnector() {
        guard let duty = launchDuty else { return }
        let connector = WatchConnector.shared
        let live = withObservationTracking {
            _ = connector.hasEverReceivedMirror
            _ = connector.mirror
            return connector.session
        } onChange: {
            Task { @MainActor in self.followConnector() }
        }

        switch duty {
        case .startPhoneWorkout:
            guard let live else { return }
            launchDuty = nil
            Task { await startIfNeeded(for: live) }
        case .settleRecovery:
            guard let recording = sessionID, live?.sessionID != recording else {
                launchDuty = nil
                return
            }
            guard phoneHasEnded(recording) else { return }
            launchDuty = nil
            Task { await closeIfSessionOver() }
        }
    }

    // MARK: - Metrics

    var currentMetrics: WatchWorkoutMetrics {
        WatchWorkoutMetrics(
            sessionID: sessionID,
            currentHeartRate: heartRate,
            averageHeartRate: averageHeartRate,
            maxHeartRate: maxHeartRate,
            activeEnergyKcal: activeEnergyKcal,
            healthWorkoutID: nil
        )
    }

    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    private func update(from builder: HKLiveWorkoutBuilder, types: Set<HKSampleType>) {
        // A builder that has just been closed can still report its last
        // samples. Read as current, they would refill the numbers `end`
        // cleared and go out under whichever session starts next.
        guard builder === self.builder else { return }
        let beats = HKUnit.count().unitDivided(by: .minute())
        for type in types {
            guard let quantityType = type as? HKQuantityType,
                  let statistics = builder.statistics(for: quantityType)
            else { continue }

            switch quantityType.identifier {
            case HKQuantityTypeIdentifier.heartRate.rawValue:
                heartRate = statistics.mostRecentQuantity()?.doubleValue(for: beats)
                averageHeartRate = statistics.averageQuantity()?.doubleValue(for: beats)
                maxHeartRate = statistics.maximumQuantity()?.doubleValue(for: beats)
            case HKQuantityTypeIdentifier.activeEnergyBurned.rawValue:
                activeEnergyKcal = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            default:
                break
            }
        }
        sendMetricsIfDue()
    }

    /// The phone shows the live heart rate in its logger and on the Lock
    /// Screen, but a push per sample would be a message every second or two
    /// for the whole workout.
    private func sendMetricsIfDue(force: Bool = false) {
        // Once the wrist has ended the session, the metrics its Finish carries
        // are the last word. A live reading still in flight could land after
        // them and write over the finished session's heart rate and energy.
        if let sessionID, !WatchConnector.shared.admitsRecording(of: sessionID) { return }
        guard force || Date().timeIntervalSince(lastMetricsSentAt) > 5 else { return }
        lastMetricsSentAt = .now
        WatchConnector.shared.send(.metrics(currentMetrics))
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WatchWorkoutRecorder: HKWorkoutSessionDelegate {

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState,
                                    date: Date) {
        Task { @MainActor in
            // A session this recorder has let go of, or not yet taken on,
            // still reports its transitions. The `.ended` of an abandoned
            // start landing after the next session began hid the running one
            // from every check on `isRunning`, and the next start built a
            // second session over it.
            guard workoutSession === self.session else { return }
            self.isRunning = toState == .running || toState == .paused
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.log.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
            guard workoutSession === self.session else { return }
            self.isRunning = false
        }
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WatchWorkoutRecorder: HKLiveWorkoutBuilderDelegate {

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>) {
        Task { @MainActor in self.update(from: workoutBuilder, types: collectedTypes) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
