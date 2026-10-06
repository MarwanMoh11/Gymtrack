import Foundation

/// Lengths follow the app's unit setting the way weights do: kilograms show as
/// centimetres, pounds as inches. There is no separate length setting because
/// a lifter who thinks in pounds thinks in inches, and a second switch would
/// be one more thing to set. Storage is centimetres either way.
extension WeightUnit {
    var lengthShort: String { self == .kg ? "cm" : "in" }
    func lengthFromCm(_ cm: Double) -> Double { self == .kg ? cm : cm / 2.54 }
    func lengthToCm(_ value: Double) -> Double { self == .kg ? value : value * 2.54 }
}

/// What typing into one measurement field amounts to.
enum MeasurementEntry: Equatable {
    /// Nothing typed. Stores nothing, and never blocks a save.
    case blank
    /// A usable length, already in centimetres.
    case cm(Double)
    /// Typed, but not a length a tape could give. Held back from saving
    /// rather than dropped, so a slip is seen instead of quietly lost.
    case invalid

    /// `text` is read in the display unit and comes back in centimetres,
    /// rounded to a tenth. A tape isn't read finer than that, and the rounding
    /// keeps 14.5 in from being stored as 36.830000000000005 cm and exported
    /// to the coach as a precision nobody measured.
    static func parse(_ text: String, unit: WeightUnit) -> MeasurementEntry {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return .blank }
        guard let typed = Double(trimmed.replacingOccurrences(of: ",", with: ".")), typed.isFinite else {
            return .invalid
        }
        let cm = (unit.lengthToCm(typed) * 10).rounded() / 10
        return BodyMeasurement.plausibleCm.contains(cm) ? .cm(cm) : .invalid
    }
}

/// A part's latest reading, and how far it has moved since the check-in
/// before that which also measured it.
struct MeasurementReading: Equatable, Identifiable {
    let part: BodyMeasurement.Part
    let cm: Double
    let date: Date
    /// Nil when this is the first time the part was measured.
    let changeCm: Double?
    let previousDate: Date?

    var id: String { part.rawValue }
}

/// The card's arithmetic, kept off the view so it can be tested without one.
enum MeasurementTrend {
    /// Newest first. Two check-ins on one date keep a stable order by ID, the
    /// way the export orders them, so the card and the file agree.
    static func newestFirst(_ checkIns: [BodyMeasurement]) -> [BodyMeasurement] {
        checkIns.sorted { ($0.date, $0.id.uuidString) > ($1.date, $1.id.uuidString) }
    }

    /// The latest value for `part` and its change against the previous
    /// check-in that measured that part. A check-in that skipped the part is
    /// passed over rather than read as no change, so waist taken monthly and
    /// arm taken weekly each compare against their own last reading.
    static func reading(for part: BodyMeasurement.Part, in checkIns: [BodyMeasurement]) -> MeasurementReading? {
        let measured = newestFirst(checkIns).compactMap { check in
            check.value(for: part).map { (cm: $0, date: check.date) }
        }
        guard let latest = measured.first else { return nil }
        let previous = measured.dropFirst().first
        return MeasurementReading(part: part, cm: latest.cm, date: latest.date,
                                  changeCm: previous.map { latest.cm - $0.cm },
                                  previousDate: previous?.date)
    }

    /// Every part that has ever been measured, in the order the check-in asks
    /// for them. A part never measured has no row at all.
    static func readings(in checkIns: [BodyMeasurement]) -> [MeasurementReading] {
        BodyMeasurement.Part.allCases.compactMap { reading(for: $0, in: checkIns) }
    }

    /// "36.5" or "84", in the display unit, with the unit after it when asked.
    static func length(_ cm: Double, unit: WeightUnit, showUnit: Bool = true) -> String {
        let value = (unit.lengthFromCm(cm) * 10).rounded() / 10
        let number = value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return showUnit ? "\(number) \(unit.lengthShort)" : number
    }

    /// "+1.0 cm", "-0.5 cm", or "no change" where it rounds to nothing, so a
    /// reading that moved by hair's breadth isn't reported as a gain.
    static func change(_ cm: Double, unit: WeightUnit) -> String {
        let value = (unit.lengthFromCm(cm) * 10).rounded() / 10
        guard value != 0 else { return "no change" }
        return "\(value > 0 ? "+" : "")\(String(format: "%.1f", value)) \(unit.lengthShort)"
    }
}
