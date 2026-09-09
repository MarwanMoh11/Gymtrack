import SwiftUI

/// Central design tokens. The app is dark-only by design — a gym app is used in
/// dim rooms and a black ground keeps the neon accent readable.
enum Theme {

    // MARK: - Color

    /// Neon lime — the app's single accent. Carried over from the original web app.
    static let accent = Color(red: 0.639, green: 1.0, blue: 0.071)      // #A3FF12
    static let accentDim = Color(red: 0.639, green: 1.0, blue: 0.071).opacity(0.16)

    static let background = Color(red: 0.02, green: 0.02, blue: 0.024)
    static let surface = Color(red: 0.063, green: 0.067, blue: 0.078)
    static let surfaceRaised = Color(red: 0.094, green: 0.098, blue: 0.114)
    static let hairline = Color.white.opacity(0.08)

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    static let positive = Color(red: 0.24, green: 0.85, blue: 0.55)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.22)
    static let negative = Color(red: 1.0, green: 0.35, blue: 0.35)

    // MARK: - Metrics

    static let cornerRadius: CGFloat = 20
    static let cornerRadiusSmall: CGFloat = 12
    static let cornerRadiusLarge: CGFloat = 28

    // MARK: - Type

    /// Numerals that don't jitter while a timer counts or a weight steps.
    static func number(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded).monospacedDigit()
    }

    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    /// Small all-caps label used for section eyebrows.
    static let eyebrow = Font.system(size: 11, weight: .bold, design: .rounded)
}

extension View {
    /// Standard raised panel used across the app.
    func gtCard(padding: CGFloat = 16, background: Color = Theme.surface) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(background, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }

    func gtScreenBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }
}
