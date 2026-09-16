import Foundation

/// Weight unit, and the arithmetic that goes with it. Everything in the app is
/// stored in kilograms; this is the only place that converts.
///
/// Shared rather than app-local because the watch draws weights too, and it has
/// no access to the phone's settings beyond what arrives in a payload.
enum WeightUnit: String, CaseIterable, Identifiable, Codable, Sendable {
    case kg, lb
    var id: String { rawValue }
    var label: String { self == .kg ? "Kilograms" : "Pounds" }
    var short: String { rawValue }

    /// Smallest sensible increment when stepping a weight in this unit.
    var step: Double { self == .kg ? 2.5 : 5 }

    func fromKg(_ kg: Double) -> Double { self == .kg ? kg : kg * 2.20462262 }
    func toKg(_ value: Double) -> Double { self == .kg ? value : value / 2.20462262 }

    /// A display-unit value rounded to a clean increment.
    func snap(_ displayValue: Double) -> Double {
        let step = self == .kg ? 0.5 : 1.0
        return (displayValue / step).rounded() * step
    }

    /// "60 kg" / "135 lb" from a stored kilogram value.
    func format(_ kg: Double, showUnit: Bool = true, decimals: Int? = nil) -> String {
        let value = fromKg(kg)
        let places = decimals ?? (value.truncatingRemainder(dividingBy: 1) == 0 ? 0 : 1)
        let number = String(format: "%.\(places)f", value)
        return showUnit ? "\(number) \(short)" : number
    }
}

extension Double {
    /// Compact volume label — 12,400 kg becomes "12.4k".
    var compactVolume: String {
        if self >= 1000 { return String(format: "%.1fk", self / 1000) }
        return String(format: "%.0f", self)
    }
}

extension TimeInterval {
    /// mm:ss, or h:mm:ss past an hour.
    var clockString: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1:12" / "48m" — the same length trimmed to four characters, for the
    /// Dynamic Island's compact pill, which grows with every glyph it draws.
    var shortDurationString: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        return h > 0 ? String(format: "%d:%02d", h, m) : "\(m)m"
    }

    /// "1h 12m" / "48m" — for summaries rather than live counters.
    var durationString: String {
        let total = Int(self.rounded())
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "\(total)s"
    }
}
