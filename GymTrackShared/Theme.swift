import SwiftUI

/// Central design tokens. The app is dark-only by design — a gym app is used in
/// dim rooms and a black ground keeps the neon accent readable.
enum Theme {

    // MARK: - Color

    /// Neon lime — the app's single accent. Carried over from the original web app.
    static let accent = Color(red: 0.639, green: 1.0, blue: 0.071)      // #A3FF12

    static let background = Color(red: 0.02, green: 0.02, blue: 0.024)
    static let surface = Color(red: 0.063, green: 0.067, blue: 0.078)
    static let surfaceRaised = Color(red: 0.094, green: 0.098, blue: 0.114)
    /// A flat separator. For the edge *around* an object, reach for the
    /// gradient `Theme.edge` instead — a hairline that's the same value all the
    /// way round draws a box rather than a thing with a top and a bottom.
    static let hairline = Color.white.opacity(0.08)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    /// Held at 0.50 because it carries 8-11 pt captions, and the lightest
    /// thing it sits on is the top of a selected card (`panelSelected`, 8%
    /// white over `surfaceRaised`). 0.38 measured 3.6:1 on plain cards and 0.46
    /// still left the selected card at 4.2:1; 0.50 clears 4.5:1 on both (4.7:1
    /// on the selected card). The app is dark-only, so there is no light-mode
    /// value to keep in step.
    static let textTertiary = Color.white.opacity(0.50)

    static let positive = Color(red: 0.24, green: 0.85, blue: 0.55)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let negative = Color(red: 1.0, green: 0.35, blue: 0.35)

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 20
    static let cornerRadiusSmall: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 28

    // MARK: - Type

    /// The text style whose default size is exactly `size`, so that size keeps
    /// its look at the default setting and grows with Dynamic Type otherwise.
    /// Sizes with no matching style, and every hero numeral from 23 pt up, stay
    /// fixed: a scaled 44 pt timer would push the logger off the screen. The
    /// watch is left fixed too, because its text styles are sized differently
    /// and a wrist has no room to grow into.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle? {
        #if os(watchOS)
        return nil
        #else
        switch size {
        case 11: return .caption2
        case 12: return .caption
        case 13: return .footnote
        case 15: return .subheadline
        case 16: return .callout
        case 17: return .body
        case 20: return .title3
        case 22: return .title2
        default: return nil
        }
        #endif
    }

    /// Numerals that don't jitter while a timer counts or a weight steps.
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        rounded(size, weight: weight).monospacedDigit()
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        if let style = textStyle(for: size) {
            return .system(style, design: .rounded, weight: weight)
        }
        return .system(size: size, weight: weight, design: .rounded)
    }

    /// Small all-caps label used for section eyebrows.
    static let eyebrow = rounded(11, weight: .bold)

    /// The eyebrow shrunk for the Dynamic Island, where a caption has to sit
    /// under a number without widening the region it lives in. Fixed, because
    /// that region can't grow.
    static let microCaps = Font.system(size: 8, weight: .bold, design: .rounded)
}
