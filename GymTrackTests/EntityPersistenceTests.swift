import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// The SwiftData entities as the real `AppSchema` stores them: what an undone
/// set leaves behind, what a delete takes with it, and the derived values the
/// rest of the app reads off a session.
///
/// Complements the swiftc-built `Tests/SessionRulesTests.swift`,
/// `Tests/PlanRotationTests.swift` and the unlog and session-model checks beside
/// them, which cannot open the real schema. Everything here runs against an
/// in-memory store built from `AppSchema.models`.
@MainActor
@Suite(.serialized, .timeLimit(.minutes(1)))
struct EntityPersistenceTests {

    private let start = TestClock.at("2026-03-10T18:00:00")

    // MARK: - unlog() is the one place a set is erased

    @Test func unlogErasesEverythingLoggingGainedAndKeepsWhatTheRowIs() throws {
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, in: context)
        let set = PersistenceFixtures.decoratedSet(at: start, setIndex: 2)
        PersistenceFixtures.add(set, to: session, in: context)

        set.unlog()

        #expect(!set.isCompleted)
        #expect(set.completedAt == nil)
        #expect(set.rpe == nil)
        #expect(set.startedAt == nil)
        #expect(set.averageHeartRate == nil)
        #expect(set.maxHeartRate == nil)
        #expect(set.heartRateWindowRaw == nil)
        #expect(set.detectedStartedAt == nil)
        #expect(set.detectedEndedAt == nil)
        #expect(set.loadNudgeOutcomeRaw == nil)
        #expect(set.loadNudgeToKg == nil)
        // What the row is, not what logging added to it.
        #expect(set.setIndex == 2)
        #expect(set.exerciseOrder == 0)
        #expect(set.weightKg == 100)
        #expect(set.reps == 5)
        #expect(set.targetRepsLow == 5)
        #expect(set.targetRepsHigh == 8)
        #expect(set.session === session)
    }

    @Test func unloggedSetStaysClearedAfterASaveAndAFreshFetch() throws {
        let container = try TestStore.container()
        let context = ModelContext(container)
        let session = PersistenceFixtures.session(startedAt: start, in: context)
        let set = PersistenceFixtures.decoratedSet(at: start, setIndex: 0)
        PersistenceFixtures.add(set, to: session, in: context)
        try context.save()

        set.unlog()
        try context.save()

        // A second context reads the saved rows, not the first one's objects.
        let reader = ModelContext(container)
        let stored = try #require(reader.fetch(FetchDescriptor<SetLog>()).first)
        #expect(stored.id == set.id)
        #expect(!stored.isCompleted)
        #expect(stored.completedAt == nil)
        #expect(stored.rpe == nil)
        #expect(stored.startedAt == nil)
        #expect(stored.averageHeartRate == nil)
        #expect(stored.loadNudgeOutcomeRaw == nil)
        #expect(stored.weightKg == 100)
    }

    @Test func unloggedSetLeavesNoKeyInTheExport() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, endedAt: start.addingTimeInterval(3600),
                                                  in: context)
        let set = PersistenceFixtures.decoratedSet(at: start, setIndex: 0)
        PersistenceFixtures.add(set, to: session, in: context)
        set.unlog()

        let data = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp())
        let sets = try PersistenceFixtures.sets(in: PersistenceFixtures.object(data), sessionIndex: 0)
        let exported = try #require(sets.first)

        // Absent, not null and not zero: the keys must not be there at all.
        for key in ["rpe", "effort", "startedAt", "completedAt", "averageHeartRate", "maxHeartRate",
                    "heartRateWindow", "detectedStartedAt", "detectedEndedAt", "loadNudge", "continues"] {
            #expect(!exported.keys.contains(key), "\(key) survived an undone set")
        }
        #expect(exported["isCompleted"] as? Bool == false)
        #expect(exported["weightKg"] as? Double == 100)
    }

    @Test func unloggingADropRowKeepsItAContinuation() throws {
        let saved = PersistenceFixtures.pin()
        defer { saved.restore() }
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, endedAt: start.addingTimeInterval(3600),
                                                  in: context)
        let parent = PersistenceFixtures.set(setIndex: 0, kg: 100, reps: 5, completedAt: start)
        let drop = PersistenceFixtures.set(setIndex: 1, kg: 80, reps: 6, completedAt: start.addingTimeInterval(20))
        drop.continuesPreviousSet = true
        PersistenceFixtures.add(parent, to: session, in: context)
        PersistenceFixtures.add(drop, to: session, in: context)

        drop.unlog()

        #expect(drop.isContinuation)
        #expect(drop.continuation == .drop)
        let data = try BackupService.exportData(context: context, stamp: PersistenceFixtures.stamp())
        let sets = try PersistenceFixtures.sets(in: PersistenceFixtures.object(data), sessionIndex: 0)
        #expect(sets.count == 2)
        #expect(sets[1]["continues"] as? String == "drop")
        #expect(!sets[1].keys.contains("completedAt"))
    }

    @Test func unloggingASetThatWasNeverLoggedChangesNothing() throws {
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, in: context)
        let set = PersistenceFixtures.set(setIndex: 3, kg: 60, reps: 10)
        PersistenceFixtures.add(set, to: session, in: context)

        set.unlog()
        set.unlog()

        #expect(!set.isCompleted)
        #expect(set.completedAt == nil && set.rpe == nil && set.startedAt == nil)
        #expect(!set.hasHeartRate)
        #expect(set.detectedWindow == nil)
        #expect(set.loadNudgeOutcome == nil)
        #expect(set.setIndex == 3 && set.weightKg == 60 && set.reps == 10)
    }

    // MARK: - Relationships and cascade deletes

    @Test func relationshipsSurviveASaveAndLoadFromAFreshContext() throws {
        let container = try TestStore.container()
        let context = ModelContext(container)
        let plan = PersistenceFixtures.plan("Push Pull", createdAt: start, active: true, in: context)
        let day = PersistenceFixtures.day("Push", order: 0, weekday: 2, exercises: [PersistenceFixtures.bench], in: plan, context: context)
        let session = PersistenceFixtures.session(startedAt: start, endedAt: start.addingTimeInterval(3600),
                                                  planDayID: day.id, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: start), to: session, in: context)
        let note = ExerciseNote(catalogID: PersistenceFixtures.bench.id, exerciseName: PersistenceFixtures.bench.name)
        note.session = session
        context.insert(note)
        try context.save()

        let reader = ModelContext(container)
        let storedPlan = try #require(reader.fetch(FetchDescriptor<Plan>()).first)
        let storedDay = try #require(storedPlan.days.first)
        #expect(storedPlan.days.count == 1)
        #expect(storedDay.items.count == 1)
        #expect(storedDay.items.first?.day === storedDay)
        #expect(storedDay.plan === storedPlan)
        let storedSession = try #require(reader.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(storedSession.sets.count == 1)
        #expect(storedSession.sets.first?.session === storedSession)
        #expect(storedSession.exerciseNotes.count == 1)
        #expect(storedSession.planDayID == storedDay.id)
    }

    @Test func deletingAPlanTakesItsDaysAndSlotsButNotTheHistory() throws {
        let context = try TestStore.context()
        let plan = PersistenceFixtures.plan("Old", createdAt: start, active: true, in: context)
        let push = PersistenceFixtures.day("Push", order: 0, weekday: 2, exercises: [PersistenceFixtures.bench, PersistenceFixtures.squat], in: plan, context: context)
        _ = PersistenceFixtures.day("Pull", order: 1, exercises: [PersistenceFixtures.pullUp], in: plan, context: context)
        let session = PersistenceFixtures.session(startedAt: start, endedAt: start.addingTimeInterval(3600),
                                                  planName: "Old", planDayID: push.id, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: start), to: session, in: context)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PlanDay>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<PlanItem>()) == 3)

        context.delete(plan)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanDay>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PlanItem>()) == 0)
        // The session holds the day as a bare ID and its name as text: nothing
        // cascades into history.
        let kept = try #require(context.fetch(FetchDescriptor<WorkoutSession>()).first)
        #expect(kept.sets.count == 1)
        #expect(kept.planDayID == push.id)
        #expect(kept.planName == "Old")
    }

    @Test func deletingADayLeavesItsSiblingsAndTheirSlots() throws {
        let context = try TestStore.context()
        let plan = PersistenceFixtures.plan("Split", createdAt: start, active: true, in: context)
        let push = PersistenceFixtures.day("Push", order: 0, exercises: [PersistenceFixtures.bench, PersistenceFixtures.squat], in: plan, context: context)
        let pull = PersistenceFixtures.day("Pull", order: 1, exercises: [PersistenceFixtures.pullUp], in: plan, context: context)
        try context.save()

        context.delete(push)
        try context.save()

        #expect(plan.days.map(\.id) == [pull.id])
        #expect(try context.fetchCount(FetchDescriptor<PlanItem>()) == 1)
        #expect(pull.items.count == 1)
    }

    @Test func deletingASessionTakesItsSetsAndNotesAndNothingElse() throws {
        let context = try TestStore.context()
        let doomed = PersistenceFixtures.session("Doomed", startedAt: start, endedAt: start.addingTimeInterval(3600), in: context)
        let kept = PersistenceFixtures.session("Kept", startedAt: start.addingTimeInterval(86_400),
                                               endedAt: start.addingTimeInterval(90_000), in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: start), to: doomed, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 1, completedAt: start), to: doomed, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: start), to: kept, in: context)
        let note = ExerciseNote(catalogID: PersistenceFixtures.bench.id, exerciseName: PersistenceFixtures.bench.name)
        note.session = doomed
        context.insert(note)
        context.insert(BodyMetric(date: start, weightKg: 82))
        try context.save()

        context.delete(doomed)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<WorkoutSession>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<ExerciseNote>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BodyMetric>()) == 1)
        #expect(kept.sets.count == 1)
    }

    // MARK: - Derived values

    @Test func effortSetsLeaveOutContinuationRowsButVolumeKeepsTheirWork() throws {
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, in: context)
        let top = PersistenceFixtures.set(setIndex: 0, kg: 100, reps: 5, completedAt: start)
        let drop = PersistenceFixtures.set(setIndex: 1, kg: 80, reps: 6, completedAt: start.addingTimeInterval(20))
        drop.continuesPreviousSet = true
        let next = PersistenceFixtures.set(setIndex: 2, kg: 100, reps: 4, completedAt: start.addingTimeInterval(200))
        let unlogged = PersistenceFixtures.set(setIndex: 3, kg: 100, reps: 5)
        for set in [top, drop, next, unlogged] { PersistenceFixtures.add(set, to: session, in: context) }

        #expect(session.completedSets.count == 3)
        #expect(session.effortSets.map(\.setIndex) == [0, 2])
        // The unlogged row counts as a set to do, the continuation does not.
        #expect(session.effortCount == 3)
        // 100x5 + 80x6 + 100x4: the drop's reps were lifted, the unlogged row's were not.
        #expect(session.totalVolumeKg == 500 + 480 + 400)
        #expect(session.totalReps == 15)
    }

    @Test func exerciseGroupsFollowExerciseOrderThenSetIndexWhateverTheInsertOrder() throws {
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, in: context)
        let bench = PersistenceFixtures.bench, squat = PersistenceFixtures.squat
        let rows: [(PersistenceFixtures.Exercise, Int, Int)] = [
            (squat, 1, 1), (bench, 0, 2), (squat, 1, 0), (bench, 0, 0), (bench, 0, 1),
        ]
        for (exercise, order, index) in rows {
            PersistenceFixtures.add(PersistenceFixtures.set(exercise, order: order, setIndex: index), to: session, in: context)
        }

        func shape() -> [String] {
            session.exerciseGroups.map { "\($0.catalogID):" + $0.sets.map { String($0.setIndex) }.joined(separator: ",") }
        }
        #expect(shape() == ["barbell-bench-press:0,1,2", "barbell-back-squat:0,1"])

        // A late arrival, such as a set the wrist logged after the rest.
        PersistenceFixtures.add(PersistenceFixtures.set(bench, order: 0, setIndex: 3), to: session, in: context)
        #expect(shape() == ["barbell-bench-press:0,1,2,3", "barbell-back-squat:0,1"])
        #expect(session.exerciseGroups.map(\.name) == ["Barbell Bench Press", "Barbell Back Squat"])
    }

    @Test(arguments: [
        PersistenceHealthReading(energy: nil, average: nil, peak: nil, hasMetrics: false),
        PersistenceHealthReading(energy: 0, average: nil, peak: nil, hasMetrics: false),
        PersistenceHealthReading(energy: 0.4, average: nil, peak: nil, hasMetrics: false),
        PersistenceHealthReading(energy: 1, average: nil, peak: nil, hasMetrics: true),
        PersistenceHealthReading(energy: nil, average: 118, peak: nil, hasMetrics: true),
        PersistenceHealthReading(energy: 0, average: nil, peak: 171, hasMetrics: true),
    ])
    func zeroEnergyIsNothingRecordedNotAWorkoutThatCostNothing(_ reading: PersistenceHealthReading) throws {
        let session = WorkoutSession(title: "Push", startedAt: start)
        session.activeEnergyKcal = reading.energy
        session.averageHeartRate = reading.average
        session.maxHeartRate = reading.peak

        #expect(session.hasHealthMetrics == reading.hasMetrics)
        let energy = reading.energy ?? 0
        #expect(session.reportableEnergyKcal == (energy >= 1 ? energy : nil))
    }

    // MARK: - Stale sessions and closing

    @Test func staleBoundaryIsExclusiveAndFinishedSessionsAreNeverStale() {
        let open = WorkoutSession(title: "Push", startedAt: start)
        let limit = WorkoutSession.staleAfter

        #expect(!open.isStale(at: start))
        #expect(!open.isStale(at: start.addingTimeInterval(limit)))
        #expect(open.isStale(at: start.addingTimeInterval(limit + 1)))

        open.endedAt = start.addingTimeInterval(3600)
        #expect(!open.isStale(at: start.addingTimeInterval(limit * 3)))
    }

    @Test func closingAStaleSessionEndsItAtTheLastSetNotAtTheLateFinish() throws {
        let dropped = TestClock.freshDefaults()
        DroppedSetMemory.shared.replaceStore(with: dropped)
        defer { DroppedSetMemory.shared.replaceStore(with: .standard) }
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, in: context)
        let lastSet = start.addingTimeInterval(1800)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: lastSet), to: session, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 1), to: session, in: context)
        let nextMorning = start.addingTimeInterval(20 * 3600)

        session.close(at: nextMorning, in: context)
        try context.save()

        #expect(session.endedAt == lastSet)
        #expect(session.sets.count == 1)
        #expect(try context.fetchCount(FetchDescriptor<SetLog>()) == 1)
    }

    @Test func closingASessionStillInDateEndsItAtTheMomentGiven() throws {
        DroppedSetMemory.shared.replaceStore(with: TestClock.freshDefaults())
        defer { DroppedSetMemory.shared.replaceStore(with: .standard) }
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: start.addingTimeInterval(600)), to: session, in: context)
        let finish = start.addingTimeInterval(3600)

        session.close(at: finish, in: context)

        #expect(session.endedAt == finish)
        #expect(!session.isActive)
    }

    @Test func wristFinishNeverLandsBeforeTheLastSetOrAfterNow() throws {
        let context = try TestStore.context()
        let session = PersistenceFixtures.session(startedAt: start, in: context)
        let lastSet = start.addingTimeInterval(1800)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: lastSet), to: session, in: context)
        let now = start.addingTimeInterval(3600)

        #expect(session.wristFinishMoment(nil, now: now) == now)
        #expect(session.wristFinishMoment(start.addingTimeInterval(2700), now: now) == start.addingTimeInterval(2700))
        // A stamp from ahead of this clock is two devices disagreeing.
        #expect(session.wristFinishMoment(start.addingTimeInterval(5400), now: now) == now)
        // A set logged after the end would say the lifter trained after stopping.
        #expect(session.wristFinishMoment(start.addingTimeInterval(600), now: now) == lastSet)
    }

    @Test func closeIfStaleDeletesAnEmptySessionAndClosesOneThatHasSets() throws {
        DroppedSetMemory.shared.replaceStore(with: TestClock.freshDefaults())
        defer { DroppedSetMemory.shared.replaceStore(with: .standard) }
        let context = try TestStore.context()
        // Started in 2000, so stale on any day this test can run.
        let long = TestClock.at("2000-01-01T10:00:00")
        let empty = PersistenceFixtures.session("Empty", startedAt: long, in: context)
        let trained = PersistenceFixtures.session("Trained", startedAt: long, in: context)
        let lastSet = long.addingTimeInterval(1200)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: lastSet), to: trained, in: context)
        let fresh = WorkoutSession(title: "Fresh", startedAt: .now)
        context.insert(fresh)

        #expect(empty.closeIfStale(in: context))
        #expect(trained.closeIfStale(in: context))
        #expect(!fresh.closeIfStale(in: context))
        try context.save()

        let titles = try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.title).sorted()
        #expect(titles == ["Fresh", "Trained"])
        #expect(trained.endedAt == lastSet)
        #expect(fresh.isActive)
    }

    /// The twelve-hour rule every path shares, asked the way the app asks it:
    /// of the wall clock, so these sessions are placed by offsets from it.
    /// Thirteen hours is yesterday's session; eleven is still somebody's workout.
    @Test func aStaleSessionIsClosedWithoutItsUnliftedRowsAndAnElevenHourOneIsLeftAlone() throws {
        DroppedSetMemory.shared.replaceStore(with: TestClock.freshDefaults())
        defer { DroppedSetMemory.shared.replaceStore(with: .standard) }
        let context = try TestStore.context()
        let now = Date.now
        func session(_ title: String, startedHoursAgo hours: Double, loggedAfterMinutes minutes: Double?) -> WorkoutSession {
            let session = PersistenceFixtures.session(title, startedAt: now.addingTimeInterval(-hours * 3600), in: context)
            if let minutes {
                let lifted = PersistenceFixtures.set(setIndex: 0, completedAt: session.startedAt.addingTimeInterval(minutes * 60))
                PersistenceFixtures.add(lifted, to: session, in: context)
            }
            PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 1), to: session, in: context)
            return session
        }
        let lifted = session("Lifted", startedHoursAgo: 13, loggedAfterMinutes: 40)
        let empty = session("Empty", startedHoursAgo: 13, loggedAfterMinutes: nil)
        let recent = session("Recent", startedHoursAgo: 11, loggedAfterMinutes: 40)
        try context.save()
        let lastSet = lifted.startedAt.addingTimeInterval(40 * 60)

        #expect(lifted.isStale() && empty.isStale())
        #expect(!recent.isStale())
        #expect(lifted.closeIfStale(in: context))
        #expect(empty.closeIfStale(in: context))
        #expect(!recent.closeIfStale(in: context))
        try context.save()

        #expect(lifted.endedAt == lastSet, "a stale session ends at its last set, not when the app noticed")
        #expect(lifted.sets.count == 1 && lifted.sets.first?.isCompleted == true)
        let titles = try context.fetch(FetchDescriptor<WorkoutSession>()).map(\.title).sorted()
        #expect(titles == ["Lifted", "Recent"], "a stale session with nothing logged is deleted")
        #expect(recent.isActive && recent.sets.count == 2)

        // A Finish on a session left open overnight goes through `close`, which
        // every Finish does, and is held to the same rule.
        let overnight = session("Overnight", startedHoursAgo: 20, loggedAfterMinutes: 55)
        try context.save()
        overnight.close(in: context)
        #expect(overnight.endedAt == overnight.startedAt.addingTimeInterval(55 * 60))
    }

    // MARK: - Plans

    @Test(arguments: 1...7)
    func eachWeekdayFindsOnlyTheTrainingDayPinnedToIt(_ weekday: Int) throws {
        let context = try TestStore.context()
        let plan = PersistenceFixtures.plan("Week", createdAt: start, active: true, in: context)
        for day in 1...7 {
            _ = PersistenceFixtures.day("Day \(day)", order: day, weekday: day, exercises: [PersistenceFixtures.bench], in: plan, context: context)
        }

        #expect(plan.day(onWeekday: weekday)?.name == "Day \(weekday)")
    }

    @Test func aRestDayAnEmptyDayAnUnpinnedDayAndAnOutOfRangeWeekdayAreNeverScheduled() throws {
        let context = try TestStore.context()
        let plan = PersistenceFixtures.plan("Odd", createdAt: start, active: true, in: context)
        PersistenceFixtures.day("Rest", order: 0, weekday: 1, isRest: true, exercises: [PersistenceFixtures.bench], in: plan, context: context)
        PersistenceFixtures.day("Empty", order: 1, weekday: 2, exercises: [], in: plan, context: context)
        let floating = PersistenceFixtures.day("Floating", order: 2, weekday: nil, exercises: [PersistenceFixtures.bench], in: plan, context: context)
        PersistenceFixtures.day("Broken", order: 3, weekday: 9, exercises: [PersistenceFixtures.bench], in: plan, context: context)

        // Calendar weekdays are 1 through 7; none of them lands on any of these.
        for weekday in 1...7 { #expect(plan.day(onWeekday: weekday) == nil, "weekday \(weekday)") }
        #expect(plan.trainingDayCount == 2)

        // A weekday outside 1...7 counts as unpinned, so that day takes its turn
        // in the rotation instead of never coming round.
        #expect(plan.nextInRotation(after: [])?.name == "Floating")
        let trained = PersistenceFixtures.session("Floating", startedAt: start, endedAt: start.addingTimeInterval(3600),
                                                  planDayID: floating.id, in: context)
        PersistenceFixtures.add(PersistenceFixtures.set(setIndex: 0, completedAt: start), to: trained, in: context)
        #expect(plan.nextInRotation(after: [trained])?.name == "Broken")
    }

    @Test func theDisplayedPlanIsTheActiveOneOrElseTheFirstCreated() throws {
        let context = try TestStore.context()
        #expect(Plan.displayed(among: []) == nil)

        let first = PersistenceFixtures.plan("First", createdAt: start, active: false, in: context)
        #expect(Plan.displayed(among: [first]) === first)

        let second = PersistenceFixtures.plan("Second", createdAt: start.addingTimeInterval(60), active: false, in: context)
        let third = PersistenceFixtures.plan("Third", createdAt: start.addingTimeInterval(120), active: false, in: context)
        // None active: the first created, whichever way the store handed them over.
        #expect(Plan.displayed(among: [third, second, first]) === first)

        third.isActive = true
        #expect(Plan.displayed(among: [first, second, third]) === third)

        // Two flagged active, which a restored hand-edited file can produce.
        second.isActive = true
        #expect(Plan.displayed(among: [third, second, first]) === second)
    }

    @Test func aBlankRoutineIsInsertedWithNoDaysAndTheRequestedFlag() throws {
        let context = try TestStore.context()

        let active = Plan.blank(in: context, makeActive: true)
        let spare = Plan.blank(in: context, makeActive: false)
        try context.save()

        #expect(active.isActive && !spare.isActive)
        #expect(active.days.isEmpty && active.trainingDayCount == 0)
        #expect(try context.fetchCount(FetchDescriptor<Plan>()) == 2)
    }
}

