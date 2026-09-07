import Foundation
import SwiftData

/// Starter routines the user can adopt at onboarding or add later. These are
/// plain values; `materialise(in:)` turns one into live SwiftData objects.
struct PlanTemplate: Identifiable {
    struct Item {
        let catalogID: String
        let sets: Int
        let repsLow: Int
        let repsHigh: Int
        let restSeconds: Int
        let seconds: Int

        init(_ catalogID: String, _ sets: Int, _ repsLow: Int, _ repsHigh: Int, rest: Int = 90, seconds: Int = 45) {
            self.catalogID = catalogID
            self.sets = sets
            self.repsLow = repsLow
            self.repsHigh = repsHigh
            self.restSeconds = rest
            self.seconds = seconds
        }
    }

    struct Day {
        let name: String
        let weekday: Int?      // 1 = Sunday
        let items: [Item]
        var isRest: Bool { items.isEmpty }
    }

    let id: String
    let name: String
    let summary: String
    let daysPerWeek: Int
    let level: String
    let symbol: String
    let days: [Day]

    /// Creates the plan (and everything under it) in the given context.
    @discardableResult
    func materialise(in context: ModelContext, makeActive: Bool) -> Plan {
        let plan = Plan(name: name, summary: summary, isActive: makeActive)
        context.insert(plan)

        for (dayIndex, day) in days.enumerated() {
            let planDay = PlanDay(name: day.name, order: dayIndex, weekday: day.weekday, isRest: day.isRest)
            planDay.plan = plan
            context.insert(planDay)

            for (itemIndex, item) in day.items.enumerated() {
                guard let catalog = ExerciseCatalog.shared.exercise(id: item.catalogID) else {
                    assertionFailure("Template references unknown exercise \(item.catalogID)")
                    continue
                }
                let planItem = PlanItem(
                    catalogID: catalog.id,
                    name: catalog.name,
                    order: itemIndex,
                    targetSets: item.sets,
                    targetRepsLow: item.repsLow,
                    targetRepsHigh: item.repsHigh,
                    targetWeightKg: 0,
                    targetSeconds: item.seconds,
                    restSeconds: item.restSeconds
                )
                planItem.day = planDay
                context.insert(planItem)
            }
        }
        return plan
    }

    // MARK: - Built-in templates

    static let all: [PlanTemplate] = [pplUpperLower, pushPullLegs, upperLower, fullBody, minimalist]

    /// Push / Pull / Legs / Upper / Lower — the five-day hybrid. Each muscle
    /// gets a heavy dedicated day early in the week and a second, lighter
    /// exposure on the upper/lower days.
    static let pplUpperLower = PlanTemplate(
        id: "ppl-upper-lower",
        name: "PPL + Upper / Lower",
        summary: "Five days: Push, Pull and Legs early in the week, then an Upper and a Lower day. Everything trained roughly twice.",
        daysPerWeek: 5,
        level: "Intermediate",
        symbol: "square.stack.3d.up.fill",
        days: [
            Day(name: "Push", weekday: 2, items: [
                Item("barbell-bench-press", 4, 5, 8, rest: 150),
                Item("overhead-press", 3, 6, 10, rest: 120),
                Item("incline-dumbbell-press", 3, 8, 12),
                Item("dumbbell-lateral-raise", 3, 12, 20, rest: 60),
                Item("tricep-pushdown-rope", 3, 10, 15, rest: 60),
                Item("overhead-tricep-extension-dumbbell", 2, 12, 15, rest: 60),
            ]),
            Day(name: "Pull", weekday: 3, items: [
                Item("deadlift", 3, 3, 5, rest: 180),
                Item("pull-up", 3, 5, 10, rest: 120),
                Item("barbell-row", 3, 8, 12, rest: 120),
                Item("face-pull", 3, 15, 20, rest: 60),
                Item("barbell-curl", 3, 8, 12, rest: 60),
                Item("hammer-curl", 2, 10, 15, rest: 60),
            ]),
            Day(name: "Legs", weekday: 4, items: [
                Item("barbell-back-squat", 4, 5, 8, rest: 180),
                Item("romanian-deadlift-barbell", 3, 8, 12, rest: 120),
                Item("leg-press", 3, 10, 15, rest: 120),
                Item("lying-leg-curl-machine", 3, 10, 15, rest: 60),
                Item("standing-calf-raise-machine", 4, 12, 20, rest: 60),
                Item("hanging-leg-raise", 3, 10, 15, rest: 60),
            ]),
            Day(name: "Upper", weekday: 6, items: [
                Item("incline-barbell-press", 4, 6, 10, rest: 150),
                Item("lat-pulldown-wide", 4, 8, 12, rest: 120),
                Item("dumbbell-shoulder-press", 3, 8, 12),
                Item("seated-cable-row", 3, 10, 12),
                Item("incline-dumbbell-curl", 3, 10, 15, rest: 60),
                Item("skullcrusher-ez", 3, 8, 12, rest: 60),
            ]),
            Day(name: "Lower", weekday: 7, items: [
                Item("barbell-front-squat", 4, 6, 10, rest: 150),
                Item("hip-thrust-barbell", 3, 8, 12, rest: 120),
                Item("bulgarian-split-squat-dumbbell", 3, 8, 12, rest: 90),
                Item("seated-leg-curl-machine", 3, 12, 15, rest: 60),
                Item("seated-calf-raise-machine", 4, 15, 20, rest: 45),
                Item("cable-crunch", 3, 12, 20, rest: 60),
            ]),
        ]
    )

