import Foundation
import SwiftData

/// Run with scripts/test-pound-load.sh; no simulator is needed.
///
/// XC-08: weights are stored in kilograms, and the unit only decides which
/// ladder the equipment is read off. Until now every one of these checks ran
/// in kilograms, where a conversion that is skipped or applied twice comes out
/// the same. In pounds the suggestion has to land on a rung the machine
/// really has, and a weight converted back from a rung must not lose a step to
/// float noise.
@main
struct PoundLoadTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        print("FAIL: \(message)")
    }

    static let poundsPerKilo = 2.20462262

    static func near(_ lhs: Double, _ rhs: Double) -> Bool { abs(lhs - rhs) < 0.001 }

    /// Whether a stored weight reads as a whole number of rungs on `increment`.
    static func onRung(_ kg: Double, in unit: WeightUnit, step increment: Double) -> Bool {
        let rungs = unit.fromKg(kg) / increment
        return abs(rungs - rungs.rounded()) < 0.001
    }

    @MainActor static func main() throws {
        defer { AppSettings.shared.weightUnit = .kg }
        let container = try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        for unit in [WeightUnit.kg, .lb] {
            AppSettings.shared.weightUnit = unit
            progression(unit, context)
            opening(unit, context)
            ladders(unit)
            snapping(unit)
            formatting(unit, context)
        }
        fflush(stdout)
        guard failures == 0 else { preconditionFailure("\(failures) pound check(s) failed") }
        print("Pound load tests passed")
    }

    // MARK: - Progression

    static func sets(_ work: [(Double, Int)], feel: SetFeel? = nil) -> [SetLog] {
        work.enumerated().map { index, pair in
            let set = SetLog(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press",
                             exerciseOrder: 0, setIndex: index, weightKg: pair.0, reps: pair.1,
                             targetRepsLow: 8, targetRepsHigh: 12, tracking: .weightReps)
            set.isCompleted = true
            set.rpe = feel.map { Double($0.rawValue) }
            return set
        }
    }

    /// The double progression on a barbell, whose rung is 2.5 kg or 5 lb.
    /// 60 kg is 132.3 lb, between two pound rungs, so a climb must land on
    /// 135 lb rather than on 132.3 plus a pound-sized step.
    @MainActor static func progression(_ unit: WeightUnit, _ context: ModelContext) {
        let tag = "(\(unit.rawValue))"
        let item = PlanItem(catalogID: "barbell-bench-press", name: "Bench Press", order: 0,
                            targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)
        context.insert(item)

        let climb = TrainingStats.suggestion(for: item, lastSets: sets([(60, 12), (60, 12), (60, 12)]))
        let climbed = unit == .kg ? 62.5 : 135 / poundsPerKilo
        check(climb.action == .increaseWeight, "A cleared session climbs \(tag), got \(climb.action)")
        check(near(climb.weightKg, climbed),
              "Climbing from 60 kg must land on the next \(unit.rawValue) rung, \(climbed) kg \(tag), got \(climb.weightKg)")
        check(onRung(climb.weightKg, in: unit, step: unit == .kg ? 2.5 : 5),
              "The climb must be a rung the barbell has \(tag), got \(unit.fromKg(climb.weightKg)) \(unit.rawValue)")

        // The load a session is prescribed from is pulled onto the ladder first,
        // so a load that is already a rung comes back exactly, and one that is
        // not (60 kg is 132.3 lb) lands on the nearest rung the unit has.
        let onLadder = unit == .kg ? 60.0 : 135 / poundsPerKilo
        let held = TrainingStats.suggestion(for: item, lastSets: sets([(onLadder, 12)]))
        check(held.action == .repeatLoad && near(held.weightKg, onLadder) && held.reps == 8,
              "A partial session holds a rung exactly \(tag), got \(held.weightKg)")
        let offLadder = unit == .kg ? 61.0 : 60.0
        let snapped = TrainingStats.suggestion(for: item, lastSets: sets([(offLadder, 12)]))
        let nearest = unit == .kg ? 60.0 : 130 / poundsPerKilo
        check(snapped.action == .repeatLoad && near(snapped.weightKg, nearest),
              "A load between rungs is held at the nearest one \(tag), expected \(nearest) kg, got \(snapped.weightKg)")

        let deload = TrainingStats.suggestion(for: item, lastSets: sets([(onLadder, 4), (onLadder, 4), (onLadder, 4)], feel: .hard))
        let lowered = unit == .kg ? 57.5 : 130 / poundsPerKilo
        check(deload.action == .deload && near(deload.weightKg, lowered),
              "A deload takes one rung off \(tag), expected \(lowered) kg, got \(deload.weightKg)")
        let offDeload = TrainingStats.suggestion(for: item, lastSets: sets([(60, 4), (60, 4), (60, 4)], feel: .hard))
        check(offDeload.weightKg < 60 && onRung(offDeload.weightKg, in: unit, step: unit == .kg ? 2.5 : 5),
              "A deload from 60 kg still lands on a rung \(tag), got \(unit.fromKg(offDeload.weightKg)) \(unit.rawValue)")

        // A load that is already a rung climbs to the next one, not two: 135 lb
        // stored in kilograms reads 135.0000001 lb back.
        let next = TrainingStats.suggestion(for: item, lastSets: sets([(onLadder, 12), (onLadder, 12), (onLadder, 12)]))
        let after = unit == .kg ? 62.5 : 140 / poundsPerKilo
        check(near(next.weightKg, after),
              "A load on a rung climbs exactly one rung \(tag), expected \(after) kg, got \(next.weightKg)")
    }

    /// What the logger opens at after a cleared session, which reads the same
    /// suggestion through the session factory.
    @MainActor static func opening(_ unit: WeightUnit, _ context: ModelContext) {
        let plan = Plan(name: "Pounds")
        let day = PlanDay(name: "Day", order: 0)
        day.plan = plan
        let item = PlanItem(catalogID: "barbell-bench-press", name: "Bench Press", order: 0,
                            targetSets: 3, targetRepsLow: 8, targetRepsHigh: 12)
        item.day = day
        let past = WorkoutSession(title: "Last", startedAt: .now.addingTimeInterval(-86_400))
        past.endedAt = past.startedAt.addingTimeInterval(3_600)
        context.insert(plan)
        context.insert(day)
        context.insert(item)
        context.insert(past)
        for set in sets([(60, 12), (60, 12), (60, 12)]) {
            set.session = past
            context.insert(set)
        }
        let opened = SessionFactory.build(day: day, plan: plan, context: context, history: [past])
            .exerciseGroups[0].sets
        let expected = unit == .kg ? 62.5 : 135 / poundsPerKilo
        check(opened.count == 3 && opened.allSatisfy { near($0.weightKg, expected) },
              "The logger opens on the next rung (\(unit.rawValue)), expected \(expected) kg, got \(opened.map(\.weightKg))")
    }

    // MARK: - Ladders

    /// The rung an exercise defaults to, through the app-wide unit. Pound gyms
    /// have their own ladder rather than a conversion of the metric one.
    @MainActor static func ladders(_ unit: WeightUnit) {
        let expected: [String: (kg: Double, lb: Double)] = [
            "barbell-bench-press": (2.5, 5),
            "leg-press": (5, 10),
            "cable-crossover": (2.5, 5),
            "dumbbell-lateral-raise": (2, 5),
        ]
        for (id, rung) in expected {
            let scale = LoadScaleBook.shared.scale(for: id)
            check(scale.unit == unit, "\(id) is marked in the phone's unit, got \(scale.unit)")
            check(scale.increment == (unit == .kg ? rung.kg : rung.lb),
                  "\(id) steps \(unit == .kg ? rung.kg : rung.lb) \(unit.rawValue), got \(scale.increment)")
        }
        // The default must not be one unit's number under the other's label.
        let standard = LoadScale.standard(unit)
        check(standard.increment == (unit == .kg ? 2.5 : 5), "The standard rung in \(unit.rawValue), got \(standard.increment)")
    }

    // MARK: - Snapping and stepping

    @MainActor static func snapping(_ unit: WeightUnit) {
        let tag = "(\(unit.rawValue))"
        let scale = LoadScale(unit: unit, increment: unit == .kg ? 2.5 : 5)
        func kg(_ display: Double) -> Double { display / (unit == .kg ? 1 : poundsPerKilo) }

        // 60 kg is 132.28 lb: nearest 5 lb rung is 130; nearest 2.5 kg rung is 60 itself.
        check(near(scale.snap(kg: 60), unit == .kg ? 60 : kg(130)),
              "60 kg snaps to its nearest rung \(tag), got \(scale.snap(kg: 60))")
        // 61.5 kg is 135.58 lb: rounds down to 135, while in kilograms it rounds to 62.5.
        check(near(scale.snap(kg: 61.5), unit == .kg ? 62.5 : kg(135)),
              "61.5 kg snaps to its nearest rung \(tag), got \(scale.snap(kg: 61.5))")
        check(scale.snap(kg: 0) == 0 && scale.snap(kg: -3) == 0, "Nothing snaps below zero \(tag)")

        // A rung stored in kilograms reads back a hair off, and must not cost a rung.
        let start = unit == .kg ? 60.0 : 135.0
        let stored = kg(start)
        check(near(scale.display(scale.step(kg: stored, by: 1)), start + scale.increment),
              "One tap up from \(start) climbs one rung \(tag)")
        check(near(scale.display(scale.step(kg: stored, by: -1)), start - scale.increment),
              "One tap down from \(start) drops one rung \(tag)")
        // Off the ladder, the first tap pulls back onto it.
        let off = unit == .kg ? 61.0 : 132.0
        check(near(scale.display(scale.step(kg: kg(off), by: 1)), unit == .kg ? 62.5 : 135),
              "The first tap up from \(off) lands on the ladder \(tag)")
        check(near(scale.display(scale.step(kg: kg(off), by: -1)), unit == .kg ? 60 : 130),
              "The first tap down from \(off) lands on the ladder \(tag)")
        check(scale.step(kg: 0, by: -1) == 0, "The ladder stops at zero \(tag)")

        let window = scale.ladder(around: stored)
        let expected = (-2...2).map { start + Double($0) * scale.increment }
        check(zip(window, expected).allSatisfy { near($0, $1) } && window.count == 5,
              "The ladder around \(start) is five rungs in display units \(tag), got \(window)")
        check(scale.displayCeiling == (unit == .kg ? 1_000 : 2_200),
              "The ceiling follows the unit \(tag), got \(scale.displayCeiling)")
    }

    // MARK: - Formatting

    @MainActor static func formatting(_ unit: WeightUnit, _ context: ModelContext) {
        let tag = "(\(unit.rawValue))"
        let coarse = LoadScale(unit: unit, increment: unit == .kg ? 2.5 : 5)
        let fine = LoadScale(unit: unit, increment: unit == .kg ? 1.25 : 2.5)
        let sixty = 60.0
        let rung = unit == .kg ? 62.5 : 135 / poundsPerKilo

        // A rung is shown as the number the equipment carries, with no noise.
        check(coarse.format(rung) == (unit == .kg ? "62.5 kg" : "135 lb"),
              "A rung reads as marked \(tag), got \(coarse.format(rung))")
        check(coarse.format(rung, showUnit: false) == (unit == .kg ? "62.5" : "135"),
              "The bare number drops the unit \(tag), got \(coarse.format(rung, showUnit: false))")
        // An off-ladder weight is rounded to what the ladder can express.
        check(coarse.format(sixty) == (unit == .kg ? "60 kg" : "132 lb"),
              "60 kg on the coarse ladder \(tag), got \(coarse.format(sixty))")
        check(fine.format(sixty) == (unit == .kg ? "60 kg" : "132.3 lb"),
              "60 kg on the fine ladder \(tag), got \(fine.format(sixty))")
        check(fine.format(61.25) == (unit == .kg ? "61.25 kg" : "135 lb"),
              "The fine ladder shows its own step \(tag), got \(fine.format(61.25))")

        check(coarse.incrementLabel == (unit == .kg ? "2.5 kg" : "5 lb"), "Jump label \(tag), got \(coarse.incrementLabel)")
        check(fine.incrementLabel == (unit == .kg ? "1.25 kg" : "2.5 lb"), "Fine jump label \(tag), got \(fine.incrementLabel)")
        check(coarse.shortLabel == (unit == .kg ? "kg · 2.5" : "lb · 5"), "Short label \(tag), got \(coarse.shortLabel)")

        // A set reads itself off its own exercise's ladder in the phone's unit.
        let bench = SetLog(catalogID: "barbell-bench-press", exerciseName: "Barbell Bench Press",
                           exerciseOrder: 0, setIndex: 0, weightKg: rung, reps: 8)
        check(bench.weightLabel == (unit == .kg ? "62.5 kg" : "135 lb"), "A set's label \(tag), got \(bench.weightLabel)")
        let stack = SetLog(catalogID: "leg-press", exerciseName: "Leg Press",
                           exerciseOrder: 1, setIndex: 0, weightKg: 100, reps: 10)
        check(stack.weightLabel == (unit == .kg ? "100 kg" : "220 lb"), "A stack's label \(tag), got \(stack.weightLabel)")

        // The unit's own formatter is the one the settings screens use.
        check(unit.format(60) == (unit == .kg ? "60 kg" : "132.3 lb"), "The unit formats 60 kg \(tag), got \(unit.format(60))")
        check(unit.snap(unit == .kg ? 60.3 : 132.6) == (unit == .kg ? 60.5 : 133),
              "The unit's own snap rounds to its step \(tag)")
    }
}
