import Foundation

/// Which plates go on each end of a barbell for a total load.
///
/// Pure arithmetic on whole hundredths of a unit. 1.25 kg plates and a 135 lb
/// bar converted from kilograms both carry float noise (a stored 61.25 kg reads
/// back as 61.2500000001), and a greedy loop over `Double` would then report an
/// exact load as 0.00000001 short. Hundredths are exact for every plate in
/// either standard set, so the loop never sees the noise.
///
/// Shared rather than app-local because the watch draws the same per-side
/// caption the phone does, and it has no catalog to ask which lifts use a bar.
enum PlateMath {

    // MARK: - What a load needs

    /// What it takes to make a total load with a bar and plates.
    enum Outcome: Equatable, Sendable {
        /// The load is made exactly. `perSide` is heaviest first, in display
        /// units, and empty when the load is the bar alone.
        case exact(perSide: [Double])
        /// No plate combination makes it. `perSide` is the heaviest load below
        /// it that can be made; `short` is how much the total falls under what
        /// was asked, across both ends, in display units.
        case unreachable(perSide: [Double], short: Double)
        /// The load is lighter than the bar. `by` is how much, in display units.
        case belowBar(by: Double)

        /// The plates for one end, or nil when the load is below the bar.
        var perSide: [Double]? {
            switch self {
            case .exact(let plates), .unreachable(let plates, _): plates
            case .belowBar: nil
            }
        }
    }

    /// Plates for one end of the bar, heaviest first.
    ///
    /// - Parameters:
    ///   - total: the whole load, bar included, in display units.
    ///   - bar: the empty bar, in the same units.
    ///   - plates: the sizes available, any order, in the same units. Each can
    ///     be used any number of times, as a gym with a rack of them allows.
    static func outcome(total: Double, bar: Double, plates: [Double]) -> Outcome {
        let totalH = hundredths(total), barH = hundredths(bar)
        guard totalH >= barH else { return .belowBar(by: Double(barH - totalH) / 100) }

        let sizes = Set(plates.map(hundredths).filter { $0 > 0 }).sorted(by: >)
        let sideH = (totalH - barH) / 2
        var remaining = sideH
        var chosen: [Int] = []
        for size in sizes {
            while remaining >= size {
                chosen.append(size)
                remaining -= size
            }
        }
        // An odd hundredth cannot be split across two ends, so it is short too.
        let shortH = remaining * 2 + (totalH - barH) % 2
        let perSide = chosen.map { Double($0) / 100 }
        return shortH == 0
            ? .exact(perSide: perSide)
            : .unreachable(perSide: perSide, short: Double(shortH) / 100)
    }

    /// The same, with the standard plates and the unit's usual bar unless told
    /// otherwise.
    static func outcome(total: Double, unit: WeightUnit, bar: Double? = nil) -> Outcome {
        outcome(total: total, bar: bar ?? standardBar(unit), plates: standardPlates(unit))
    }

    private static func hundredths(_ value: Double) -> Int { Int((value * 100).rounded()) }

    // MARK: - The usual gym

    /// Plates a commercial gym racks, in each unit. Kilograms stop at 1.25 and
    /// pounds at 2.5 because those are the smallest a plate is commonly cast.
    static func standardPlates(_ unit: WeightUnit) -> [Double] {
        unit == .kg ? [25, 20, 15, 10, 5, 2.5, 1.25] : [45, 35, 25, 10, 5, 2.5]
    }

    /// The Olympic bar: 20 kg, or 45 lb where the plates are stamped in pounds.
    static func standardBar(_ unit: WeightUnit) -> Double { unit == .kg ? 20 : 45 }

    /// "20 + 10 + 2.5" for one end, or "bar only" when no plate is needed.
    static func caption(_ perSide: [Double], separator: String = " + ") -> String {
        perSide.isEmpty ? "Bar only" : perSide.map(label).joined(separator: separator)
    }

    /// A plate as stamped: 25, 2.5, 1.25.
    static func label(_ plate: Double) -> String {
        let rounded = (plate * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(format: "%.0f", rounded) }
        if (rounded * 10).rounded() / 10 == rounded { return String(format: "%.1f", rounded) }
        return String(format: "%.2f", rounded)
    }

    // MARK: - Which lifts use a bar

    /// Catalog equipment says "Barbell" for every lift done on any long bar, so
    /// the tag alone would put a 20 kg bar under a lift that does not use one.
    /// These are the ones tagged Barbell that are not a plain bar loaded on both
    /// ends: an EZ curl bar and a trap or safety bar weigh something else
    /// (and vary by gym), and a landmine, T-bar or single-arm row loads one end
    /// only. The app cannot know their bar weight, and a wrong "per side" line
    /// is worse than none.
    static let notAPlainBar: Set<String> = [
        "landmine-press", "landmine-press-shoulder", "landmine-squat", "landmine-row",
        "t-bar-row", "meadows-row", "single-arm-barbell-row", "single-arm-barbell-curl",
        "preacher-curl-ez", "skullcrusher-ez", "ez-bar-pullover",
        "overhead-tricep-extension-ez-bar", "ez-bar-wrist-curl", "ez-bar-reverse-wrist-curl",
        "trap-bar-deadlift", "safety-bar-squat",
    ]

    /// Whether an exercise is loaded with plates on a standard bar. "Plate"
    /// equipment (a plate held or strapped on) is deliberately not included: no
    /// bar is involved. Dumbbells, machines, cables and bodyweight never are.
    static func usesPlainBar(catalogID: String, equipment: [String]) -> Bool {
        equipment.contains("Barbell") && !notAPlainBar.contains(catalogID)
    }
}

/// How heavy the lifter's bar is. A preset rather than a free number: the
/// Olympic bar is nearly everyone's, a lighter one covers the others, and a
/// preset reads correctly in either unit without a conversion that would put
/// 20 kg at 44.09 lb.
enum BarWeight: String, CaseIterable, Identifiable, Sendable {
    case standard, light, lightest

    var id: String { rawValue }

    /// The bar in the unit the exercise is marked in.
    func weight(in unit: WeightUnit) -> Double {
        switch (self, unit) {
        case (.standard, .kg): 20
        case (.standard, .lb): 45
        case (.light, .kg): 15
        case (.light, .lb): 35
        case (.lightest, .kg): 10
        case (.lightest, .lb): 25
        }
    }

    /// "20 kg / 45 lb", both units, since the setting is one choice for both.
    var label: String {
        "\(PlateMath.label(weight(in: .kg))) kg / \(PlateMath.label(weight(in: .lb))) lb"
    }
}
