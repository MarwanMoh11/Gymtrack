import SwiftUI

/// The watch app's surfaces, drawn in the same vocabulary as the Live Activity:
/// phase colour, gradient fill, hairline edge, glow under the one thing you're
/// meant to press.
///
/// It matters more here than anywhere else in the app. The watch draws on true
/// black in a gym's lighting, at arm's length, past a bar — a flat fill and a
/// flat border disappear into the bezel, and a gradient with an edge on it
/// doesn't.

// MARK: - Phase on the wrist

extension WatchSessionSnapshot {
    /// Which phase the wrist is in.
    ///
    /// The watch runs its own rest clock — it starts one the instant a set is
    /// logged rather than waiting for the phone to say so — so the timer, not
    /// the mirror, is what decides whether this is a rest.
    func phase(resting: Bool) -> SessionPhase {
        if resting { return .resting }
        if totalSets > 0, completedSets >= totalSets { return .done }
        return .working
    }
}

// MARK: - Surfaces

extension View {
    /// The standard panel. Lifted at the top and settling into the ground at
    /// the bottom, with an edge that catches light the way the hardware does.
    func watchCard(padding: CGFloat = 10,
                   radius: CGFloat = 14,
                   phase: SessionPhase? = nil) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    LinearGradient(colors: [Theme.surfaceRaised, Theme.surface],
                                   startPoint: .top, endPoint: .bottom)
                    if let phase {
                        LinearGradient(colors: [phase.tint.opacity(0.16), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [Color.white.opacity(0.15),
                                                          Color.white.opacity(0.03)],
                                                 startPoint: .top, endPoint: .bottom),
                                  lineWidth: 1)
            }
    }

    /// The wash behind a whole screen, keyed to the phase. Amber at the top of
    /// the logger means you're resting before you've read the number.
    ///
    /// It falls off to nothing by halfway down: the watch's black is the best
    /// surface the app has, and a tint carried the whole way spends it.
    func watchScreenTint(_ phase: SessionPhase) -> some View {
        containerBackground(
            LinearGradient(colors: [phase.tint.opacity(0.26),
                                    phase.trail.opacity(0.07),
                                    .clear],
                           startPoint: .top, endPoint: .center),
            for: .navigation)
    }
}

// MARK: - Buttons

/// The one action a screen is really offering. Gradient-filled with a glow
/// under it, because on a 41mm screen the primary button *is* the interface.
struct WatchProminentButtonStyle: ButtonStyle {
    var phase: SessionPhase = .working

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(15, weight: .heavy))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Capsule().fill(phase.gradient))
            .shadow(color: phase.glow.opacity(configuration.isPressed ? 0.25 : 0.5), radius: 7, y: 2)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// Everything else. Translucent and hairlined — quiet enough that the
/// prominent button above it is never in doubt, lit enough to find in the dark.
struct WatchQuietButtonStyle: ButtonStyle {
    var tint: Color = Theme.textPrimary
    var weight: Font.Weight = .bold
    var size: CGFloat = 13
    /// Set for a button sitting inline beside something else, where the full
    /// height would turn a two-word label into a lozenge.
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.rounded(size, weight: weight))
            .foregroundStyle(tint)
            .frame(maxWidth: compact ? nil : .infinity)
            .padding(.horizontal, compact ? 10 : 0)
            .padding(.vertical, compact ? 5 : 8)
            .background(Capsule().fill(tint.opacity(0.14)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Pieces

/// A symbol in a tinted tile — the same shape the Lock Screen card leads with,
/// shrunk to the wrist.
struct WatchGlyphTile: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 26

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.07)],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                    .strokeBorder(tint.opacity(0.38), lineWidth: 1)
            )
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: size * 0.44, weight: .bold))
                    .foregroundStyle(tint.wash)
            )
            .frame(width: size, height: size)
    }
}

/// The rest countdown as a ring, filling as the rest runs out.
struct WatchRestRing: View {
    let progress: Double
    var phase: SessionPhase = .resting
    var size: CGFloat = 28
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [phase.tint.opacity(0.18), .clear],
                                     center: .center, startRadius: 0, endRadius: size * 0.7))
            Circle()
                .stroke(Color.white.opacity(0.14), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(phase.arc, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: phase.glow, radius: 3)
        }
        .frame(width: size, height: size)
    }
}

/// How much of the rest has run, as one continuous bar.
///
/// `PhaseProgressBar` counts sets, which are discrete and worth drawing as
/// ticks. A rest is a duration, and a duration drawn as ticks reads as a
/// number of things rather than as time going by.
struct WatchRestProgressBar: View {
    let progress: Double
    var phase: SessionPhase = .resting
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.13))
                Capsule()
                    .fill(phase.bar)
                    .frame(width: filledWidth(in: geo.size.width))
                    .shadow(color: phase.glow, radius: 4, y: 1)
            }
        }
        .frame(height: height)
    }

    /// Never narrower than it is tall: a capsule thinner than its own radius
    /// draws as a sliver that reads as a rendering fault rather than as a bar
    /// that has only just started.
    private func filledWidth(in width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0 else { return 0 }
        let fraction = min(1, max(0, progress))
        guard fraction > 0 else { return 0 }
        return min(width, max(height, width * fraction))
    }
}

/// A small translucent capsule for a number that isn't the headline.
struct WatchChip<Content: View>: View {
    var tint: Color = Theme.textSecondary
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 3) { content }
            .foregroundStyle(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(tint.opacity(0.13)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 0.5))
    }
}

/// One of the numbers the Digital Crown turns, and whether the crown is on it.
///
/// The selected tile doesn't just gain a border — it lights: gradient numerals
/// over a tinted ground with a glow behind. Which number the crown is holding
/// is the single most important thing this screen says, and it has to survive
/// being read in a mirror, mid-set, at arm's length.
struct WatchValueTile: View {
    let title: String
    let value: String
    let isEditing: Bool
    var phase: SessionPhase = .working

    var body: some View {
        VStack(spacing: 0) {
            Text(value)
                .font(Theme.number(26))
                .foregroundStyle(isEditing ? AnyShapeStyle(phase.gradient) : AnyShapeStyle(Theme.ink))
                .shadow(color: isEditing ? phase.glow : .clear, radius: 6)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(title.uppercased())
                .font(Theme.eyebrow)
                .foregroundStyle(isEditing ? phase.tint : Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background {
            ZStack {
                LinearGradient(colors: [Theme.surfaceRaised, Theme.surface],
                               startPoint: .top, endPoint: .bottom)
                if isEditing {
                    LinearGradient(colors: [phase.tint.opacity(0.22), phase.trail.opacity(0.05)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isEditing ? AnyShapeStyle(phase.gradient) : AnyShapeStyle(Theme.hairline),
                              lineWidth: isEditing ? 2 : 1)
        }
        .shadow(color: isEditing ? phase.tint.opacity(0.25) : .clear, radius: 7, y: 2)
    }
}