    static let pushPullLegs = PlanTemplate(
        id: "ppl",
        name: "Push / Pull / Legs",
        summary: "Six sessions a week, each muscle trained twice. The highest-volume option.",
        daysPerWeek: 6,
        level: "Intermediate",
        symbol: "flame.fill",
        days: [
            Day(name: "Push A", weekday: 2, items: [
                Item("barbell-bench-press", 4, 5, 8, rest: 150),
                Item("overhead-press", 3, 6, 10, rest: 120),
                Item("incline-dumbbell-press", 3, 8, 12),
                Item("dumbbell-lateral-raise", 3, 12, 20, rest: 60),
                Item("tricep-pushdown-rope", 3, 10, 15, rest: 60),
                Item("overhead-tricep-extension-dumbbell", 3, 10, 15, rest: 60),
            ]),
            Day(name: "Pull A", weekday: 3, items: [
                Item("deadlift", 3, 3, 5, rest: 180),
                Item("pull-up", 3, 5, 10, rest: 120),
                Item("barbell-row", 3, 8, 12, rest: 120),
                Item("face-pull", 3, 15, 20, rest: 60),
                Item("barbell-curl", 3, 8, 12, rest: 60),
                Item("hammer-curl", 3, 10, 15, rest: 60),
            ]),
            Day(name: "Legs A", weekday: 4, items: [
                Item("barbell-back-squat", 4, 5, 8, rest: 180),
                Item("romanian-deadlift-barbell", 3, 8, 12, rest: 120),
                Item("leg-press", 3, 10, 15, rest: 120),
                Item("lying-leg-curl-machine", 3, 10, 15, rest: 60),
                Item("standing-calf-raise-machine", 4, 12, 20, rest: 60),
                Item("hanging-leg-raise", 3, 10, 15, rest: 60),
            ]),
            Day(name: "Push B", weekday: 5, items: [
                Item("incline-barbell-press", 4, 6, 10, rest: 150),
                Item("dumbbell-shoulder-press", 3, 8, 12, rest: 120),
                Item("chest-dip", 3, 8, 12),
                Item("cable-lateral-raise", 3, 12, 20, rest: 60),
                Item("skullcrusher-ez", 3, 8, 12, rest: 60),
                Item("chest-fly-machine", 3, 12, 15, rest: 60),
            ]),
            Day(name: "Pull B", weekday: 6, items: [
                Item("lat-pulldown-wide", 4, 8, 12, rest: 120),
                Item("seated-cable-row", 3, 8, 12, rest: 120),
                Item("chest-supported-dumbbell-row", 3, 10, 15),
                Item("rear-delt-fly-dumbbell", 3, 15, 20, rest: 60),
                Item("incline-dumbbell-curl", 3, 10, 15, rest: 60),
                Item("cable-curl-rope", 3, 12, 15, rest: 60),
            ]),
            Day(name: "Legs B", weekday: 7, items: [
                Item("barbell-front-squat", 4, 6, 10, rest: 150),
                Item("hip-thrust-barbell", 3, 8, 12, rest: 120),
                Item("bulgarian-split-squat-dumbbell", 3, 8, 12, rest: 90),
                Item("seated-leg-curl-machine", 3, 12, 15, rest: 60),
                Item("seated-calf-raise-machine", 4, 15, 20, rest: 45),
                Item("cable-crunch", 3, 12, 20, rest: 60),
            ]),
        ]
    )

