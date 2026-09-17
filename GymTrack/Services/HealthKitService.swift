import Foundation
import HealthKit
import SwiftData
import os

/// Everything GymTrack does with Apple Health.
///
/// Three separate jobs, each with its own switch in Settings, because they ask
/// for different things from the user:
///
/// * **Writing workouts** — a finished session becomes an `HKWorkout` of
///   traditional strength training, with one `HKWorkoutActivity` per exercise
///   carrying its sets, reps and volume. That's what makes GymTrack sessions
///   close the Move ring and show up in Fitness alongside everything else.
/// * **Reading back** — heart rate and active energy for the session's window.
///   An Apple Watch worn during the workout records those whether or not the
///   GymTrack watch app was running, so a session gets its numbers either way.
/// * **Body weight** — two-way, so weighing yourself on a connected scale
///   lands in GymTrack and a weight typed into GymTrack lands in Health.
///
/// Nothing here throws at the caller for permission problems: Health is a
/// bonus, never a gate on logging a set.
@MainActor
@Observable
final class HealthKitService {

    static let shared = HealthKitService()

    private let store = HKHealthStore()
    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "com.marwanmohamed.gymtrack", category: "HealthKit")

    /// Set once the authorization sheet has been through. HealthKit
    /// deliberately won't tell us whether reads were granted, so this only
    /// records that we asked.
    private(set) var hasRequestedAuthorization: Bool

    /// Last error worth showing a user, e.g. the Health sheet failing to open.
    var lastErrorMessage: String?

    private init() {
        hasRequestedAuthorization = defaults.bool(forKey: SettingsKey.healthRequested)
    }

    // MARK: - Availability

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// True when we're allowed to add workouts. The read side can't be probed.
    var canWriteWorkouts: Bool {
        isAvailable && store.authorizationStatus(for: .workoutType()) == .sharingAuthorized
    }

    var canWriteBodyMass: Bool {
        guard isAvailable, let type = HKObjectType.quantityType(forIdentifier: .bodyMass) else { return false }
        return store.authorizationStatus(for: type) == .sharingAuthorized
    }

    // MARK: - Types

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        if let bodyMass = HKObjectType.quantityType(forIdentifier: .bodyMass) { types.insert(bodyMass) }
        if let energy = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { types.insert(energy) }
        return types
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType(), HKObjectType.activitySummaryType()]
        for identifier: HKQuantityTypeIdentifier in [.heartRate, .activeEnergyBurned, .basalEnergyBurned, .bodyMass, .restingHeartRate] {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        return types
    }

    // MARK: - Authorization

    /// Shows the Health permission sheet. Safe to call again — iOS only
    /// re-prompts for types the user hasn't answered for yet.
    @discardableResult
    func requestAuthorization() async -> Bool {
        guard isAvailable else {
            lastErrorMessage = "Health isn't available on this device."
            return false
        }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            hasRequestedAuthorization = true
            defaults.set(true, forKey: SettingsKey.healthRequested)
            return true
        } catch {
            log.error("Health authorization failed: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Waking the watch

    /// Asks the system to launch the GymTrack watch app for a strength
    /// workout. Health owns this handshake — it's what lets a session started
    /// on the phone begin recording heart rate without the user having to find
    /// the app on their wrist first.
    func startWatchApp() {
        guard isAvailable, canWriteWorkouts, WatchBridge.shared.isLinked else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor
        store.startWatchApp(with: configuration) { [weak self] started, error in
            if let error {
                self?.log.debug("Couldn't wake the watch app: \(error.localizedDescription, privacy: .public)")
            } else if started {
                self?.log.info("Watch app woken for this session")
            }
        }
    }

    // MARK: - Writing a finished session

    /// Saves a finished session as an `HKWorkout` and returns its Health UUID.
    ///
    /// Returns `nil` — without complaint — when the session is already in
    /// Health (the watch saved it, and it carries the heart rate we'd never
    /// get from the phone), when the user has the switch off, or when the
    /// permission was never granted.
    @discardableResult
    func saveWorkout(for session: WorkoutSession) async -> UUID? {
        guard AppSettings.shared.healthWriteWorkouts, canWriteWorkouts else { return nil }
        guard session.healthWorkoutID == nil else { return nil }

        let completed = session.completedSets
        guard !completed.isEmpty else { return nil }

        let start = session.startedAt
        let end = session.endedAt ?? .now
        guard end > start else { return nil }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        do {
            try await builder.beginCollection(at: start)

            // One activity per exercise, so Health shows the shape of the
            // session rather than a single anonymous block of time. Each one
            // runs from where the last left off to the moment its final set was
            // logged, which is the only interval the app actually knows.
            var cursor = start
            for group in session.exerciseGroups {
                let sets = group.sets.filter(\.isCompleted).sorted { $0.setIndex < $1.setIndex }
                guard let finished = sets.compactMap(\.completedAt).max() else { continue }
                let activityEnd = min(end, max(cursor, finished))
                guard activityEnd > cursor else { continue }

                // The activity spans everything you spent on the exercise,
                // warm-ups included — that time was real. What it's *counted*
                // as is the working sets, so Health and the app agree on the
                // volume rather than disagreeing by a ramp.
                let working = sets.filter { !$0.isWarmup }

                let activity = HKWorkoutActivity(
                    workoutConfiguration: configuration,
                    start: cursor,
                    end: activityEnd,
                    metadata: [
                        Metadata.exercise: group.name,
                        Metadata.sets: working.count,
                        Metadata.reps: working.reduce(0) { $0 + $1.reps },
                        Metadata.volume: working.reduce(0) { $0 + $1.volumeKg },
                        Metadata.topSet: Self.setLabel(working.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }),
                    ]
                )
                // One exercise Health won't take is not a reason to lose the
                // whole workout.
                do {
                    try await builder.addWorkoutActivity(activity)
                    cursor = activityEnd
                } catch {
                    log.debug("Health refused an exercise activity: \(error.localizedDescription, privacy: .public)")
                }
            }

            try await builder.addMetadata([
                HKMetadataKeyIndoorWorkout: true,
                HKMetadataKeyExternalUUID: session.id.uuidString,
                HKMetadataKeyWorkoutBrandName: "GymTrack",
                Metadata.title: session.title,
                Metadata.plan: session.planName,
                Metadata.sets: completed.count,
                Metadata.reps: session.totalReps,
                Metadata.volume: session.totalVolumeKg,
                Metadata.exercises: session.exerciseGroups.count,
            ])

            try await builder.endCollection(at: end)
            let workout = try await builder.finishWorkout()
            session.healthWorkoutID = workout?.uuid
            log.info("Saved session to Health")
            return workout?.uuid
        } catch {
            log.error("Couldn't save workout to Health: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Removes a session's workout from Health. Only ever touches the sample
    /// GymTrack itself wrote — HealthKit refuses anything else anyway.
    func deleteWorkout(id: UUID) async {
        guard isAvailable, canWriteWorkouts else { return }
        let predicate = HKQuery.predicateForObject(with: id)
        do {
            let workouts = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
                }
                store.execute(query)
            }
            guard !workouts.isEmpty else { return }
            try await store.delete(workouts)
        } catch {
            log.error("Couldn't remove workout from Health: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Reading a session's vitals

    struct SessionVitals: Sendable, Equatable {
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var activeEnergyKcal: Double?

        var isEmpty: Bool { averageHeartRate == nil && maxHeartRate == nil && activeEnergyKcal == nil }
    }

    /// Heart rate and active energy recorded during a session's window — by our
    /// watch app, or by the watch simply being worn.
    func vitals(from start: Date, to end: Date) async -> SessionVitals {
        guard isAvailable, AppSettings.shared.healthReadVitals, end > start else { return SessionVitals() }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        async let heart = statistics(
            identifier: .heartRate,
            predicate: predicate,
            options: [.discreteAverage, .discreteMax]
        )
        async let energy = statistics(
            identifier: .activeEnergyBurned,
            predicate: predicate,
            options: .cumulativeSum
        )

        let beats = HKUnit.count().unitDivided(by: .minute())
        let heartStats = await heart
        return SessionVitals(
            averageHeartRate: heartStats?.averageQuantity()?.doubleValue(for: beats),
            maxHeartRate: heartStats?.maximumQuantity()?.doubleValue(for: beats),
            activeEnergyKcal: await energy?.sumQuantity()?.doubleValue(for: .kilocalorie())
        )
    }

    /// Fills in whatever a session is missing. Called right after a workout
    /// ends, and again when its summary is opened — HealthKit can take a
    /// minute to receive the watch's samples.
    func backfillVitals(for session: WorkoutSession) async {
        guard AppSettings.shared.healthReadVitals, session.endedAt != nil else { return }
        let vitals = await vitals(from: session.startedAt, to: session.endedAt ?? .now)
        guard !vitals.isEmpty else { return }
        if let average = vitals.averageHeartRate, session.averageHeartRate == nil {
            session.averageHeartRate = average
        }
        if let max = vitals.maxHeartRate, session.maxHeartRate == nil {
            session.maxHeartRate = max
        }
        if let energy = vitals.activeEnergyKcal, energy > 0, session.activeEnergyKcal == nil {
            session.activeEnergyKcal = energy
        }
    }

    private func statistics(identifier: HKQuantityTypeIdentifier,
                            predicate: NSPredicate,
                            options: HKStatisticsOptions) async -> HKStatistics? {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return nil }
        return await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: options) { _, statistics, _ in
                continuation.resume(returning: statistics)
            }
            store.execute(query)
        }
    }

    // MARK: - Body weight

    /// The most recent body mass in Health, in kilograms.
    func latestBodyMassKg() async -> (kg: Double, date: Date)? {
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return nil }
        let sample: HKQuantitySample? = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
        guard let sample else { return nil }
        return (sample.quantity.doubleValue(for: .gramUnit(with: .kilo)), sample.endDate)
    }

    /// Writes a weigh-in to Health.
    func saveBodyMass(kg: Double, date: Date = .now) async {
        guard AppSettings.shared.healthBodyWeight, canWriteBodyMass,
              let type = HKQuantityType.quantityType(forIdentifier: .bodyMass), kg > 0
        else { return }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date,
            end: date,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        do { try await store.save(sample) } catch {
            log.error("Couldn't save body weight to Health: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Pulls weigh-ins from Health into the app's own history, skipping any day
    /// already recorded so repeated imports don't pile up.
    @discardableResult
    func importBodyMass(into context: ModelContext, since: Date? = nil) async -> Int {
        guard AppSettings.shared.healthBodyWeight,
              isAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .bodyMass)
        else { return 0 }

        let start = since ?? Calendar.current.date(byAdding: .year, value: -2, to: .now)
        let predicate = start.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: []) }
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
        guard !samples.isEmpty else { return 0 }

        let existing = (try? context.fetch(FetchDescriptor<BodyMetric>())) ?? []
        let calendar = Calendar.current
        var days = Set(existing.map { calendar.startOfDay(for: $0.date) })

        var added = 0
        for sample in samples {
            let day = calendar.startOfDay(for: sample.endDate)
            guard !days.contains(day) else { continue }
            days.insert(day)
            let metric = BodyMetric(date: sample.endDate, weightKg: sample.quantity.doubleValue(for: .gramUnit(with: .kilo)))
            metric.source = BodyMetric.Source.health.rawValue
            context.insert(metric)
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    // MARK: - Metadata keys

    /// Custom metadata keys. Health shows unknown keys verbatim in the workout
    /// detail, so they're written as sentences rather than identifiers.
    private enum Metadata {
        static let title = "Session"
        static let plan = "Routine"
        static let sets = "Sets"
        static let reps = "Reps"
        static let volume = "Volume (kg)"
        static let exercises = "Exercises"
        static let exercise = "Exercise"
        static let topSet = "Top set"
    }

    private static func setLabel(_ set: SetLog?) -> String {
        guard let set else { return "—" }
        if set.tracking == .duration { return "\(set.seconds)s" }
        if set.weightKg == 0 { return "\(set.reps) reps" }
        return "\(String(format: "%.1f", set.weightKg)) kg × \(set.reps)"
    }
}