/// One reading of what Health supplied for a session, and whether it counts.
struct PersistenceHealthReading: Sendable {
    var energy: Double?
    var average: Double?
    var peak: Double?
    var hasMetrics: Bool
}

// MARK: - Builders shared by the persistence and backup suites

/// Builders and JSON helpers for `EntityPersistenceTests` and the `Backup*Tests`
/// suites. Named for what they serve so no other suite's helpers collide with
/// them.
@MainActor
enum PersistenceFixtures {

    struct Exercise {
        var id: String
        var name: String
    }

    static let bench = Exercise(id: "barbell-bench-press", name: "Barbell Bench Press")
    static let squat = Exercise(id: "barbell-back-squat", name: "Barbell Back Squat")
    static let pullUp = Exercise(id: "pull-up", name: "Pull-Up")
    static let plank = Exercise(id: "plank-bodyweight", name: "Plank")

    /// What a test changes in the process-wide settings, put back by `restore`.
    /// Restore writes the unit, name and rest into `AppSettings.shared`, and
    /// registers custom and hidden exercises in the shared catalog, so every
    /// test that exports or restores pins first and restores in `defer`.
    struct Pin {
        let unit = AppSettings.shared.weightUnit
        let name = AppSettings.shared.userName
        let rest = AppSettings.shared.defaultRestSeconds

