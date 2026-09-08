#if DEBUG
import Foundation
import SwiftData

/// Debug-only history generator. Fills the app with a couple of months of
/// plausible training so the charts, streaks and heatmap can be checked without
/// logging real workouts. Never compiled into a Release build.
enum SampleData {

    /// True when the app was launched with `-GTSeedSampleData`.
    static var isRequestedAtLaunch: Bool {
        ProcessInfo.processInfo.arguments.contains("-GTSeedSampleData")
    }

    static func generate(weeks: Int = 9, context: ModelContext) {
        guard let plan = (try? context.fetch(FetchDescriptor<Plan>()))?.first(where: \.isActive) else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let trainingDays = plan.orderedDays.filter { !$0.isRest }
        guard !trainingDays.isEmpty else { return }

        // Working weight per exercise, nudged up as the weeks pass.
        var loads: [String: Double] = [:]

        for weekOffset in stride(from: weeks - 1, through: 0, by: -1) {
            for (index, day) in trainingDays.enumerated() {
                // Skip the odd session so streaks and gaps look real.
                if Int.random(in: 0..<10) < 2 { continue }

                // Spread the week's sessions backwards from its end. Anchoring
                // them forwards left the current week with a single day, which
                // made every "last 7 days" view look like a deload.
                let spacing = max(1, 7 / trainingDays.count)
                let daysBack = weekOffset * 7 + (trainingDays.count - 1 - index) * spacing
                guard daysBack >= 0,
                      let date = calendar.date(byAdding: .day, value: -daysBack, to: today),
                      date <= today
                else { continue }

                let start = calendar.date(bySettingHour: 18, minute: Int.random(in: 0...45), second: 0, of: date)!
                let session = WorkoutSession(title: day.name, planDayID: day.id,
                                             planName: plan.name, startedAt: start)
                session.endedAt = start.addingTimeInterval(Double.random(in: 2700...4500))
                context.insert(session)

                for (exerciseIndex, item) in day.orderedItems.enumerated() {
                    let base = loads[item.catalogID] ?? startingLoad(for: item)
                    let working = item.tracking == .bodyweightReps ? 0 : base
                    loads[item.catalogID] = base + (Bool.random() ? increment(for: item) : 0)

                    for setIndex in 0..<item.targetSets {
                        let reps = item.tracking == .duration
                            ? 0
                            : max(1, Int.random(in: item.targetRepsLow...max(item.targetRepsLow, item.targetRepsHigh)) - setIndex / 2)
                        let set = SetLog(
                            catalogID: item.catalogID,
                            exerciseName: item.name,
                            exerciseOrder: exerciseIndex,
                            setIndex: setIndex,
                            weightKg: working,
                            reps: reps,
                            seconds: item.tracking == .duration ? item.targetSeconds + Int.random(in: -5...10) : 0,
                            targetRepsLow: item.targetRepsLow,
                            targetRepsHigh: item.targetRepsHigh
                        )
                        set.isCompleted = true
                        set.completedAt = start.addingTimeInterval(Double(exerciseIndex * 480 + setIndex * 130))
                        set.session = session
                        context.insert(set)
                    }
                }
            }
        }

        try? context.save()
    }

    private static func startingLoad(for item: PlanItem) -> Double {
        guard let equipment = item.catalog?.equipment else { return 20 }
        if equipment.contains("Barbell") { return Double.random(in: 40...70) }
        if equipment.contains("Dumbbell") { return Double.random(in: 10...24) }
        if equipment.contains("Machine") || equipment.contains("Cable") { return Double.random(in: 25...50) }
        return 0
    }

    private static func increment(for item: PlanItem) -> Double {
        TrainingStats.weightIncrement(for: item) / 2
    }
}
#endif