    static let upperLower = PlanTemplate(
        id: "upper-lower",
        name: "Upper / Lower",
        summary: "Four days a week. The best balance of frequency and recovery for most people.",
        daysPerWeek: 4,
        level: "Beginner–Intermediate",
        symbol: "square.split.1x2.fill",
        days: [
            Day(name: "Upper A", weekday: 2, items: [
                Item("barbell-bench-press", 4, 5, 8, rest: 150),
                Item("barbell-row", 4, 6, 10, rest: 120),
                Item("dumbbell-shoulder-press", 3, 8, 12),
                Item("lat-pulldown-wide", 3, 10, 12),
                Item("barbell-curl", 3, 8, 12, rest: 60),
                Item("tricep-pushdown-rope", 3, 10, 15, rest: 60),
            ]),
            Day(name: "Lower A", weekday: 3, items: [
                Item("barbell-back-squat", 4, 5, 8, rest: 180),
                Item("romanian-deadlift-barbell", 3, 8, 12, rest: 120),
                Item("leg-press", 3, 10, 15),
                Item("lying-leg-curl-machine", 3, 10, 15, rest: 60),
                Item("standing-calf-raise-machine", 4, 12, 20, rest: 45),
                Item("plank-bodyweight", 3, 0, 0, rest: 60, seconds: 45),
            ]),
            Day(name: "Upper B", weekday: 5, items: [
                Item("overhead-press", 4, 5, 8, rest: 150),
                Item("pull-up", 4, 5, 10, rest: 120),
                Item("incline-dumbbell-press", 3, 8, 12),
                Item("seated-cable-row", 3, 10, 12),
                Item("dumbbell-lateral-raise", 3, 12, 20, rest: 60),
                Item("hammer-curl", 3, 10, 15, rest: 60),
            ]),
            Day(name: "Lower B", weekday: 6, items: [
                Item("deadlift", 3, 3, 5, rest: 180),
                Item("bulgarian-split-squat-dumbbell", 3, 8, 12, rest: 90),
                Item("hip-thrust-barbell", 3, 10, 15),
                Item("leg-extension-machine", 3, 12, 15, rest: 60),
                Item("seated-calf-raise-machine", 4, 15, 20, rest: 45),
                Item("hanging-leg-raise", 3, 10, 15, rest: 60),
            ]),
        ]
    )

    static let fullBody = PlanTemplate(
        id: "full-body",
        name: "Full Body 3×",
        summary: "Three sessions covering everything. Ideal if you're starting out or short on days.",
        daysPerWeek: 3,
        level: "Beginner",
        symbol: "figure.strengthtraining.traditional",
        days: [
            Day(name: "Full Body A", weekday: 2, items: [
                Item("barbell-back-squat", 3, 5, 8, rest: 150),
                Item("barbell-bench-press", 3, 5, 8, rest: 150),
                Item("barbell-row", 3, 8, 12, rest: 120),
                Item("dumbbell-lateral-raise", 2, 12, 20, rest: 60),
                Item("plank-bodyweight", 3, 0, 0, rest: 60, seconds: 45),
            ]),
            Day(name: "Full Body B", weekday: 4, items: [
                Item("deadlift", 3, 3, 5, rest: 180),
                Item("overhead-press", 3, 6, 10, rest: 120),
                Item("lat-pulldown-wide", 3, 8, 12),
                Item("leg-press", 3, 10, 15),
                Item("barbell-curl", 2, 10, 15, rest: 60),
            ]),
            Day(name: "Full Body C", weekday: 6, items: [
                Item("barbell-front-squat", 3, 6, 10, rest: 150),
                Item("incline-dumbbell-press", 3, 8, 12),
                Item("seated-cable-row", 3, 10, 12),
                Item("lying-leg-curl-machine", 3, 10, 15, rest: 60),
                Item("tricep-pushdown-rope", 2, 12, 15, rest: 60),
            ]),
        ]
    )

    static let minimalist = PlanTemplate(
        id: "minimalist",
        name: "Minimalist Strength",
        summary: "Two days, five big lifts. Everything that matters, nothing that doesn't.",
        daysPerWeek: 2,
        level: "Any",
        symbol: "bolt.fill",
        days: [
            Day(name: "Day A", weekday: 2, items: [
                Item("barbell-back-squat", 5, 5, 5, rest: 180),
                Item("barbell-bench-press", 5, 5, 5, rest: 180),
                Item("barbell-row", 5, 5, 5, rest: 150),
            ]),
            Day(name: "Day B", weekday: 5, items: [
                Item("deadlift", 3, 5, 5, rest: 210),
                Item("overhead-press", 5, 5, 5, rest: 180),
                Item("pull-up", 3, 5, 10, rest: 150),
            ]),
        ]
    )
}