        func restore() {
            AppSettings.shared.weightUnit = unit
            AppSettings.shared.userName = name
            AppSettings.shared.defaultRestSeconds = rest
            ExerciseCatalog.shared.setCustom([])
            ExerciseCatalog.shared.setHidden([])
            LoadScaleBook.shared.reload()
        }
    }

    /// Captures the settings, then sets the baseline a test starts from.
    static func pin() -> Pin {
        let pin = Pin()
        AppSettings.shared.weightUnit = .kg
        AppSettings.shared.userName = "Test Lifter"
        AppSettings.shared.defaultRestSeconds = 90
        ExerciseCatalog.shared.setCustom([])
        ExerciseCatalog.shared.setHidden([])
        return pin
    }

    /// The ID numbered `n`, for fixtures whose rows have to sort, or be found,
    /// by a known ID.
    nonisolated static func uuid(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012X", n))!
    }

    /// A stamp with the clock and the zone held still, so two exports of one
    /// store are the same bytes.
    static func stamp(at moment: Date = TestClock.reference, zone: String = "Africa/Cairo",
                      version: String? = "1.4.2", build: String? = "57") -> BackupService.ExportStamp {
        BackupService.ExportStamp(exportedAt: moment, timeZone: TimeZone(identifier: zone)!,
                                  appVersion: version, appBuild: build)
    }

