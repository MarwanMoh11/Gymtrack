import SwiftUI

/// The phone's surfaces, drawn in the same vocabulary as the Live Activity and
/// the watch: phase colour, a ground that falls away from the light, an edge
/// that catches it at the top, and a glow under the one thing the screen is
/// asking you to press.
///
/// The phone had the most room of the three screens and the least depth in it —
/// every panel was one flat fill inside one flat hairline. That reads as a
/// wireframe the moment the Lock Screen card next to it doesn't, so these are
/// deliberately the same shapes the wrist uses: one session, three screens, one
/// look.

// MARK: - Phase on the phone

extension ActiveWorkout {
    /// Which phase this session is in.
    ///
    /// The phone never shows `.restOver`: its rest timer is live and stops
    /// itself the moment it runs out, so there's no sleeping card to wake up
    /// holding a countdown that finished.
    var phase: SessionPhase {
        if restTimer.isRunning { return .resting }
        if totalCount > 0, completedCount >= totalCount { return .done }
        return .working
    }
}

// MARK: - Grounds

extension Theme {
    /// What a panel is filled with. Lifted where light would land and settling
    /// into the screen at the bottom, so a card has a top and a bottom rather
    /// than four identical sides.
    static let panel = LinearGradient(colors: [surfaceRaised, surface],
                                      startPoint: .top, endPoint: .bottom)

    /// Laid over `panel` for the one option in a list that's chosen. Brightness
    /// rather than a second colour — a selected row is the same object, lit.
    static let panelSelected = LinearGradient(
        colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
        startPoint: .top, endPoint: .bottom)

    /// A well pressed *into* a card, for the rows that belong to the card
    /// rather than sitting on it. Darker than the ground it's cut from, which
    /// is the only way a recess reads as a recess.
    static let well = LinearGradient(colors: [Color.black.opacity(0.34), Color.black.opacity(0.16)],
                                     startPoint: .top, endPoint: .bottom)

    /// The hairline around anything. Bright along the top edge, gone by the
    /// bottom — a single flat stroke draws a box, and this draws an object.
    static let edge = LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.03)],
                                     startPoint: .top, endPoint: .bottom)

    /// The edge of a card that belongs to a phase: its colour where the light
    /// lands, fading to the ordinary hairline before it comes back round.
    static func edge(_ phase: SessionPhase) -> LinearGradient {
        LinearGradient(colors: [phase.tint.opacity(0.5), phase.trail.opacity(0.14), Color.white.opacity(0.04)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension View {
    /// The standard panel.
    ///
    /// `phase` tints it for a card that belongs to a running session; `selected`
    /// lifts the one row in a list that's chosen; `dimmed` settles a card that's
    /// finished with back into the screen without hiding it.
    func gtCard(padding: CGFloat = 16,
                radius: CGFloat = Theme.cornerRadius,
                phase: SessionPhase? = nil,
                selected: Bool = false,
                dimmed: Bool = false) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                ZStack {
                    Theme.panel
                    if selected { Theme.panelSelected }
                    if let phase {
                        LinearGradient(colors: [phase.tint.opacity(0.15), phase.trail.opacity(0.04), .clear],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
                .opacity(dimmed ? 0.5 : 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(phase.map { AnyShapeStyle(Theme.edge($0)) } ?? AnyShapeStyle(Theme.edge),
                                  lineWidth: 1)
                    .opacity(dimmed ? 0.55 : 1)
            }
    }

    /// The recess inside a card — the set list under a hero, the breakdown
    /// under a headline.
    func gtWell(vertical: CGFloat = 10, horizontal: CGFloat = 12, radius: CGFloat = 14) -> some View {
        self
            .padding(.vertical, vertical)
            .padding(.horizontal, horizontal)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.well, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.045), lineWidth: 1)
            }
    }

    func gtScreenBackground() -> some View {
        self.background(Theme.background.ignoresSafeArea())
    }

    /// The wash behind the logger, keyed to the phase — amber across the top of
    /// the screen says you're resting before you've read the clock.
    ///
    /// Deliberately faint, and gone by a third of the way down. The card's own
    /// bloom is tuned for a 150pt Lock Screen panel; at full screen height the
    /// same strength turns every white hairline under it green and the phase
    /// stops meaning anything. What the eye needs here is a cast, not a colour.
    func gtSessionTint(_ phase: SessionPhase) -> some View {
        self.background {
            LinearGradient(colors: [phase.tint.opacity(0.10), phase.trail.opacity(0.025), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.45), value: phase)
        }
    }
}

// MARK: - Pieces

/// A symbol in a tinted tile. The shape the Lock Screen card leads with, at the
/// size the phone can afford — it's what makes a row identifiable from across
/// the screen rather than only readable up close.
struct GlyphTile: View {
    let symbol: String
    var tint: Color = Theme.accent
    var size: CGFloat = 34
    /// Filled rather than tinted, for the one glyph on a screen that's the
    /// point of it — the checkmark on the summary, the app mark in onboarding.
    var solid: Bool = false

    private var radius: CGFloat { size * 0.3 }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(solid
                  ? AnyShapeStyle(tint.wash)
                  : AnyShapeStyle(LinearGradient(colors: [tint.opacity(0.26), tint.opacity(0.06)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing)))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(solid ? Color.white.opacity(0.22) : tint.opacity(0.35), lineWidth: 1)
            }
            .overlay {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(solid ? AnyShapeStyle(Color.black) : AnyShapeStyle(tint.wash))
            }
            .frame(width: size, height: size)
            .shadow(color: solid ? tint.opacity(0.4) : .clear, radius: size * 0.3, y: size * 0.08)
    }
}

/// The session's completion as a ring: an angular sweep that's brightest at its
/// leading edge, over a soft core so the middle of the ring isn't a hole.
struct ProgressRing: View {
    let progress: Double          // 0...1
    var lineWidth: CGFloat = 8
    var phase: SessionPhase = .working
    var label: String?

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [phase.tint.opacity(0.14), .clear],
                                     center: .center, startRadius: 0, endRadius: 46))
            Circle()
                .stroke(Color.white.opacity(0.09), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(1, max(0, progress)))
                .stroke(phase.arc, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: phase.glow, radius: 4)
                .animation(.spring(response: 0.5, dampingFraction: 0.85), value: progress)
            if let label {
                Text(label)
                    .font(Theme.number(15))
                    .foregroundStyle(Theme.ink)
            }
        }
    }
}
