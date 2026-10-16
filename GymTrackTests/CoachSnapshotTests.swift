import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// The coach snapshot must follow the store: what the export carries, written
/// again after any save that changes it, and never rewritten for the sets of a
/// workout still in progress.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct CoachSnapshotTests {

    /// A started writer over a temporary folder, after its launch write.
    @MainActor private struct Rig {
        let container: ModelContainer
        let store: CoachStore
        let writer: CoachSnapshot
        var context: ModelContext { container.mainContext }

        static func started(_ container: ModelContainer, store: CoachStore? = nil) async -> Rig {
            let store = store ?? CoachFixture.temporaryStore()
            let writer = CoachSnapshot()
            writer.quietPeriod = .zero
            writer.start(container: container, store: store)
            await writer.settled()
            return Rig(container: container, store: store, writer: writer)
        }

        func finish() {
            writer.stop()
            CoachFixture.discard(store)
        }

        func archive() throws -> BackupService.Archive {
            try BackupService.decodedArchive(from: Data(contentsOf: store.snapshotURL))
        }
    }

    private func finishedSession(_ title: String, in context: ModelContext, reps: Int = 8) -> (WorkoutSession, SetLog) {
        let session = WorkoutSession(title: title, startedAt: TestClock.reference)
        session.endedAt = session.startedAt.addingTimeInterval(3_600)
        context.insert(session)
        let set = SetLog(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press",
                         exerciseOrder: 0, setIndex: 0, weightKg: 60, reps: reps)
        set.isCompleted = true
        set.completedAt = session.startedAt.addingTimeInterval(600)
        PersistenceFixtures.add(set, to: session, in: context)
        return (session, set)
    }

    // MARK: - Insert, update, delete

    @Test func aSavedTapeMeasurementReachesTheSnapshot() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = await Rig.started(try TestStore.container())
        defer { rig.finish() }
        let check = BodyMeasurement()
        check.armCm = 37
        rig.context.insert(check)
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().bodyMeasurements?.first?.armCm == 37, "The coach must receive the just-saved check-in")
    }

    /// A photo added to or taken off a check-in changes what the coach pulls,
    /// so the snapshot follows it.
    @Test func aProgressPhotoReachesTheSnapshotAndItsDeleteLeavesIt() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = await Rig.started(try TestStore.container())
        defer { rig.finish() }
        let check = BodyMeasurement()
        check.waistCm = 82
        rig.context.insert(check)
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().bodyMeasurements?.first?.photos == nil)

        let photo = ProgressPhoto(pose: .side, takenAt: TestClock.reference)
        rig.context.insert(photo)
        photo.checkIn = check
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().bodyMeasurements?.first?.photos?.map(\.id) == [photo.id])

        rig.context.delete(photo)
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().bodyMeasurements?.first?.photos == nil, "a deleted photo must leave the coach's copy")
    }

    @Test func aDeletedWorkoutLeavesTheSnapshot() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let container = try TestStore.container()
        let (session, _) = finishedSession("Deleted workout", in: container.mainContext)
        try container.mainContext.save()
        let rig = await Rig.started(container)
        defer { rig.finish() }
        #expect(try rig.archive().sessions.count == 1)
        rig.context.delete(session)
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().sessions.isEmpty, "A deleted session must not continue to reach the coach")
    }

    @Test func correctionsToAFinishedWorkoutAndItsNotesReachTheSnapshot() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let container = try TestStore.container()
        let (session, set) = finishedSession("Push", in: container.mainContext)
        try container.mainContext.save()
        let rig = await Rig.started(container)
        defer { rig.finish() }

        session.notes = "Shoulder felt tight"
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().sessions.first?.notes == "Shoulder felt tight", "A session note")

        set.reps = 10
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().sessions.first?.sets.first?.reps == 10, "A corrected set")

        let note = ExerciseNote(catalogID: set.catalogID, exerciseName: set.exerciseName)
        note.text = "Pause the first rep"
        note.session = session
        rig.context.insert(note)
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().sessions.first?.exerciseNotes?.first?.text == "Pause the first rep", "A new exercise note")

        rig.context.delete(set)
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().sessions.first?.sets.isEmpty == true, "A set deleted from a finished session")
    }

    @Test func weighInsAndOtherExportedRecordsAskForANewSnapshot() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = await Rig.started(try TestStore.container())
        defer { rig.finish() }
        let launched = rig.writer.lastWrittenAt

        let weighIn = BodyMetric(weightKg: 81)
        rig.context.insert(weighIn)
        try rig.context.save()
        await rig.writer.settled()
        #expect(try rig.archive().bodyMetrics?.first?.weightKg == 81)

        let afterWeighIn = rig.writer.lastWrittenAt
        #expect(afterWeighIn != launched)
        rig.context.insert(HiddenExerciseRecord(catalogID: "barbell-bench-press"))
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt != afterWeighIn, "A hidden exercise is exported")

        let afterHidden = rig.writer.lastWrittenAt
        rig.context.delete(weighIn)
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt != afterHidden, "A deleted weigh-in")
        #expect(try rig.archive().bodyMetrics?.isEmpty ?? true)
    }

    // MARK: - A workout in progress

    @Test func savesThatOnlyTouchTheWorkoutInProgressDoNotWrite() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = await Rig.started(try TestStore.container())
        defer { rig.finish() }
        let launched = try #require(rig.writer.lastWrittenAt)

        let session = WorkoutSession(title: "Live", startedAt: TestClock.reference)
        rig.context.insert(session)
        let set = SetLog(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press",
                         exerciseOrder: 0, setIndex: 0, weightKg: 60, reps: 8)
        PersistenceFixtures.add(set, to: session, in: rig.context)
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt == launched, "Starting a workout")

        set.isCompleted = true
        set.completedAt = TestClock.reference.addingTimeInterval(60)
        set.reps = 9
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt == launched, "Logging a set")

        let note = ExerciseNote(catalogID: set.catalogID, exerciseName: set.exerciseName)
        note.session = session
        rig.context.insert(note)
        try rig.context.save()
        rig.context.delete(note)
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt == launched, "An exercise note written and cleared mid-workout")

        rig.context.delete(set)
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt == launched, "A set removed mid-workout")

        session.endedAt = TestClock.reference.addingTimeInterval(1_800)
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt != launched, "Finishing the workout writes it")
        #expect(try rig.archive().sessions.count == 1)
    }

    @Test func aMachineSetupSavedDuringAWorkoutWritesNothingUntilItFinishes() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = await Rig.started(try TestStore.container())
        defer { rig.finish() }
        let session = WorkoutSession(title: "Live", startedAt: TestClock.reference)
        rig.context.insert(session)
        try rig.context.save()
        await rig.writer.settled()
        let launched = try #require(rig.writer.lastWrittenAt)

        let setup = MachineSetupRecord(catalogID: "machine-chest-press", machineID: "panatta-chest-press", at: TestClock.reference)
        rig.context.insert(setup)
        try rig.context.save()
        setup.settingsRaw = "{\"seat\":4}"
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt == launched, "Choosing a machine and nudging a seat mid-workout")

        session.endedAt = TestClock.reference.addingTimeInterval(1_800)
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt != launched, "Finishing writes it")
        #expect(try rig.archive().machineSetups?.count == 1)
    }

    @Test func aMachineSetupSavedBetweenWorkoutsAsksForANewSnapshot() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let rig = await Rig.started(try TestStore.container())
        defer { rig.finish() }
        let launched = try #require(rig.writer.lastWrittenAt)

        rig.context.insert(MachineSetupRecord(catalogID: "machine-chest-press", machineID: "panatta-chest-press", at: TestClock.reference))
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt != launched)
    }

    @Test func aLaunchWithAnOpenWorkoutWritesWhenItFinishes() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let container = try TestStore.container()
        let session = WorkoutSession(title: "Live", startedAt: TestClock.reference)
        container.mainContext.insert(session)
        try container.mainContext.save()
        let rig = await Rig.started(container)
        defer { rig.finish() }
        #expect(rig.writer.lastWrittenAt == nil, "Relaunching mid-workout starts no export")
        #expect(!rig.store.hasSnapshot)

        session.endedAt = TestClock.reference.addingTimeInterval(1_800)
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt != nil)
        #expect(try rig.archive().sessions.count == 1)
    }

    @Test func lateHealthVitalsOnAFinishedSessionAskForANewSnapshot() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let container = try TestStore.container()
        let (session, _) = finishedSession("Pull", in: container.mainContext)
        try container.mainContext.save()
        let rig = await Rig.started(container)
        defer { rig.finish() }
        let launched = try #require(rig.writer.lastWrittenAt)

        session.averageHeartRate = 131
        try rig.context.save()
        await rig.writer.settled()
        #expect(rig.writer.lastWrittenAt != launched, "A vital arriving after the session ended is exported")
    }

    // MARK: - Launch

    @Test func relaunchRefreshesAFileThatWentStale() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let container = try TestStore.container()
        let first = await Rig.started(container)
        defer { first.finish() }
        first.writer.stop()
        #expect(try first.archive().sessions.isEmpty)

        // The app was killed before the debounce wrote this one.
        _ = finishedSession("Written while no writer was watching", in: first.context)
        try first.context.save()
        #expect(try first.archive().sessions.isEmpty)

        let second = await Rig.started(container, store: first.store)
        defer { second.writer.stop() }
        #expect(try second.archive().sessions.count == 1, "A launch over an existing file refreshes it")
    }
}
