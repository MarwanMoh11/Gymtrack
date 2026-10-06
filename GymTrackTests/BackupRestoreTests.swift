import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// `BackupService` export and restore against the real schema: the file is the
/// same bytes for the same store, restoring it and exporting again gives that
/// file back, and a restore that is refused leaves the phone as it was.
///
/// Complements `Tests/BackupRoundTripTests.swift`, `Tests/PoundBackupTests.swift`
/// and `Tests/BackupExportFidelityTests.swift`, which run against a stubbed
/// store. Decoding of older and malformed files is in `BackupDecodingTests`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct BackupRestoreTests {

    private let stamp = PersistenceFixtures.stamp()

    // MARK: - Export

    @Test func twoExportsOfOneStoreWithOneStampAreTheSameBytes() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try populate(context)

        let first = try BackupService.exportData(context: context, stamp: stamp)
        let second = try BackupService.exportData(context: context, stamp: stamp)

        #expect(first == second)
    }

    @Test func exportsMadeAtDifferentMomentsDifferOnlyInExportedAt() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try populate(context)

        let earlier = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(at: TestClock.reference))
        let later = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(at: TestClock.reference.addingTimeInterval(86_400)))

        #expect(earlier != later)
        var first = try PersistenceFixtures.object(earlier)
        var second = try PersistenceFixtures.object(later)
        #expect(first["exportedAt"] as? String == "2026-03-11T12:00:00Z")
        #expect(second["exportedAt"] as? String == "2026-03-12T12:00:00Z")
        first["exportedAt"] = nil
        second["exportedAt"] = nil
        #expect(NSDictionary(dictionary: first).isEqual(to: second))
    }

    @Test func exportCarriesVersionTwoAndTheStampsZoneAndBuild() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()

        let stamped = try PersistenceFixtures.object(
            BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(version: "1.4.2", build: "57")))
        #expect(stamped["version"] as? Int == 2)
        #expect(stamped["timeZone"] as? String == "Africa/Cairo")
        #expect(stamped["appVersion"] as? String == "1.4.2")
        #expect(stamped["appBuild"] as? String == "57")

        // A bundle with neither writes no key, rather than an empty string.
        let bare = try PersistenceFixtures.object(
            BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(version: nil, build: nil)))
        #expect(!bare.keys.contains("appVersion"))
        #expect(!bare.keys.contains("appBuild"))
        #expect(bare["timeZone"] as? String == "Africa/Cairo")
    }

    @Test func fileOrderFollowsStartDateCreationDateAndOrderNotInsertOrder() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-02T18:00:00")
        // Everything inserted newest and last-numbered first.
        let lateSession = PersistenceFixtures.session("Late", startedAt: t.addingTimeInterval(2 * 86_400),
                                                      endedAt: t.addingTimeInterval(2 * 86_400 + 3600), in: context)
        let earlySession = PersistenceFixtures.session("Early", startedAt: t, endedAt: t.addingTimeInterval(3600), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 1, completedAt: t), to: earlySession, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(PersistenceFixtures.squat, order: 1, setIndex: 0, completedAt: t), to: earlySession, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: t), to: earlySession, in: context)
        _ = lateSession
        let newPlan = PersistenceFixtures.plan("Newer", createdAt: t.addingTimeInterval(60), active: false, in: context)
        let oldPlan = PersistenceFixtures.plan("Older", createdAt: t, active: true, in: context)
        _ = PersistenceFixtures.day("Second", order: 1, exercises: [], in: oldPlan, context: context)
        _ = PersistenceFixtures.day("First", order: 0, exercises: [], in: oldPlan, context: context)
        _ = newPlan

        let root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: stamp))

        let sessions = try PersistenceFixtures.sessions(in: root)
        #expect(sessions.map { $0["title"] as? String } == ["Early", "Late"])
        let sets = try PersistenceFixtures.sets(in: root, sessionIndex: 0)
        #expect(sets.map { "\($0["exerciseOrder"] as? Int ?? -1).\($0["setIndex"] as? Int ?? -1)" } == ["0.0", "0.1", "1.0"])
        let plans = try #require(root["plans"] as? [[String: Any]])
        #expect(plans.map { $0["name"] as? String } == ["Older", "Newer"])
        let days = try #require(plans[0]["days"] as? [[String: Any]])
        #expect(days.map { $0["name"] as? String } == ["First", "Second"])
    }

    @Test func aWorkoutStillInProgressIsLeftOutOfTheFile() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        PersistenceFixtures.session("Done", startedAt: t, endedAt: t.addingTimeInterval(3600), in: context)
        let open = PersistenceFixtures.session("Running", startedAt: t.addingTimeInterval(7200), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: t.addingTimeInterval(7300)), to: open, in: context)

        let root = try PersistenceFixtures.object(BackupService.exportData(context: context, stamp: stamp))

        #expect(try PersistenceFixtures.sessions(in: root).map { $0["title"] as? String } == ["Done"])
    }

    @Test func exportingToAFileNamesItByTheLifterOwnDayAndHoldsTheSameBytes() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        // 23:30 UTC on the 10th is 01:30 on the 11th in Cairo.
        let late = PersistenceFixtures.stamp(at: TestClock.at("2026-03-10T23:30:00"))

        let url = try BackupService.export(context: context, stamp: late)
        defer { try? FileManager.default.removeItem(at: url) }

        #expect(url.lastPathComponent == "GymTrack-2026-03-11.json")
        #expect(try Data(contentsOf: url) == BackupService.exportData(context: context, stamp: late))
    }

    // MARK: - Round trips

    @Test func restoringAnExportAndExportingAgainGivesTheSameFileBack() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let source = try TestStore.context()
        let ids = try populate(source)
        let original = try BackupService.exportData(context: source, stamp: stamp)

        // A different phone: its settings differ until the file says otherwise.
        AppSettings.shared.userName = "Someone else"
        AppSettings.shared.defaultRestSeconds = 45
        let target = try TestStore.context()
        try BackupService.restore(data: original, context: target)

        #expect(AppSettings.shared.userName == "Test Lifter")
        #expect(AppSettings.shared.defaultRestSeconds == 90)
        #expect(try target.fetchCount(FetchDescriptor<Plan>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<PlanDay>()) == 3)
        #expect(try target.fetchCount(FetchDescriptor<PlanItem>()) == 3)
        #expect(try target.fetchCount(FetchDescriptor<WorkoutSession>()) == 2)
        #expect(try target.fetchCount(FetchDescriptor<SetLog>()) == 5)
        #expect(try target.fetchCount(FetchDescriptor<ExerciseNote>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<BodyMetric>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<BodyMeasurement>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<ExerciseLoadPreference>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<HiddenExerciseRecord>()) == 1)
        #expect(try target.fetchCount(FetchDescriptor<CustomExerciseRecord>()) == 1)

        let sessions = try target.fetch(FetchDescriptor<WorkoutSession>())
        let push = try #require(sessions.first { $0.id == ids.pushSession })
        #expect(push.title == "Push")
        #expect(push.notes == "Felt strong")
        #expect(push.noteTags == [.feltStrong])
        #expect(push.averageHeartRate == 118 && push.maxHeartRate == 171 && push.activeEnergyKcal == 240)
        #expect(push.heartRateSource == .watchWorkout && push.heartRateReadings == 600)
        #expect(push.healthWorkoutID == ids.healthWorkout)
        #expect(push.wasWatchDriven)
        #expect(push.planDayID == ids.pushDay)
        #expect(push.plannedSlots?.map(\.catalogID) == [PersistenceFixtures.bench.id, PersistenceFixtures.plank.id])
        #expect(push.exerciseNotes.first?.text == "Left shoulder pinched")
        #expect(push.exerciseNotes.first?.tags == [.pain])
        let drop = try #require(push.sets.first { $0.id == ids.dropSet })
        #expect(drop.isContinuation && drop.continuation == .drop)
        #expect(drop.weightKg == 80 && drop.reps == 6)
        let hard = try #require(push.sets.first { $0.id == ids.hardSet })
        #expect(hard.rpe == 9 && hard.averageHeartRate == 150 && hard.heartRateWindow == .measured)
        #expect(hard.loadNudgeOutcome == .taken && hard.loadNudgeToKg == 102.5)
        #expect(hard.detectedWindow != nil)
        let timed = try #require(push.sets.first { $0.catalogID == PersistenceFixtures.plank.id })
        #expect(timed.seconds == 60 && timed.tracking == .duration)

        let afterwards = try #require(sessions.first { $0.id == ids.afterwardsSession })
        #expect(afterwards.isLoggedAfterwards && !afterwards.isActive)
        #expect(afterwards.sets.first?.completedAt == nil && afterwards.sets.first?.isCompleted == true)

        let day = try #require(target.fetch(FetchDescriptor<PlanDay>()).first { $0.id == ids.pushDay })
        #expect(day.weekday == 2 && day.notes == "Bar path straight")
        let bench = try #require(day.orderedItems.first)
        #expect(bench.targetSets == 4 && bench.targetRepsLow == 5 && bench.targetRepsHigh == 8)
        #expect(bench.targetWeightKg == 80 && bench.restSeconds == 120 && bench.notes == "Pause the first rep")

        // The file is a function of the data, so the restored store writes it again.
        #expect(try BackupService.exportData(context: target, stamp: stamp) == original)
    }

    @Test func aPoundsLifterStoresKilogramsAndGetsPoundsBack() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        AppSettings.shared.weightUnit = .lb
        let source = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        let session = PersistenceFixtures.session(startedAt: t, endedAt: t.addingTimeInterval(3600), in: source)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, kg: 102.5, completedAt: t), to: session, in: source)
        source.insert(BodyMetric(date: t, weightKg: 82.5))

        let data = try BackupService.exportData(context: source, stamp: stamp)

        let root = try PersistenceFixtures.object(data)
        #expect((root["settings"] as? [String: Any])?["weightUnit"] as? String == "lb")
        // Pounds are display only: the file holds the kilograms that were stored.
        #expect(try PersistenceFixtures.sets(in: root, sessionIndex: 0).first?["weightKg"] as? Double == 102.5)
        #expect((root["bodyMetrics"] as? [[String: Any]])?.first?["weightKg"] as? Double == 82.5)

        AppSettings.shared.weightUnit = .kg
        let target = try TestStore.context()
        try BackupService.restore(data: data, context: target)

        #expect(AppSettings.shared.weightUnit == .lb)
        #expect(try target.fetch(FetchDescriptor<SetLog>()).first?.weightKg == 102.5)
        #expect(try target.fetch(FetchDescriptor<BodyMetric>()).first?.weightKg == 82.5)
    }

    @Test func aSessionKeepsItsInstantWhateverZoneTheFileWasWrittenIn() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let instant = TestClock.at("2026-03-10T22:30:00")
        let plan = PersistenceFixtures.plan("Week", createdAt: instant, active: true, in: context)
        PersistenceFixtures.day("Tuesday", order: 0, weekday: 3, exercises: [PersistenceFixtures.bench], in: plan, context: context)
        PersistenceFixtures.session("Late", startedAt: instant, endedAt: instant.addingTimeInterval(3600), in: context)

        let cairo = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(zone: "Africa/Cairo"))
        let kiritimati = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp(zone: "Pacific/Kiritimati"))

        // Dates are UTC in the file whoever wrote it; only the zone key differs.
        #expect(try PersistenceFixtures.sessions(in: PersistenceFixtures.object(cairo)).first?["startedAt"] as? String == "2026-03-10T22:30:00Z")
        var first = try PersistenceFixtures.object(cairo)
        var second = try PersistenceFixtures.object(kiritimati)
        #expect(first["timeZone"] as? String == "Africa/Cairo")
        #expect(second["timeZone"] as? String == "Pacific/Kiritimati")
        first["timeZone"] = nil
        second["timeZone"] = nil
        #expect(NSDictionary(dictionary: first).isEqual(to: second))

        let target = try TestStore.context()
        try BackupService.restore(data: kiritimati, context: target)
        let restored = try #require(target.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(restored.startedAt == instant)
        // The same instant is Tuesday night in UTC and already Wednesday in Cairo, which is
        // why the weekday on a plan day is read back as the lifter's, never converted.
        #expect(TestClock.calendar.component(.weekday, from: restored.startedAt) == 3)
        #expect(TestClock.calendar(in: "Africa/Cairo").component(.weekday, from: restored.startedAt) == 4)
        #expect(try target.fetch(FetchDescriptor<PlanDay>()).first?.weekday == 3)
    }

    @Test func restoreKeepsTheHealthLinkAlreadyOnThisPhone() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        let session = PersistenceFixtures.session(startedAt: t, endedAt: t.addingTimeInterval(3600), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: t), to: session, in: context)
        let file = try BackupService.exportData(context: context, stamp: stamp)
        #expect(!(try PersistenceFixtures.sessions(in: PersistenceFixtures.object(file))[0]).keys.contains("healthWorkoutID"))
        // The workout was saved to Health after the file was taken.
        let linked = UUID(uuidString: "5A3D1C20-0000-4000-8000-000000000042")!
        session.healthWorkoutID = linked
        try context.save()

        try BackupService.restore(data: file, context: context)

        let restored = try #require(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(restored.id == session.id)
        #expect(restored.healthWorkoutID == linked)
    }

    // MARK: - Restore replaces, refuses and rolls back

    @Test func restoreReplacesWhatIsOnThePhoneInsteadOfMergingIt() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        let oldPlan = PersistenceFixtures.plan("Old plan", createdAt: t, active: true, in: context)
        PersistenceFixtures.day("Old day", order: 0, weekday: 2, exercises: [PersistenceFixtures.squat], in: oldPlan, context: context)
        let oldSession = PersistenceFixtures.session("Old session", startedAt: t, endedAt: t.addingTimeInterval(3600), in: context)
        context.insert(BodyMetric(date: t, weightKg: 90))
        context.insert(HiddenExerciseRecord(catalogID: "deadlift"))
        try context.save()
        let donor = try donorBackup()

        try BackupService.restore(data: donor.data, context: context)

        let plans = try context.fetch(FetchDescriptor<Plan>())
        #expect(plans.map(\.name) == ["Donor plan"])
        #expect(plans.first?.id != oldPlan.id)
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>())
        #expect(sessions.map(\.title) == ["Donor session"])
        #expect(sessions.first?.id != oldSession.id)
        #expect(try context.fetchCount(FetchDescriptor<PlanDay>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<PlanItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BodyMetric>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HiddenExerciseRecord>()) == 0)
        #expect(!ExerciseCatalog.shared.isHidden("deadlift"))
    }

    @Test func restoreRefusesWhileAWorkoutIsOpenAndTouchesNothing() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        PersistenceFixtures.plan("Keep", createdAt: t, active: true, in: context)
        let open = PersistenceFixtures.session("Running", startedAt: t, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: t), to: open, in: context)
        try context.save()
        AppSettings.shared.userName = "Still me"
        let donor = try donorBackup()

        do {
            try BackupService.restore(data: donor.data, context: context)
            Issue.record("A restore over a running workout was accepted")
        } catch let error as BackupService.RestoreError {
            guard case .workoutInProgress = error else {
                Issue.record("Wrong refusal: \(error)")
                return
            }
        }

        #expect(try context.fetch(FetchDescriptor<Plan>()).map(\.name) == ["Keep"])
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(open.isActive && open.sets.count == 1)
        #expect(AppSettings.shared.userName == "Still me")
    }

    // MARK: - Erase

    @Test func eraseRemovesEverythingAndNeverTouchesHealthUnlessAsked() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        _ = try populate(context)
        try context.save()

        let result = try await BackupService.wipe(context: context)

        #expect(result == nil)
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanDay>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanItem>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseNote>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BodyMetric>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BodyMeasurement>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseLoadPreference>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<HiddenExerciseRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CustomExerciseRecord>()) == 0)
    }

    @Test func eraseRefusesWhileAWorkoutIsOpen() async throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let t = TestClock.at("2026-03-10T18:00:00")
        PersistenceFixtures.plan("Keep", createdAt: t, active: true, in: context)
        PersistenceFixtures.session("Running", startedAt: t, in: context)
        try context.save()

        do {
            try await BackupService.wipe(context: context)
            Issue.record("An erase over a running workout was accepted")
        } catch is BackupService.WipeError {
        }

        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
    }

    // MARK: - Fixtures

    private struct Populated {
        var pushDay: UUID
        var pushSession: UUID
        var afterwardsSession: UUID
        var dropSet: UUID
        var hardSet: UUID
        var healthWorkout: UUID
    }

    /// A store using every table and most of what a set can carry.
    private func populate(_ context: ModelContext) throws -> Populated {
        let bench = PersistenceFixtures.bench, plank = PersistenceFixtures.plank
        let plan = PersistenceFixtures.plan("Push Pull", createdAt: TestClock.at("2026-02-20T09:00:00"), active: true, in: context)
        plan.summary = "Two days a week"
        let push = PersistenceFixtures.day("Push", order: 0, weekday: 2, exercises: [bench, plank], in: plan, context: context)
        push.notes = "Bar path straight"
        let slot = try #require(push.orderedItems.first)
        slot.targetSets = 4
        slot.targetRepsLow = 5
        slot.targetRepsHigh = 8
        slot.targetWeightKg = 80
        slot.restSeconds = 120
        slot.notes = "Pause the first rep"
        try #require(push.orderedItems.last).targetSeconds = 60
        PersistenceFixtures.day("Rest", order: 1, weekday: 3, isRest: true, exercises: [], in: plan, context: context)
        PersistenceFixtures.day("Pull", order: 2, exercises: [PersistenceFixtures.pullUp], in: plan, context: context)

        let t = TestClock.at("2026-03-02T18:00:00")
        let health = UUID(uuidString: "5A3D1C20-0000-4000-8000-0000000000A1")!
        let session = PersistenceFixtures.session("Push", startedAt: t, endedAt: t.addingTimeInterval(3600),
                                                  planName: "Push Pull", planDayID: push.id, in: context)
        session.recordPlan(of: push)
        session.notes = "Felt strong"
        session.noteTagsRaw = [NoteTag.feltStrong.rawValue]
        session.averageHeartRate = 118
        session.maxHeartRate = 171
        session.activeEnergyKcal = 240
        session.heartRateSourceRaw = VitalsSource.watchWorkout.rawValue
        session.energySourceRaw = VitalsSource.watchWorkout.rawValue
        session.heartRateReadings = 600
        session.wasWatchDriven = true
        session.healthWorkoutID = health

        let solid = PersistenceFixtures.set(setIndex: 0, kg: 100, reps: 5, completedAt: t.addingTimeInterval(120))
        solid.rpe = SetFeel.solid.rawValue
        solid.startedAt = t.addingTimeInterval(90)
        let hard = PersistenceFixtures.decoratedSet(at: t.addingTimeInterval(400), setIndex: 1)
        let drop = PersistenceFixtures.set(setIndex: 2, kg: 80, reps: 6, completedAt: t.addingTimeInterval(560))
        drop.continuesPreviousSet = true
        let hold = SetLog(catalogID: plank.id, exerciseName: plank.name, exerciseOrder: 1, setIndex: 0,
                          seconds: 60, tracking: .duration)
        hold.isCompleted = true
        hold.completedAt = t.addingTimeInterval(900)
        for set in [solid, hard, drop, hold] { PersistenceFixtures.add(set, to: session, in: context) }
        let note = ExerciseNote(catalogID: bench.id, exerciseName: bench.name)
        note.text = "Left shoulder pinched"
        note.tags = [.pain]
        note.session = session
        context.insert(note)

        let later = TestClock.at("2026-03-04T12:00:00")
        let afterwards = PersistenceFixtures.session("Pull", startedAt: later, endedAt: later, in: context)
        afterwards.isLoggedAfterwards = true
        let pulls = PersistenceFixtures.set(PersistenceFixtures.pullUp, setIndex: 0, kg: 0, reps: 8)
        pulls.isCompleted = true
        PersistenceFixtures.add(pulls, to: afterwards, in: context)

        context.insert(BodyMetric(date: TestClock.at("2026-03-05T07:30:00"), weightKg: 82.5))
        let tape = BodyMeasurement(date: TestClock.at("2026-03-05T07:35:00"))
        tape.set(38.5, for: .arm)
        tape.set(81, for: .waist)
        context.insert(tape)
        context.insert(ExerciseLoadPreference(catalogID: bench.id, scale: LoadScale(unit: .kg, increment: 1.25)))
        context.insert(HiddenExerciseRecord(catalogID: "deadlift"))
        context.insert(CustomExerciseRecord(name: "Landmine Press", muscles: [], equipment: ["Barbell"], tracking: .weightReps))
        try context.save()
        return Populated(pushDay: push.id, pushSession: session.id, afterwardsSession: afterwards.id,
                         dropSet: drop.id, hardSet: hard.id, healthWorkout: health)
    }

    /// A backup written by some other phone, with nothing in common with the
    /// store a test restores it into.
    private func donorBackup() throws -> (data: Data, planID: UUID) {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let donor = try TestStore.context()
        let t = TestClock.at("2026-02-01T18:00:00")
        let plan = PersistenceFixtures.plan("Donor plan", createdAt: t, active: true, in: donor)
        PersistenceFixtures.day("Donor day", order: 0, weekday: 4, exercises: [], in: plan, context: donor)
        PersistenceFixtures.session("Donor session", startedAt: t, endedAt: t.addingTimeInterval(1800), in: donor)
        return (try BackupService.exportData(context: donor, stamp: PersistenceFixtures.stamp()), plan.id)
    }
}
