import Foundation
import HealthKit
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
        if isRunning, sessionID == snapshot.sessionID { return }
        if isRunning { await end(discardingSamples: true) }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard await requestAuthorization() else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        do {
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self

            // Backdate to when the session actually began on the phone, so the
            // workout covers the sets logged before the watch caught up.
            let start = min(snapshot.startedAt, .now)
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)

            self.session = session
            self.builder = builder
            self.sessionID = snapshot.sessionID
            self.startedAt = start
            self.isRunning = true
            log.info("Workout recording started")
        } catch {
            log.error("Couldn't start the workout session: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Ending

    /// Ends the recording. Saving returns the Health workout's ID, which the
    /// phone uses to avoid writing its own copy of the same session.
    @discardableResult
    func end(discardingSamples discard: Bool = false, title: String? = nil, sets: Int = 0, volumeKg: Double = 0) async -> WatchWorkoutMetrics? {
        guard let session, let builder else { return nil }
        let end = Date()
        session.end()

        var metrics = currentMetrics

        if discard {
            builder.discardWorkout()
        } else {
            do {
                if let title {
                    try await builder.addMetadata([
                        HKMetadataKeyIndoorWorkout: true,
                        HKMetadataKeyWorkoutBrandName: "GymTrack",
                        "Session": title,
                        "Sets": sets,
                        "Volume (kg)": volumeKg,
                    ])
                }
                try await builder.endCollection(at: end)
                let workout = try await builder.finishWorkout()
                metrics.healthWorkoutID = workout?.uuid
                log.info("Workout saved to Health")
            } catch {
                log.error("Couldn't save the workout: \(error.localizedDescription, privacy: .public)")
            }
        }

        self.session = nil
        self.builder = nil
        self.sessionID = nil
        self.isRunning = false
        self.startedAt = nil
        self.heartRate = nil
        return metrics
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
            self.isRunning = toState == .running || toState == .paused
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Task { @MainActor in
            self.log.error("Workout session failed: \(error.localizedDescription, privacy: .public)")
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