    @discardableResult
    static func session(_ title: String = "Push", startedAt: Date, endedAt: Date? = nil, planName: String = "",
                        planDayID: UUID? = nil, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: title, planDayID: planDayID, planName: planName, startedAt: startedAt)
        session.endedAt = endedAt
        context.insert(session)
        return session
    }

    /// A reps set. Logged when `completedAt` is given.
    static func set(_ exercise: Exercise? = nil, order: Int = 0, setIndex: Int, kg: Double = 100,
                    reps: Int = 5, completedAt: Date? = nil) -> SetLog {
        let exercise = exercise ?? bench
        let set = SetLog(catalogID: exercise.id, exerciseName: exercise.name, exerciseOrder: order,
                         setIndex: setIndex, weightKg: kg, reps: reps)
        if let completedAt {
            set.isCompleted = true
            set.completedAt = completedAt
        }
        return set
    }

    /// A logged set carrying every piece of data logging can attach.
    static func decoratedSet(at moment: Date, setIndex: Int) -> SetLog {
        let set = SetLog(catalogID: bench.id, exerciseName: bench.name, exerciseOrder: 0, setIndex: setIndex,
                         weightKg: 100, reps: 5, targetRepsLow: 5, targetRepsHigh: 8)
        set.isCompleted = true
        set.completedAt = moment.addingTimeInterval(60)
        set.startedAt = moment
        set.rpe = SetFeel.hard.rawValue
        set.averageHeartRate = 150
        set.maxHeartRate = 168
        set.heartRateWindowRaw = HeartRateWindowSource.measured.rawValue
        set.recordDetectedWindow(DetectedSetWindow(start: moment.addingTimeInterval(5), end: moment.addingTimeInterval(50)))
        set.recordLoadNudge(.taken, toKg: 102.5)
        return set
    }

    static func add(_ set: SetLog, to session: WorkoutSession, in context: ModelContext) {
        set.session = session
        context.insert(set)
    }

    @discardableResult
    static func plan(_ name: String, createdAt: Date, active: Bool, in context: ModelContext) -> Plan {
        let plan = Plan(name: name, isActive: active)
        plan.createdAt = createdAt
        context.insert(plan)
        return plan
    }

    @discardableResult
    static func day(_ name: String, order: Int, weekday: Int? = nil, isRest: Bool = false,
                    exercises: [Exercise], in plan: Plan, context: ModelContext) -> PlanDay {
        let day = PlanDay(name: name, order: order, weekday: weekday, isRest: isRest)
        day.plan = plan
        context.insert(day)
        for (index, exercise) in exercises.enumerated() {
            let item = PlanItem(catalogID: exercise.id, name: exercise.name, order: index)
            item.day = day
            context.insert(item)
        }
        return day
    }

    // MARK: JSON

    static func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    static func sessions(in root: [String: Any]) throws -> [[String: Any]] {
        try #require(root["sessions"] as? [[String: Any]])
    }

    static func sets(in root: [String: Any], sessionIndex: Int) throws -> [[String: Any]] {
        let session = try #require(sessions(in: root)[sessionIndex] as [String: Any]?)
        return try #require(session["sets"] as? [[String: Any]])
    }
}
