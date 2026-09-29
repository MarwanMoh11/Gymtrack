import Foundation
import SwiftData

/// Run with scripts/test-training-stats-history-records.sh; no simulator is needed.
@main
struct TrainingStatsHistoryRecordTests {
    @MainActor static func main() throws {
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        func finished(_ title: String, at date: Date, sets: [SetLog]) -> WorkoutSession {
            let session = WorkoutSession(title: title, startedAt: date)
            session.endedAt = date.addingTimeInterval(60)
            context.insert(session)
            for set in sets {
                set.isCompleted = true
                set.completedAt = session.endedAt
                set.session = session
                context.insert(set)
            }
            return session
        }

        let earlier = Date(timeIntervalSinceReferenceDate: 700_000_000)
        let later = earlier.addingTimeInterval(86_400)
        let oldID = SetLog(catalogID: "scaption-dumbbell", exerciseName: "Dumbbell Scaption Raise",
                           exerciseOrder: 0, setIndex: 0, weightKg: 12, reps: 10, tracking: .weightReps)
        let survivorID = SetLog(catalogID: "scaption", exerciseName: "Scaption",
                                exerciseOrder: 0, setIndex: 0, weightKg: 12, reps: 8, tracking: .weightReps)
        let oldSession = finished("Old ID", at: earlier, sets: [oldID])
        let newSession = finished("Survivor ID", at: later, sets: [survivorID])
        let merged = [oldSession, newSession]

        let history = TrainingStats.history(for: "scaption", in: merged)
        precondition(history.count == 2 && history.flatMap(\.sets).count == 2,
                     "Both catalog IDs must appear in the survivor's history")
        precondition(TrainingStats.history(for: "scaption-dumbbell", in: merged).count == 2)
        precondition(oldID.catalogID == "scaption-dumbbell", "Historical rows must retain their logged ID")
        precondition(TrainingStats.lastPerformance(of: "scaption", in: [oldSession]).first?.id == oldID.id,
                     "The survivor's progression must find an old-ID session")
        precondition(TrainingStats.lastPerformance(of: "scaption-dumbbell", in: merged).first?.id == survivorID.id,
                     "The old ID must find the latest survivor-ID performance")
        precondition(!TrainingStats.isPersonalRecord(survivorID, among: [oldID, survivorID]),
                     "A weaker survivor-ID set must not reset the record baseline")
        precondition(TrainingStats.recordCandidates(in: merged)["scaption"]?.count == 2)
        precondition(TrainingStats.recordSets(in: newSession, history: merged).isEmpty,
                     "The session summary must compare survivor sets with old-ID records")
        precondition(TrainingStats.records(in: merged).filter { $0.catalogID == "scaption" }.count == 1)

        let timed = SetLog(catalogID: "plank", exerciseName: "Plank",
                           exerciseOrder: 0, setIndex: 0, seconds: 75, tracking: .duration)
        let durationSession = finished("Hold", at: later.addingTimeInterval(86_400), sets: [timed])
        let unloaded = SetLog(catalogID: "push-up", exerciseName: "Push-up",
                               exerciseOrder: 0, setIndex: 0, reps: 15, tracking: .bodyweightReps)
        let bodyweightSession = finished("Bodyweight", at: later.addingTimeInterval(172_800), sets: [unloaded])
        let added = SetLog(catalogID: "pull-up", exerciseName: "Pull-up",
                            exerciseOrder: 0, setIndex: 0, weightKg: 10, reps: 8, tracking: .bodyweightReps)
        let addedSession = finished("Added load", at: later.addingTimeInterval(259_200), sets: [added])
        let unweightedLoad = SetLog(catalogID: "test-unweighted-load", exerciseName: "No load entered",
                                    exerciseOrder: 0, setIndex: 0, reps: 10, tracking: .weightReps)
        let unweightedSession = finished("No load", at: later.addingTimeInterval(345_600), sets: [unweightedLoad])
        let records = TrainingStats.records(in: merged + [durationSession, bodyweightSession,
                                                         addedSession, unweightedSession])

        guard let duration = records.first(where: { $0.catalogID == "plank" }),
              case .duration(seconds: 75) = duration.measure else {
            preconditionFailure("Duration records must use measured seconds")
        }
        // Unloaded reps and added load are separate records since STATS-08: the
        // old single row counted weighted reps as "best reps".
        guard let bodyweight = records.first(where: { $0.catalogID == "push-up" }),
              case .reps(15) = bodyweight.measure else {
            preconditionFailure("Unloaded bodyweight records must use reps without inferred weight")
        }
        precondition(!records.contains { $0.catalogID == "push-up" && $0.measure.kindName == "added" })
        guard let weightedBodyweight = records.first(where: { $0.catalogID == "pull-up" }),
              case .addedLoad(kg: 10, reps: 8) = weightedBodyweight.measure else {
            preconditionFailure("Added bodyweight load is recorded only when explicitly logged")
        }
        precondition(!records.contains { $0.catalogID == "pull-up" && $0.measure.kindName == "reps" },
                     "A weighted set must not stand in as an unloaded rep record")
        guard let noLoad = records.first(where: { $0.catalogID == "test-unweighted-load" }),
              case .reps(10) = noLoad.measure else {
            preconditionFailure("A rep set with no load must not claim a zero-kilogram record")
        }
        precondition(!records.contains { $0.catalogID == "plank" && $0.achievedAt == .distantPast })

        let firstUnloaded = SetLog(catalogID: "pull-up", exerciseName: "Pull-up",
                                   exerciseOrder: 0, setIndex: 0, reps: 12, tracking: .bodyweightReps)
        firstUnloaded.isCompleted = true
        firstUnloaded.completedAt = added.completedAt!.addingTimeInterval(60)
        precondition(!TrainingStats.isPersonalRecord(firstUnloaded, among: [added, firstUnloaded]),
                     "A loaded set cannot serve as an unloaded rep baseline")
        let firstLoaded = SetLog(catalogID: "push-up", exerciseName: "Push-up",
                                 exerciseOrder: 0, setIndex: 0, weightKg: 5, reps: 10, tracking: .bodyweightReps)
        firstLoaded.isCompleted = true
        firstLoaded.completedAt = unloaded.completedAt!.addingTimeInterval(60)
        precondition(!TrainingStats.isPersonalRecord(firstLoaded, among: [unloaded, firstLoaded]),
                     "An unloaded set cannot serve as an added-load baseline")

        print("Merged history, progression and tracking-mode records passed")
    }
}
