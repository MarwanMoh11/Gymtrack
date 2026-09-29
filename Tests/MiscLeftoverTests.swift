import Foundation
import Observation
import SwiftData

/// Run with scripts/test-misc-leftovers.sh; no simulator is needed.
///
/// The wave-6 leftovers that reach a pure function: a custom exercise's rename
/// and the tracking record on its plan slots (`ExerciseEditorView.save()` and
/// `RootView.syncCustomExercises` call these), the summary's history fetch
/// (LOG-13), and the live-metrics merge (LOG-12).
///
/// What no test here reaches: the editor and `RootView` actually calling
/// them, and `WatchBridge` (WatchConnectivity has no macOS build) assigning
/// only a non-nil answer.
@main
@MainActor
struct MiscLeftoverTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ message: @autoclosure () -> String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message())")
    }

    static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        try renameReachesSlotsOnly(context)
        try slotsKeepTheirTrackingWhenTheExerciseGoes(context)
        try summaryMatchesTheWholeHistoryWalk(context)
        liveMetricsAssignOnlyOnChange()
        if failures > 0 { print("\(failures) failure(s)"); exit(1) }
        print("misc leftovers: all checks passed")
    }

    static func slot(_ id: String, _ name: String, in context: ModelContext) -> PlanItem {
        let item = PlanItem(catalogID: id, name: name, order: 0)
        context.insert(item)
        return item
    }

    // MARK: - Rename

    static func renameReachesSlotsOnly(_ context: ModelContext) throws {
        let mine = slot("custom-aaaa", "Old name", in: context)
        let again = slot("custom-aaaa", "Old name", in: context)
        let other = slot("custom-bbbb", "Other", in: context)
        let bundled = slot("bench-press", "Bench Press", in: context)
        let past = SetLog(catalogID: "custom-aaaa", exerciseName: "Old name",
                          exerciseOrder: 0, setIndex: 0, weightKg: 20, reps: 8, tracking: .weightReps)
        past.isCompleted = true
        context.insert(past)
        try context.save()

        let changed = try context.renamePlanSlots(of: "custom-aaaa", to: "New name")
        expect(changed == 2, "both slots of the exercise are renamed, got \(changed)")
        expect(mine.name == "New name" && again.name == "New name", "the slots carry the new name")
        expect(other.name == "Other" && bundled.name == "Bench Press", "another exercise's slots are left alone")
        expect(past.exerciseName == "Old name", "a logged set keeps the name it was performed under")

        expect(try context.renamePlanSlots(of: "custom-aaaa", to: "New name") == 0,
               "renaming to the name already held changes nothing")
        expect(try context.renamePlanSlots(of: "custom-aaaa", to: "  \n") == 0 && mine.name == "New name",
               "a blank name must not reach the slots")
    }

    // MARK: - Tracking record on custom slots

    static func slotsKeepTheirTrackingWhenTheExerciseGoes(_ context: ModelContext) throws {
        let hold = CustomExerciseRecord(name: "Dead Hang", muscles: [], equipment: [], tracking: .duration)
        context.insert(hold)
        let plain = slot(hold.id, "Dead Hang", in: context)
        let stamped = slot(hold.id, "Dead Hang", in: context)
        stamped.trackingRaw = TrackingMode.duration.rawValue
        let bundled = slot("bench-press", "Bench Press", in: context)
        let elsewhere = slot("custom-gone", "Unknown", in: context)
        try context.save()

        ExerciseCatalog.shared.setCustom([hold.asCatalogExercise])
        let stampedCount = try context.snapshotCustomSlotTracking(of: [hold.asCatalogExercise])
        expect(stampedCount == 1, "only the slot without a record is stamped, got \(stampedCount)")
        expect(plain.trackingRaw == TrackingMode.duration.rawValue, "the slot takes the exercise's tracking")
        expect(bundled.trackingRaw == nil, "a bundled exercise's slot has nothing to snapshot")
        expect(elsewhere.trackingRaw == nil, "a slot of an exercise not in the list is not guessed at")
        expect(try context.snapshotCustomSlotTracking(of: [hold.asCatalogExercise]) == 0, "a second pass stamps nothing")
        expect(try context.snapshotCustomSlotTracking(of: []) == 0, "no custom exercises, nothing to stamp")

        // The failure this exists for: the exercise vanishes, and the slot
        // must still read a hold as a hold.
        ExerciseCatalog.shared.setCustom([])
        expect(plain.tracking == .duration, "a slot outlives its exercise measuring what it measured")
    }

    // MARK: - LOG-13

    static func set(_ id: String, kg: Double = 0, reps: Int = 0, seconds: Int = 0, index: Int = 0,
                    tracking: TrackingMode = .weightReps, continues: Bool = false) -> SetLog {
        let set = SetLog(catalogID: id, exerciseName: id, exerciseOrder: 0, setIndex: index,
                         weightKg: kg, reps: reps, seconds: seconds, tracking: tracking)
        if continues { set.continuesPreviousSet = true }
        return set
    }

    static func finished(on date: Date, _ sets: [SetLog], active: Bool = false,
                         in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(title: "Test", startedAt: date)
        if !active { session.endedAt = date.addingTimeInterval(3_600) }
        context.insert(session)
        for (offset, set) in sets.enumerated() {
            set.isCompleted = true
            set.completedAt = date.addingTimeInterval(Double(offset + 1) * 60)
            set.session = session
            context.insert(set)
        }
        return session
    }

    /// The summary asks for the sets of the session's own exercises only, and
    /// must name the same record rows the whole-history walk names, including
    /// through a merged ID, and without sets that belong to no session.
    static func summaryMatchesTheWholeHistoryWalk(_ context: ModelContext) throws {
        let day0 = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func day(_ n: Int) -> Date { day0.addingTimeInterval(Double(n) * 86_400) }

        let older = finished(on: day(0), [
            set("bench-x", kg: 60, reps: 8), set("plank-x", seconds: 50, tracking: .duration),
            set("scaption-dumbbell", kg: 5, reps: 10),
            set("bench-x", kg: 100, reps: 5, index: 1, continues: true),
        ], in: context)
        let unrelated = finished(on: day(1), [set("row-x", kg: 80, reps: 8)], in: context)
        let running = finished(on: day(2), [set("bench-x", kg: 200, reps: 1)], active: true, in: context)
        let orphan = set("plank-x", seconds: 999, tracking: .duration)
        orphan.isCompleted = true
        orphan.completedAt = day(0)
        context.insert(orphan)
        let today = finished(on: day(3), [
            set("bench-x", kg: 70, reps: 8), set("plank-x", seconds: 60, tracking: .duration),
            set("plank-x", seconds: 75, index: 1, tracking: .duration),
            set("scaption", kg: 8, reps: 10), set("squat-x", kg: 90, reps: 5),
        ], in: context)
        try context.save()

        let history = try context.fetch(FetchDescriptor<WorkoutSession>())
        let whole = TrainingStats.summaryRecords(for: today, history: history).map(\.id)
        let scoped = try SummaryRecords.sets(for: today, in: context).map(\.id)
        expect(!whole.isEmpty, "the fixture must produce records, or the comparison proves nothing")
        expect(scoped == whole, "the scoped fetch must name the same record rows as the whole walk")
        expect(whole.count == 2, "the longer plank and the merged scaption are the records; bench is out-lifted by the running session, got \(whole.count)")
        _ = (older, unrelated, running)

        let nothing = finished(on: day(4), [], in: context)
        expect(try SummaryRecords.sets(for: nothing, in: context).isEmpty, "a session with no sets has no records")
        expect(SummaryRecords.spellings(of: ["scaption"]).contains("scaption-dumbbell"),
               "a merged spelling is searched under its survivor")
    }

    // MARK: - LOG-12

    @Observable final class Holder { var metrics: WatchWorkoutMetrics? }
    final class Counter: @unchecked Sendable { var notified = 0; var registered = false }

    static func liveMetricsAssignOnlyOnChange() {
        let id = UUID()
        func reading(_ bpm: Double) -> WatchWorkoutMetrics {
            WatchWorkoutMetrics(sessionID: id, currentHeartRate: bpm)
        }
        let holder = Holder()
        let counter = Counter()
        /// One observation at a time: `withObservationTracking` fires once, and
        /// a registration left pending by a fold that changed nothing would be
        /// counted again by the next one.
        func fold(_ incoming: WatchWorkoutMetrics) {
            if !counter.registered {
                counter.registered = true
                withObservationTracking { _ = holder.metrics } onChange: {
                    counter.notified += 1
                    counter.registered = false
                }
            }
            // The bridge's own pattern: assign a non-nil answer, nothing else.
            if let merged = WatchWorkoutMetrics.merged(incoming, into: holder.metrics) { holder.metrics = merged }
        }
        var notified: Int { counter.notified }

        fold(reading(120))
        expect(notified == 1 && holder.metrics?.currentHeartRate == 120, "the first reading is a change")
        fold(reading(120))
        expect(notified == 1, "the same reading again must not notify readers, got \(notified)")
        fold(reading(121))
        expect(notified == 2 && holder.metrics?.currentHeartRate == 121, "a new reading is a change")
        fold(WatchWorkoutMetrics(sessionID: id, maxHeartRate: 140))
        expect(notified == 3 && holder.metrics?.maxHeartRate == 140, "a first max is a change")
        fold(WatchWorkoutMetrics(sessionID: id, maxHeartRate: 100))
        expect(notified == 3, "a lower max folds into nothing new and must not notify, got \(notified)")
        fold(WatchWorkoutMetrics(sessionID: id, maxHeartRate: 150))
        expect(notified == 4 && holder.metrics?.maxHeartRate == 150, "a higher max is a change")

        expect(WatchWorkoutMetrics.merged(WatchWorkoutMetrics(sessionID: UUID()), into: holder.metrics) != nil,
               "a payload for another session replaces what is held")
        expect(WatchWorkoutMetrics.merged(WatchWorkoutMetrics(sessionID: id), into: nil) != nil,
               "the first payload of a session is a change even when empty: the phone reads presence as recording")
        expect(WatchWorkoutMetrics.merged(WatchWorkoutMetrics(), into: holder.metrics) == nil,
               "a payload with no session folds into nothing")
    }
}
