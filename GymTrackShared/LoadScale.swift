import Foundation

/// How one piece of equipment is marked, and the ladder of weights it can
/// actually be set to.
///
/// A gym is not uniform. The barbell takes 1.25 kg plates a side, the leg press
/// stack is stamped in pounds and pins in 15 lb steps, and the dumbbell rack
/// jumps 2 kg at a time. One global unit with one global step made every one of
/// those a small lie: the app would happily offer 62.5 kg on a machine whose
/// stack only does 60 or 65, and print kilograms on a plate marked 45.
///
/// A scale is a unit and an increment, nothing more. Weight is still *stored*
/// in kilograms everywhere — history, volume, personal records and Health stay
/// comparable no matter what each machine is marked in — so a scale only
/// governs how a single exercise's load is read and entered.
///
/// Shared rather than app-local because the watch has to draw and turn the same
/// ladder, and it has no access to the phone's catalog or settings beyond what
/// arrives in a mirror.
struct LoadScale: Codable, Hashable, Sendable {

    /// What the equipment is marked in.
    var unit: WeightUnit
    /// The smallest jump the equipment allows, expressed in `unit`.
    var increment: Double

    init(unit: WeightUnit, increment: Double) {
        self.unit = unit
        // A zero or negative step would freeze every stepper on the screen.
        self.increment = increment > 0 ? increment : unit.step
    }

    /// The scale for equipment with nothing special about it.
    static func standard(_ unit: WeightUnit) -> LoadScale {
        LoadScale(unit: unit, increment: unit.step)
    }

    static let kilograms = LoadScale.standard(.kg)

    // MARK: - Conversion

    /// A stored kilogram value as the equipment reads it.
    func display(_ kg: Double) -> Double { unit.fromKg(kg) }

    /// A value read off the equipment, back in storage units.
    func kilograms(_ display: Double) -> Double { unit.toKg(display) }

    // MARK: - The ladder

    /// The nearest rung to a value in display units.
    func snap(display value: Double) -> Double {
        max(0, (value / increment).rounded() * increment)
    }

    /// The nearest achievable weight, in kilograms. Used wherever the app
    /// proposes a load of its own — a progression suggestion that lands between
    /// two pins is worse than useless mid-set.
    func snap(kg: Double) -> Double {
        guard kg > 0 else { return 0 }
        return kilograms(snap(display: display(kg)))
    }

    /// One rung up or down, whether or not the weight started on one.
    ///
    /// A number typed by hand stays exactly where it was typed — that's the
    /// escape hatch for the machine nobody could have predicted — but the first
    /// tap of a stepper pulls it back onto the ladder rather than carrying the
    /// offset forward forever.
    func step(display value: Double, by direction: Int) -> Double {
        guard direction != 0 else { return value }
        let rungs = value / increment
        // A hair of tolerance, or a rounding error left over from a conversion
        // costs a whole rung.
        let epsilon = 0.001
        let next = direction > 0
            ? (rungs + epsilon).rounded(.down) + 1
            : (rungs - epsilon).rounded(.up) - 1
        return max(0, next * increment)
    }

    /// One rung up or down, in kilograms.
    func step(kg: Double, by direction: Int) -> Double {
        kilograms(step(display: display(kg), by: direction))
    }

    /// The increment as a weight in kilograms — what a progression adds.
    var incrementKg: Double { kilograms(increment) }

    /// A window of rungs around a weight, for showing what the ladder looks
    /// like. Slides rather than shrinks near zero, so the preview is always the
    /// same width.
    func ladder(around kg: Double, rungs: Int = 2) -> [Double] {
        let centre = snap(display: display(kg))
        let start = max(0, centre - Double(rungs) * increment)
        return (0..<(rungs * 2 + 1)).map { start + Double($0) * increment }
    }

    /// The most anyone will load, in display units — the ceiling on a stepper
    /// or the Digital Crown.
    var displayCeiling: Double { unit == .kg ? 500 : 1_100 }

    // MARK: - Formatting

    /// How many decimals this ladder can land on. A stack that moves in fives
    /// never needs one; 1.25 kg microplates need two.
    var decimals: Int {
        if abs(increment.rounded() - increment) < 0.001 { return 0 }
        if abs((increment * 10).rounded() / 10 - increment) < 0.001 { return 1 }
        return 2
    }

    /// A display-unit number as this equipment would read it.
    ///
    /// Rounded to what the ladder can express, which is what keeps a converted
    /// weight honest rather than noisy: 60 kg on a machine marked in pounds is
    /// "132.3", not "132.28".
    func text(_ value: Double) -> String {
        let factor = pow(10.0, Double(decimals))
        let rounded = (value * factor).rounded() / factor
        if abs(rounded.rounded() - rounded) < 0.0001 { return String(format: "%.0f", rounded) }
        if decimals >= 2, abs((rounded * 10).rounded() / 10 - rounded) >= 0.0001 {
            return String(format: "%.2f", rounded)
        }
        return String(format: "%.1f", rounded)
    }

    /// "60 kg" / "135 lb" from a stored kilogram value.
    func format(_ kg: Double, showUnit: Bool = true) -> String {
        let number = text(display(kg))
        return showUnit ? "\(number) \(unit.short)" : number
    }

    /// "2.5 kg" / "5 lb" — the jump itself.
    var incrementLabel: String { "\(text(increment)) \(unit.short)" }

    /// "kg · 2.5" — the caption under a weight field, which has to say both
    /// what you're typing and what a tap of + is worth.
    var shortLabel: String { "\(unit.short) · \(text(increment))" }

    /// A number at the precision it deserves: whole where it's whole, one place
    /// where a half-step needs it, two only for the finest microplates.
    static func trim(_ value: Double) -> String {
        for places in 0...2 {
            let rounded = (value * pow(10, Double(places))).rounded() / pow(10, Double(places))
            if abs(rounded - value) < 0.005 { return String(format: "%.\(places)f", value) }
        }
        return String(format: "%.2f", value)
    }

    // MARK: - The increments worth offering

    /// Jumps a real gym actually has, for the unit in question. Anything else
    /// is still reachable by typing the weight.
    static func choices(for unit: WeightUnit) -> [Double] {
        unit == .kg
            ? [0.5, 1, 1.25, 2, 2.5, 5, 10]
            : [1, 2.5, 5, 10, 15, 20, 25]
    }

    /// The same scale expressed in the other unit, used when someone flips a
    /// machine's unit and expects the step to stay roughly the jump it was.
    func converted(to newUnit: WeightUnit) -> LoadScale {
        guard newUnit != unit else { return self }
        let equivalent = newUnit.fromKg(kilograms(increment))
        let nearest = Self.choices(for: newUnit)
            .min { abs($0 - equivalent) < abs($1 - equivalent) } ?? newUnit.step
        return LoadScale(unit: newUnit, increment: nearest)
    }
}
