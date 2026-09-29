import Foundation
import HealthKit
import SwiftData
import UIKit
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

    /// Shared by launch, Settings and the body-weight card so two Health
    /// queries cannot both decide that the same day is missing.
    @ObservationIgnored private var bodyMassImportInFlight = false

    /// A phone fallback may have finished just before the watch sends its
    /// richer workout, and a deleted session's workout is left with no owner.
    /// The list of workouts waiting for Health to remove them (see
    /// `PendingWorkoutCleanup`) is kept here, across an app restart.
    private static let pendingWorkoutCleanupKey = "health.pendingWorkoutCleanup"
    /// The workouts this phone wrote itself, newest last. The session's link
    /// alone cannot say whose workout it is, and only the phone's own fallback
    /// may be replaced by a later watch save; see `WatchWorkoutLink`. A late
    /// watch save lands within hours, so the list only needs recent sessions.
    private static let phoneWrittenWorkoutsKey = "health.phoneWrittenWorkouts"
    private static let phoneWrittenWorkoutsLimit = 64
    @ObservationIgnored private var cleanupContainer: ModelContainer?
    @ObservationIgnored private var cleanupGate = CleanupPassGate()
    /// How many workouts the cleanup list has stopped trying to remove. Settings
    /// shows a line only while this is above zero. See `CleanupAttemptLedger`.
    private(set) var givenUpCleanupCount = 0
    private static let cleanupAttemptsKey = "health.cleanupAttempts"
    @ObservationIgnored private var protectedDataObserver: NSObjectProtocol?

    private init() {
        hasRequestedAuthorization = defaults.bool(forKey: SettingsKey.healthRequested)
        givenUpCleanupCount = loadAttemptLedger().givenUp.count
    }

    /// Connects pending Health cleanup to the persistent sessions. This runs
    /// before a watch command can finish a newly recovered session.
    func configure(container: ModelContainer) {
        cleanupContainer = container
        observeProtectedData()
        Task { await retryPendingWorkoutCleanup() }
    }

    /// Tries the cleanup list again the moment a locked phone opens Health's
    /// database. A delete refused while locked would otherwise wait for the
    /// next foreground, and a phone unlocked in a pocket may not have one for
    /// days. Registered once, from `configure`, because a watch message can
    /// wake the app with no view to do it.
    private func observeProtectedData() {
        guard protectedDataObserver == nil else { return }
        protectedDataObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.protectedDataDidBecomeAvailableNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.retryPendingWorkoutCleanup() }
        }
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

    /// Quantities the phone reads: heart rate and active energy over a
    /// session's window, and body weight for the two-way sync. Workouts are
    /// read as well, to find the one a session was saved as.
    ///
    /// Each is asked for because a query above uses it. Resting heart rate,
    /// basal energy and the activity summary used to be here with no reader:
    /// the Health sheet listed toggles for data the app had decided never to
    /// use, and resting heart rate is recovery data, which the product has
    /// rejected. A permission nothing needs is also one a later change can
    /// start using without anyone noticing. Adding a type here means adding the
    /// code that reads it in the same change; `HealthPermissionSetTests`
    /// compares the two.
    private static let readQuantityIdentifiers: [HKQuantityTypeIdentifier] = [
        .heartRate, .activeEnergyBurned, .bodyMass,
    ]

    /// Quantities the phone writes. Only body weight: the workout builder adds
    /// no energy samples of its own, so share access to active energy was never
    /// exercised.
    private static let shareQuantityIdentifiers: [HKQuantityTypeIdentifier] = [.bodyMass]

    private var shareTypes: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        for identifier in Self.shareQuantityIdentifiers {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) { types.insert(type) }
        }
        return types
    }

    private var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [HKObjectType.workoutType()]
        for identifier in Self.readQuantityIdentifiers {
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
            await retryPendingWorkoutCleanup()
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
        // Permission, never the "Save workouts to Health" switch. The watch
        // runs its workout session with saving off and discards it at the
        // end, because that session is what keeps it awake for heart rate and
        // the rest-over haptic. Following the switch would leave the watch
        // asleep for everyone who turned saving off.
        guard isAvailable, WatchBridge.shared.isLinked,
              store.authorizationStatus(for: .workoutType()) == .sharingAuthorized else { return }
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
        guard PhoneWorkoutWrite.shouldWrite(sessionGone: session.isGoneFromStore,
                                            linkedWorkoutID: session.healthWorkoutID) else { return nil }

        let completed = session.completedSets
        guard !completed.isEmpty else { return nil }

        let sessionID = session.id
        let start = session.startedAt
        let end = session.endedAt ?? .now
        guard end > start else { return nil }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        configuration.locationType = .indoor

        // Everything Health is told is read off the session before the first
        // await. After one, the session may be gone, and a deleted model is not
        // something to read a title from.
        let activities = Self.exerciseActivities(of: session, from: start, to: end,
                                                 configuration: configuration)
        let metadata: [String: Any] = [
            HKMetadataKeyIndoorWorkout: true,
            HKMetadataKeyExternalUUID: sessionID.uuidString,
            HKMetadataKeyWorkoutBrandName: "GymTrack",
            Metadata.title: session.title,
            Metadata.plan: session.planName,
            Metadata.sets: completed.count,
            Metadata.reps: session.totalReps,
            Metadata.volume: session.totalVolumeKg,
            Metadata.exercises: session.exerciseGroups.count,
        ]

        let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())

        // Each of Health's calls suspends, and the whole write can take
        // seconds. A session deleted, erased or restored over meanwhile must
        // not get a workout: nothing in the app could find it to remove it.
        func abandoned() -> Bool {
            guard isGone(session, id: sessionID) else { return false }
            builder.discardWorkout()
            log.info("Stopped writing a session to Health; it was removed meanwhile")
            return true
        }

        do {
            try await builder.beginCollection(at: start)
            if abandoned() { return nil }

            for activity in activities {
                // One exercise Health won't take is not a reason to lose the
                // whole workout.
                do {
                    try await builder.addWorkoutActivity(activity)
                } catch {
                    log.debug("Health refused an exercise activity: \(error.localizedDescription, privacy: .public)")
                }
                if abandoned() { return nil }
            }

            try await builder.addMetadata(metadata)
            if abandoned() { return nil }
            try await builder.endCollection(at: end)
            if abandoned() { return nil }
            let workout = try await builder.finishWorkout()
            // Gone during the last call, when there is no builder left to
            // discard: the workout is already in Health. It goes on the same
            // durable list as a replaced fallback, so a refused or unverifiable
            // delete is retried on a later launch instead of forgotten. No
            // session links to it, so the list has nothing to relink.
            //
            // A watch can also finish while this builder is suspended. Its
            // record has the measured samples; remove the phone's just-written
            // copy rather than replacing the ID and leaving both in Health.
            switch PhoneWorkoutWrite.outcome(written: workout?.uuid,
                                             sessionGone: isGone(session, id: sessionID),
                                             linkedWorkoutID: session.healthWorkoutID) {
            case .nothing:
                return nil
            case .removeAsOrphan:
                if let workout {
                    enqueueCleanup(workoutID: workout.uuid, sessionID: sessionID,
                                   preferredWorkoutID: workout.uuid)
                    await retryPendingWorkoutCleanup()
                }
                return nil
            case .removeAsDuplicate(let watchID):
                if let workout {
                    enqueueCleanup(workoutID: workout.uuid, sessionID: sessionID,
                                   preferredWorkoutID: watchID)
                    await retryPendingWorkoutCleanup()
                }
                return nil
            case .link:
                guard let workout else { return nil }
                notePhoneWritten(workout.uuid)
                session.healthWorkoutID = workout.uuid
                log.info("Saved session to Health")
                return workout.uuid
            }
        } catch {
            log.error("Couldn't save workout to Health: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// One activity per stretch of the session spent on one exercise, in the
    /// order the sets were logged, so Health shows the shape of the session
    /// rather than a single anonymous block of time. See
    /// `WorkoutActivitySegmentation` for where each one starts and ends.
    private static func exerciseActivities(of session: WorkoutSession, from start: Date, to end: Date,
                                           configuration: HKWorkoutConfiguration) -> [HKWorkoutActivity] {
        let groups = session.exerciseGroups
        let names = Dictionary(groups.map { ($0.catalogID, $0.name) }, uniquingKeysWith: { first, _ in first })
        let logged = groups.flatMap(\.sets).filter(\.isCompleted)
        let byID = Dictionary(logged.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let stamps = logged.compactMap { set in
            set.completedAt.map {
                ActivitySetStamp(id: set.id, exercise: set.catalogID, startedAt: set.startedAt, completedAt: $0)
            }
        }

        return WorkoutActivitySegmentation.runs(of: stamps, sessionStart: start, sessionEnd: end).map { run in
            let sets = run.setIDs.compactMap { byID[$0] }
            // Sets and the top set are read off the efforts, the way every
            // screen in the app reads them: a drop is one set taken further,
            // and its light back-off row for a pile of reps estimates a
            // higher one-rep max than the set it came off. Reps and volume
            // keep every row, because that work happened.
            let efforts = sets.filter { !$0.isContinuation }
            return HKWorkoutActivity(
                workoutConfiguration: configuration,
                start: run.start,
                end: run.end,
                metadata: [
                    Metadata.exercise: names[run.exercise] ?? run.exercise,
                    Metadata.sets: efforts.count,
                    Metadata.reps: sets.reduce(0) { $0 + $1.reps },
                    Metadata.volume: sets.reduce(0) { $0 + $1.volumeKg },
                    Metadata.topSet: setLabel(efforts.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }),
                ]
            )
        }
    }

    /// Whether a session held across an await has left the store.
    ///
    /// The store is asked as well as the instance, because a session finished
    /// headlessly is held by the watch command center's context while an
    /// erase from the screen deletes through another, and that leaves this
    /// instance looking alive. `id` is taken before the first await, so the
    /// check never has to read the session to find it.
    private func isGone(_ session: WorkoutSession, id: UUID) -> Bool {
        session.isGone(fromStore: FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == id }))
    }

    /// A late watch save makes the measured workout the session's link. The
    /// phone fallback stays on a durable cleanup list until Health removes it;
    /// otherwise a missed read permission or an app restart strands a copy.
    ///
    /// Only the phone's own fallback gives way. A watch workout already linked
    /// is the one saved when the session ended, and a later one is a recording
    /// restarted after it: taking that instead queued the accurate workout for
    /// deletion and linked a copy with no metadata and an inflated duration.
    func acceptWatchWorkout(_ watchID: UUID, for session: WorkoutSession, context: ModelContext) {
        let phoneWritten = Set(phoneWrittenWorkouts())
        switch WatchWorkoutLink.decide(current: session.healthWorkoutID, incoming: watchID,
                                       phoneWritten: phoneWritten) {
        case .alreadyLinked:
            return
        case .link:
            session.healthWorkoutID = watchID
        case .replacePhoneFallback(let previousID):
            enqueueCleanup(workoutID: previousID, sessionID: session.id,
                           preferredWorkoutID: watchID)
            session.healthWorkoutID = watchID
            try? context.save()
            Task { await retryPendingWorkoutCleanup() }
        case .keepExisting:
            log.info("Kept the watch workout already linked; ignored a later one for the same session")
        }
    }

    /// Works through the durable list of workouts waiting to be removed: a
    /// phone fallback the watch's measured workout replaced, the workout of a
    /// session deleted from history, or one that finished writing after its
    /// session was deleted. Runs at launch, after authorization, on every
    /// foreground and whenever an entry is added, since those are the moments
    /// Health may take a delete it refused before. A phone locked when the
    /// watch's ID arrived refuses the lookup until the next unlock, and a
    /// cold launch can be days away.
    ///
    /// An entry leaves the list only when `deleteWorkout` says the workout is
    /// gone, and that includes one its query can no longer find. Every entry
    /// is a workout this phone wrote, and Health shows an app its own samples
    /// whether or not it may read them, so an empty answer means the workout
    /// was already removed, not that read permission was withheld. A refused
    /// or failed delete keeps the entry for the next attempt.
    func retryPendingWorkoutCleanup() async {
        guard cleanupGate.begin() else { return }
        defer { cleanupGate.end() }

        repeat {
            cleanupGate.startPass()
            await HealthCleanupQueue.drain(
                load: pendingWorkouts,
                save: savePendingWorkouts,
                prepare: relinkSession,
                delete: { await self.deleteForCleanup(id: $0) })
        } while cleanupGate.wantsAnotherPass
    }

    /// One delete for the cleanup list, settled against the attempt cap. True
    /// when the entry should leave the list: the workout is gone, or the list
    /// has stopped trying and keeps it in the ledger for Settings to offer
    /// again. A locked phone is not a failure and costs no attempt.
    private func deleteForCleanup(id: UUID) async -> Bool {
        let outcome = await deleteOutcome(id: id)
        // The entry can be removed while Health answers. Then there is nothing
        // to give up on, and nothing to count against.
        guard let entry = pendingWorkouts().first(where: { $0.workoutID == id }) else {
            return outcome == .gone
        }
        var ledger = loadAttemptLedger()
        let leaves = ledger.record(outcome, workoutID: id, sessionID: entry.sessionID, at: .now)
        saveAttemptLedger(ledger)
        return leaves
    }

    /// Queues every workout the list gave up on for one more attempt each, and
    /// runs it. What Settings' Retry does; nothing else ever asks the user.
    func retryGivenUpCleanups() async {
        var ledger = loadAttemptLedger()
        let reopened = ledger.reopen()
        guard !reopened.isEmpty else { return }
        saveAttemptLedger(ledger)
        var queue = pendingWorkouts()
        for item in reopened {
            queue = HealthCleanupQueue.enqueue(
                PendingWorkoutCleanup(workoutID: item.workoutID, sessionID: item.sessionID,
                                      preferredWorkoutID: nil),
                into: queue)
        }
        savePendingWorkouts(queue)
        await retryPendingWorkoutCleanup()
    }

    private func loadAttemptLedger() -> CleanupAttemptLedger {
        guard let data = defaults.data(forKey: Self.cleanupAttemptsKey) else { return CleanupAttemptLedger() }
        return (try? JSONDecoder().decode(CleanupAttemptLedger.self, from: data)) ?? CleanupAttemptLedger()
    }

    private func saveAttemptLedger(_ ledger: CleanupAttemptLedger) {
        if let data = try? JSONEncoder().encode(ledger) { defaults.set(data, forKey: Self.cleanupAttemptsKey) }
        givenUpCleanupCount = ledger.givenUp.count
    }

    /// Points the entry's session at its successor before the old workout is
    /// removed. Only the sessions an entry names are read, and only the one
    /// row: an entry with no successor has nothing to link and asks the
    /// store nothing.
    ///
    /// False when the link could not be established or saved, so the delete
    /// waits. The link must reach disk first, or a crash would leave it
    /// pointing at a workout that is gone.
    private func relinkSession(for pending: PendingWorkoutCleanup) -> Bool {
        guard let preferred = pending.preferredWorkoutID else { return true }
        guard let container = cleanupContainer else { return false }
        let sessionID = pending.sessionID
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        let context = ModelContext(container)
        guard let matches = try? context.fetch(descriptor) else { return false }
        let stored = matches.first
        guard let session = stored,
              CleanupRelink.isNeeded(preferredWorkoutID: preferred, sessionFound: stored != nil,
                                     sessionLink: stored?.healthWorkoutID, workoutID: pending.workoutID)
        else { return true }
        session.healthWorkoutID = preferred
        return (try? context.save()) != nil
    }

    private func pendingWorkouts() -> [PendingWorkoutCleanup] {
        guard let data = defaults.data(forKey: Self.pendingWorkoutCleanupKey) else { return [] }
        return (try? JSONDecoder().decode([PendingWorkoutCleanup].self, from: data)) ?? []
    }

    private func savePendingWorkouts(_ pending: [PendingWorkoutCleanup]) {
        guard let data = try? JSONEncoder().encode(pending) else { return }
        defaults.set(data, forKey: Self.pendingWorkoutCleanupKey)
    }

    private func phoneWrittenWorkouts() -> [UUID] {
        (defaults.stringArray(forKey: Self.phoneWrittenWorkoutsKey) ?? []).compactMap(UUID.init(uuidString:))
    }

    private func notePhoneWritten(_ workoutID: UUID) {
        var ids = phoneWrittenWorkouts()
        ids.removeAll { $0 == workoutID }
        ids.append(workoutID)
        defaults.set(ids.suffix(Self.phoneWrittenWorkoutsLimit).map(\.uuidString),
                     forKey: Self.phoneWrittenWorkoutsKey)
    }

    private func enqueueCleanup(workoutID: UUID, sessionID: UUID, preferredWorkoutID: UUID?) {
        savePendingWorkouts(HealthCleanupQueue.enqueue(
            PendingWorkoutCleanup(workoutID: workoutID, sessionID: sessionID,
                                  preferredWorkoutID: preferredWorkoutID),
            into: pendingWorkouts()))
    }

    /// Queues the Health workout of a session the user has just deleted from
    /// history, and starts removing it. A one-shot delete fired here and then
    /// forgotten left the workout in Fitness whenever Health refused it, with
    /// nothing to try again: the linked workout is usually the watch's, and
    /// the phone may not see it, or may not be allowed to remove it. On the
    /// list it is retried on every foreground.
    ///
    /// Call after the delete is saved. An entry queued for a session whose
    /// delete then failed would remove the workout of a session still on
    /// screen.
    func discardWorkout(_ workoutID: UUID, ofDeletedSession sessionID: UUID) {
        enqueueCleanup(workoutID: workoutID, sessionID: sessionID, preferredWorkoutID: nil)
        Task { await retryPendingWorkoutCleanup() }
    }

    /// Queues a workout the watch reported for a session that no longer
    /// exists, and returns whether it did. Nothing else can remove it: no
    /// session holds its ID, so no erase or later delete would find it.
    ///
    /// The store is asked afresh, not the caller's copy of the session, which
    /// can look alive after a delete saved through another context. A restore
    /// may have put the same session back, and then the workout belongs to it
    /// and stays. A fetch that fails says nothing either way and queues
    /// nothing.
    @discardableResult
    func discardOrphanWorkout(_ workoutID: UUID, sessionID: UUID) -> Bool {
        guard let container = cleanupContainer else { return false }
        var descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.id == sessionID })
        descriptor.fetchLimit = 1
        guard let matches = try? ModelContext(container).fetch(descriptor),
              let orphan = HealthCleanupQueue.orphaned(workoutID: workoutID, sessionID: sessionID,
                                                       sessionExists: !matches.isEmpty)
        else { return false }
        enqueueCleanup(workoutID: orphan.workoutID, sessionID: orphan.sessionID,
                       preferredWorkoutID: orphan.preferredWorkoutID)
        Task { await retryPendingWorkoutCleanup() }
        return true
    }

    /// Removes a session's workout from Health, and returns whether it is
    /// gone. Only ever touches the sample GymTrack itself wrote — HealthKit
    /// refuses anything else anyway.
    ///
    /// A workout the query cannot find counts as gone. With write access,
    /// HealthKit always shows an app the samples it wrote, even when read
    /// access is withheld, so an empty answer means the workout was already
    /// deleted, in Health or by an earlier erase. Counting that as a failure
    /// made every later erase or restore blame Health access for workouts that
    /// no longer exist. The one blind spot is a workout the watch app wrote:
    /// Health may treat it as another source and hide it when read access is
    /// withheld. Refused (no write access, or Health denying the delete) and
    /// failed (a locked phone, a store error) stay false, so callers keep the
    /// workout on their list and say so.
    @discardableResult
    func deleteWorkout(id: UUID) async -> Bool {
        await deleteOutcome(id: id) == .gone
    }

    /// `deleteWorkout`, keeping apart a refusal from a phone that is only
    /// locked, which the cleanup list must not hold against the workout.
    private func deleteOutcome(id: UUID) async -> CleanupAttemptLedger.Outcome {
        guard isAvailable else { return .refused }
        guard canWriteWorkouts else {
            log.info("Health refused to remove a workout: write access is off")
            return .refused
        }
        let predicate = HKQuery.predicateForObject(with: id)
        do {
            let workouts = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
                }
                store.execute(query)
            }
            guard !workouts.isEmpty else {
                log.info("Workout was already gone from Health")
                return .gone
            }
            try await store.delete(workouts)
            return .gone
        } catch let error as HKError where error.code == .errorDatabaseInaccessible {
            log.info("Health is locked; the workout will be removed after the next unlock")
            return .deferred
        } catch let error as HKError where error.code == .errorAuthorizationDenied {
            log.error("Health refused to remove a workout: \(error.localizedDescription, privacy: .public)")
            return .refused
        } catch {
            log.error("Couldn't remove workout from Health: \(error.localizedDescription, privacy: .public)")
            return .refused
        }
    }

    /// Removes many workouts with one query and one delete, and returns the
    /// IDs that are still in Health, in the order given.
    ///
    /// An erase used to await a query and a delete per session, which held
    /// the sheet on an empty store for as long as the history was long. IDs
    /// the query cannot find count as gone, for the reason given on
    /// `deleteWorkout`. A found workout that a GymTrack source did not write
    /// is left alone and reported as remaining: HealthKit fails a whole batch
    /// that holds one sample it refuses, so it must not be in the array, and
    /// another app's workout is not ours to remove. The watch app writes under
    /// a source named after this app's, so both count as ours. If the batch
    /// itself is refused, nothing was removed and every found ID is returned.
    func deleteWorkouts(ids: [UUID]) async -> [UUID] {
        let wanted = WorkoutDeletionPlan.unique(ids)
        guard !wanted.isEmpty else { return [] }
        guard isAvailable else { return wanted }
        guard canWriteWorkouts else {
            log.info("Health refused to remove workouts: write access is off")
            return wanted
        }
        let predicate = HKQuery.predicateForObjects(with: Set(wanted))
        do {
            let found = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: .workoutType(), predicate: predicate,
                                          limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
                }
                store.execute(query)
            }
            let stamped = found.map { WorkoutDeletionPlan.Found(id: $0.uuid, ours: isGymTrackFamilySource($0)) }
            let deletable = Set(WorkoutDeletionPlan.toDelete(found: stamped))
            let ours = found.filter { deletable.contains($0.uuid) }
            var deleteFailed = false
            if !ours.isEmpty {
                do {
                    try await store.delete(ours)
                } catch {
                    log.error("Couldn't remove workouts from Health: \(error.localizedDescription, privacy: .public)")
                    deleteFailed = true
                }
            }
            return WorkoutDeletionPlan.remaining(wanted: wanted, found: stamped, deleteFailed: deleteFailed)
        } catch {
            log.error("Couldn't look up workouts in Health: \(error.localizedDescription, privacy: .public)")
            return wanted
        }
    }

    /// This app or its watch app, whose bundle id extends the phone's. Another
    /// app's bundle id never does.
    private func isGymTrackFamilySource(_ sample: HKSample) -> Bool {
        let mine = HKSource.default().bundleIdentifier
        let theirs = sample.sourceRevision.source.bundleIdentifier
        return theirs == mine || theirs.hasPrefix(mine + ".")
    }

    // MARK: - Reading a session's vitals

    /// Heart rate and active energy recorded during a session's window, kept
    /// only where the readings can stand as a measurement of the session.
    ///
    /// Every heart-rate reading in the window is fetched and weighed by
    /// `VitalsEvidence.judge`, rather than averaged by Health's statistics
    /// query, because that query answers just as confidently for two background
    /// readings as for a workout's worth, and a caller can't tell the difference
    /// afterwards. Energy is the exception, and only for its total: two watch
    /// apps can write the same minutes, and Health's cumulative sum counts each
    /// once where adding the slices counted both. See `wristEnergy`. What comes
    /// back is empty for whatever was too thin.
    func vitals(from start: Date, to end: Date) async -> VitalsEvidence {
        guard isAvailable, AppSettings.shared.healthReadVitals, end > start else { return VitalsEvidence() }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        let beats = HKUnit.count().unitDivided(by: .minute())

        async let heart = vitalsSamples(identifier: .heartRate, unit: beats, predicate: predicate)
        async let energy = wristEnergy(predicate: predicate)
        return VitalsEvidence.judge(heartRate: await heart, energy: await energy,
                                    window: DateInterval(start: start, end: end))
    }

    /// Fills in whatever a session is missing — the session's own numbers, and
    /// then a heart rate for each of its sets. Called right after a workout
    /// ends, and again whenever its summary or its page in the history is
    /// opened, because HealthKit can take a minute to receive the watch's
    /// samples, and a phone locked in a bag can't read them at all until it is
    /// next unlocked.
    ///
    /// The session's own numbers are written only where there was nothing.
    /// A set's heart rate is too, except that one this phone read off a trace
    /// still arriving can be read again once more of it has; see
    /// `SetHeartRateAttribution.updates`.
    func backfillVitals(for session: WorkoutSession) async {
        guard AppSettings.shared.healthReadVitals, !session.isGoneFromStore,
              let end = session.endedAt else { return }
        let sessionID = session.id
        // Heart rate is taken or left as a pair, so its source describes both
        // numbers: a peak from Health beside an average the wrist recorded
        // would be labelled with one of them and wrong about the other.
        let needsHeartRate = session.averageHeartRate == nil && session.maxHeartRate == nil
        let needsEnergy = session.activeEnergyKcal == nil
        if needsHeartRate || needsEnergy {
            let vitals = await vitals(from: session.startedAt, to: end)
            guard !isGone(session, id: sessionID) else { return }
            // Nothing from a query that found too little to vouch for: a few
            // background readings or a phone's step-counted energy would file
            // as a workout's, and read as one.
            if needsHeartRate, let average = vitals.averageHeartRate, let peak = vitals.maxHeartRate {
                session.averageHeartRate = average
                session.maxHeartRate = peak
                session.heartRateSourceRaw = VitalsSource.healthSamples.rawValue
                session.heartRateReadings = vitals.heartRateReadings
            }
            if needsEnergy, let energy = vitals.activeEnergyKcal {
                session.activeEnergyKcal = energy
                session.energySourceRaw = VitalsSource.healthSamples.rawValue
            }
        }
        // Not only when the session-wide read found something. That read judges
        // the whole window and comes back empty for reasons the individual
        // samples don't share — a watch that recorded a handful of beats and no
        // energy at all is too thin to be a session's heart rate, and those
        // beats are exactly what a set wants.
        await attributeHeartRate(within: session, id: sessionID)
    }

    /// Another pass over the sessions finished in the last day and a half that
    /// have a workout in Health and a set still without a heart rate.
    ///
    /// For the next time the app comes to the foreground: a workout finished
    /// on the wrist with the phone locked is handled headlessly, every read
    /// then fails, and no summary is ever shown to try again. Kept to recent
    /// sessions with a workout in Health because those are the ones whose
    /// samples can still be on their way; an older gap is a set the watch
    /// wasn't there for, and asking again on every unlock would find nothing.
    func backfillRecentSessions(in context: ModelContext, now: Date = .now) async {
        guard AppSettings.shared.healthReadVitals else { return }
        let finishedSince = now.addingTimeInterval(-36 * 60 * 60)
        // A session runs twelve hours at the most before it is closed as
        // stale, so anything finished since then started after this.
        let startedSince = finishedSince.addingTimeInterval(-12 * 60 * 60)
        let descriptor = FetchDescriptor<WorkoutSession>(predicate: #Predicate { $0.startedAt >= startedSince })
        let due = ((try? context.fetch(descriptor)) ?? []).filter { session in
            guard let endedAt = session.endedAt, endedAt >= finishedSince,
                  session.healthWorkoutID != nil else { return false }
            return session.completedSets.contains { $0.completedAt != nil && !$0.hasHeartRate }
        }
        guard !due.isEmpty else { return }
        for session in due {
            await backfillVitals(for: session)
        }
        try? context.save()
    }

    // MARK: - Heart rate, set by set

    /// Gives each of a session's sets the heart rate recorded during it.
    ///
    /// One query for the whole session, partitioned in memory, rather than a
    /// query per set: a thirty-set session would otherwise mean thirty round
    /// trips to HealthKit for samples that all arrive in the same fetch, and
    /// the windows have to be worked out relative to one another anyway — a set
    /// without an announced start is bounded by the set logged before it.
    ///
    /// Every completed set is given a window, including the ones that already
    /// carry a heart rate, because those are what bound the ones that don't.
    /// Only the sets a pass may still write are written to, and, among those,
    /// the ones nobody announced are first looked for in the trace itself, so
    /// the heart rate is read over the set the watch saw rather than an
    /// estimate.
    private func attributeHeartRate(within session: WorkoutSession, id sessionID: UUID) async {
        let completed = session.completedSets.filter { $0.completedAt != nil }
        let ledger = SetHeartRateLedger(defaults: defaults)
        let remembered = ledger.samples()
        let stored = completed.map { set in
            StoredSetHeartRate(
                timing: SetTiming(
                    id: set.id,
                    startedAt: set.startedAt,
                    completedAt: set.completedAt ?? session.startedAt,
                    reps: set.reps,
                    // A duration-tracked set states its own length; a set of
                    // reps has to be estimated. See `SetTiming.assumedDuration`.
                    heldSeconds: set.tracking == .duration ? set.seconds : 0,
                    detected: set.detectedWindow
                ),
                hasReading: set.hasHeartRate,
                readFrom: set.hasHeartRate ? remembered[set.id] : nil,
                // Read only where nobody said: an announced start is a
                // measurement, and nothing read off a trace improves on one.
                // Not for a continuation either — a "set" found in a drop's
                // back-off row would be the tail of the row above.
                mayDetect: set.startedAt == nil && !set.isContinuation
            )
        }
        guard stored.contains(where: \.isOpen) else { return }

        let sessionStart = session.startedAt
        let samples = await heartRateSamples(from: sessionStart, to: session.endedAt ?? .now)
        guard !samples.isEmpty, !isGone(session, id: sessionID) else { return }

        let updates = SetHeartRateAttribution.updates(samples: samples, sets: stored, sessionStart: sessionStart)
        guard !updates.isEmpty else { return }

        // Checked again set by set, because the fetch suspended. A late undo
        // from the wrist can remove a row from a finished session, a set
        // logged again has another window, and a second pass running beside
        // this one may already have written more than this one read.
        let loggedAt = Dictionary(stored.map { ($0.timing.id, $0.timing.completedAt) },
                                  uniquingKeysWith: { first, _ in first })
        let sets = Dictionary(completed.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let current = ledger.samples()
        var written: [UUID: Int] = [:]
        for update in updates {
            guard let set = sets[update.id], !set.isGoneFromStore, set.isCompleted,
                  set.completedAt == loggedAt[update.id],
                  SetHeartRateAttribution.mayReplace(hasReading: set.hasHeartRate, readFrom: current[update.id],
                                                     samples: update.samples)
            else { continue }
            if let window = update.detected { set.recordDetectedWindow(window) }
            set.apply(update.heartRate)
            written[update.id] = update.samples
        }
        ledger.record(written)
    }

    /// Every individual heart-rate reading overlapping a window.
    ///
    /// Deliberately without `.strictStartDate`, which the session-level
    /// statistics use: a reading that began a second before the session and
    /// ended inside it is a reading from inside the session, and whether it
    /// belongs to any particular set is a question for the windowing, not for
    /// the fetch.
    private func heartRateSamples(from start: Date, to end: Date) async -> [HeartRateSample] {
        guard isAvailable, end > start,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate)
        else { return [] }

        let beats = HKUnit.count().unitDivided(by: .minute())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: [sort]) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
        return samples.map {
            HeartRateSample(start: $0.startDate, end: $0.endDate, bpm: $0.quantity.doubleValue(for: beats))
        }
    }

    /// Every sample of one quantity that started inside a window, with whether
    /// a wrist wrote it.
    ///
    /// The device is read off the source revision's product type
    /// (`Watch7,1`, `iPhone16,2`), the one place Health says what hardware a
    /// sample came from. A sample that doesn't say is reported as not the
    /// wrist, which costs a measurement at worst and never invents one.
    private func vitalsSamples(identifier: HKQuantityTypeIdentifier, unit: HKUnit,
                               predicate: NSPredicate) async -> [VitalsSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { return [] }
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
        return samples.map {
            VitalsSample(start: $0.startDate, end: $0.endDate, value: $0.quantity.doubleValue(for: unit),
                         isFromWrist: $0.sourceRevision.productType?.hasPrefix("Watch") == true)
        }
    }

    /// The active energy a wrist recorded in the window, counted once, as the
    /// one slice `VitalsEvidence.judge` weighs; empty when there is none to
    /// vouch for.
    ///
    /// The slices are read only to learn who wrote them and over what span.
    /// The total comes from a cumulative-sum statistics query restricted to the
    /// sources that wrote nothing but wrist slices, because Health de-duplicates
    /// overlapping sources there by the user's priority order, and adding the
    /// slices up here counted the same minutes twice whenever two watch apps
    /// had written them. Restricting the sources keeps the phone's step-counted
    /// estimate out of that sum, as it was out of the old one; see
    /// `WristEnergyRead`. No reading, or a sum of zero, is no slice at all.
    private func wristEnergy(predicate: NSPredicate) async -> [VitalsSample] {
        guard let type = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else { return [] }
        let unit = HKUnit.kilocalorie()
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate,
                                      limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
        let slices = samples.map {
            EnergySlice(start: $0.startDate, end: $0.endDate, kilocalories: $0.quantity.doubleValue(for: unit),
                        sourceID: $0.sourceRevision.source.bundleIdentifier,
                        isFromWrist: $0.sourceRevision.productType?.hasPrefix("Watch") == true)
        }
        let trusted = WristEnergyRead.trustedSources(in: slices)
        guard !trusted.isEmpty else { return [] }
        let sources = Set(samples.map(\.sourceRevision.source).filter { trusted.contains($0.bundleIdentifier) })
        let restricted = NSCompoundPredicate(andPredicateWithSubpredicates: [
            predicate, HKQuery.predicateForObjects(from: sources)])
        let sum: Double? = await withCheckedContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: restricted,
                                          options: .cumulativeSum) { _, statistics, _ in
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
        guard let energy = WristEnergyRead.result(slices: slices, trusted: trusted, cumulativeSum: sum) else { return [] }
        return [VitalsSample(start: energy.start, end: energy.end, value: energy.kilocalories, isFromWrist: true)]
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

    /// Writes a weigh-in to Health, and returns the UUID of the sample it
    /// writes so the entry can keep it, or nil when Health gets nothing.
    ///
    /// A sample has its UUID from the moment it is built, so the ID comes back
    /// before the save lands. A correction made seconds later still knows
    /// which sample to remove, and `deleteBodyMass` waits for the save first.
    /// If the save fails, the entry holds an ID Health never had, and removing
    /// it later simply finds nothing.
    @discardableResult
    func saveBodyMass(kg: Double, date: Date = .now) -> UUID? {
        guard AppSettings.shared.healthBodyWeight, canWriteBodyMass,
              let type = HKQuantityType.quantityType(forIdentifier: .bodyMass), kg > 0
        else { return nil }
        let sample = HKQuantitySample(
            type: type,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
            start: date,
            end: date,
            metadata: [HKMetadataKeyWasUserEntered: true]
        )
        let id = sample.uuid
        bodyMassSaves[id] = Task {
            do { try await store.save(sample) } catch {
                log.error("Couldn't save body weight to Health: \(error.localizedDescription, privacy: .public)")
            }
            bodyMassSaves[id] = nil
        }
        return id
    }

    /// Pulls weigh-ins from Health into the app's own history, skipping any day
    /// already recorded so repeated imports don't pile up.
    @discardableResult
    func importBodyMass(into context: ModelContext, since: Date? = nil) async -> Int {
        guard AppSettings.shared.healthBodyWeight,
              isAvailable,
              let type = HKQuantityType.quantityType(forIdentifier: .bodyMass),
              !bodyMassImportInFlight
        else { return 0 }
        bodyMassImportInFlight = true
        defer { bodyMassImportInFlight = false }

        let start = since ?? Calendar.current.date(byAdding: .year, value: -2, to: .now)
        let predicate = start.map { HKQuery.predicateForSamples(withStart: $0, end: nil, options: []) }
        let samples: [HKQuantitySample] = await withCheckedContinuation { continuation in
            // The newest reading wins when a scale recorded more than one on
            // the same day. The importer keeps only the first sample per day.
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
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
            if isWrittenByGymTrack(sample) {
                // A weigh-in typed here whose entry is gone: an erase, or a
                // delete whose Health half failed. It comes back as what it
                // was, typed and holding its sample, so deleting it again
                // takes it out of Health instead of it returning every import.
                metric.healthSampleID = sample.uuid
            } else {
                metric.source = BodyMetric.Source.health.rawValue
            }
            context.insert(metric)
            added += 1
        }
        if added > 0 { try? context.save() }
        return added
    }

    /// Health saves still in flight, by the UUID of the sample each writes. A
    /// delete that ran first would find nothing, and the save landing after it
    /// would leave the wrong weight in Health anyway.
    @ObservationIgnored private var bodyMassSaves: [UUID: Task<Void, Never>] = [:]

    /// Takes a weigh-in GymTrack wrote back out of Health, and returns whether
    /// it is gone. The sample's source is checked in Health rather than
    /// trusted from the entry, so a reading any scale or other app wrote is
    /// never touched.
    ///
    /// Not gated on the body-weight switch: this is GymTrack's own wrong
    /// number, and turning sync off afterwards should not strand it in Health.
    /// A sample that cannot be found counts as gone, for the reason given on
    /// `deleteWorkout`.
    @discardableResult
    func deleteBodyMass(id: UUID) async -> Bool {
        if let save = bodyMassSaves[id] { await save.value }
        guard isAvailable, let type = HKQuantityType.quantityType(forIdentifier: .bodyMass) else { return false }
        guard canWriteBodyMass else {
            log.info("Health refused to remove a weigh-in: write access is off")
            return false
        }
        let predicate = HKQuery.predicateForObject(with: id)
        do {
            let samples = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKSample], Error>) in
                let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
                    if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: samples ?? []) }
                }
                store.execute(query)
            }
            guard let sample = samples.first else { return true }
            guard isWrittenByGymTrack(sample) else {
                log.error("Refused to remove a weigh-in another source wrote to Health")
                return false
            }
            try await store.delete(sample)
            return true
        } catch {
            log.error("Couldn't remove body weight from Health: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    /// Whether this app wrote the sample. Health keeps every source's samples
    /// apart, and only these are ever GymTrack's to take back.
    private func isWrittenByGymTrack(_ sample: HKSample) -> Bool {
        sample.sourceRevision.source.bundleIdentifier == HKSource.default().bundleIdentifier
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
