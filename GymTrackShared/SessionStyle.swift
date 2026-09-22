import SwiftUI

/// The four things a running session can be doing, and the colour each one
/// owns.
///
/// Shared by the Live Activity and the watch on purpose: rest is the same amber
/// on the Lock Screen as it is on the wrist, so one glance teaches you both.
/// Every tinted surface — glyph tile, ring, bar, keyline, the bloom behind a
/// card — pulls from here, which is what keeps a screen reading as one object
/// rather than a stack of separately coloured parts.
enum SessionPhase {
    /// Between sets, counting down.
    case resting
    /// The rest ran out while the card was asleep.
    case restOver
    /// Under the bar, with sets still to log.
    case working
    /// Every set is in; all that's left is to end the session.
    case done

    /// The near end of every gradient, and the colour of anything drawn solid.
    var tint: Color {
        switch self {
        case .resting: return Theme.warning
        case .restOver, .working: return Theme.accent
        case .done: return Theme.positive
        }
    }

    /// The far end. Near enough in hue to read as shading rather than as a
    /// second colour, far enough that a flat fill picks up some depth.
    var trail: Color {
        switch self {
        case .resting: return Color(red: 1.0, green: 0.45, blue: 0.22)
        case .restOver, .working: return Color(red: 0.33, green: 0.93, blue: 0.44)
        case .done: return Color(red: 0.20, green: 0.80, blue: 0.87)
        }
    }

    var glyph: String {
        switch self {
        case .resting: return "hourglass"
        case .restOver: return "bolt.fill"
        case .working: return "dumbbell.fill"
        case .done: return "checkmark"
        }
    }

    var eyebrow: String {
        switch self {
        case .resting: return "RESTING"
        case .restOver: return "REST DONE"
        case .working: return "ON DECK"
        case .done: return "ALL SETS LOGGED"
        }
    }

    /// Diagonal — for fills with area: a glyph tile, a button, a call-to-action
    /// pill, a number big enough to carry a gradient without muddying.
    var gradient: LinearGradient {
        LinearGradient(colors: [tint, trail], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Left to right, for anything that reads as travel: a progress bar.
    var bar: LinearGradient {
        LinearGradient(colors: [trail, tint], startPoint: .leading, endPoint: .trailing)
    }

    /// Sweeps with a ring from twelve o'clock, so the leading edge of the arc
    /// is also its brightest point.
    var arc: AngularGradient {
        AngularGradient(colors: [trail, tint, tint], center: .center, angle: .degrees(-90))
    }

    /// How hard a filled shape burns into the ground behind it.
    var glow: Color { tint.opacity(0.45) }

    /// The wash behind a card or a screen: the phase colour bleeding in from
    /// one corner and cooling out through the other.
    func bloom(strength: Double = 1) -> some View {
        ZStack {
            RadialGradient(colors: [tint.opacity(0.20 * strength), .clear],
                           center: UnitPoint(x: 0.02, y: -0.10),
                           startRadius: 0, endRadius: 210)
            RadialGradient(colors: [trail.opacity(0.13 * strength), .clear],
                           center: UnitPoint(x: 1.05, y: 1.15),
                           startRadius: 0, endRadius: 185)
            LinearGradient(colors: [Color.white.opacity(0.06 * strength), .clear],
                           startPoint: .top, endPoint: .center)
        }
    }
}

extension Color {
    /// A two-stop wash of one colour, for anything that carries a tint of its
    /// own — heart red, energy amber, a trophy's gold — rather than the
    /// session's. A symbol filled with it has the same depth as one filled
    /// with a phase gradient, without pretending to be a phase.
    var wash: LinearGradient {
        LinearGradient(colors: [self, opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

extension Theme {
    /// White with a little fall-off. A headline drawn in it has some weight to
    /// it instead of sitting flat on the surface.
    static let ink = LinearGradient(colors: [.white, Color.white.opacity(0.72)],
                                    startPoint: .top, endPoint: .bottom)
}

/// Sets completed across a session.
///
/// Drawn as one tick per set while the count is small enough to read — a set is
/// a discrete thing, and a discrete bar shows you the one you're standing in.
/// Past `maxTicks` it falls back to a continuous bar rather than a picket
/// fence, which is why the wrist asks for a lower ceiling than the phone.
struct PhaseProgressBar: View, Animatable {
    let total: Int
    let phase: SessionPhase
    var height: CGFloat = 6
    var maxTicks: Int = 20
    /// Sets completed, as a number the bar can move through: a newly logged
    /// tick fades in across the animation instead of snapping on.
    private var progress: Double

    init(completed: Int, total: Int, phase: SessionPhase, height: CGFloat = 6, maxTicks: Int = 20) {
        self.total = total
        self.phase = phase
        self.height = height
        self.maxTicks = maxTicks
        self.progress = Double(completed)
    }

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    private var completed: Int { Int(progress.rounded(.down)) }

    var body: some View {
        Group {
            if total > 1, total <= maxTicks {
                segments
            } else {
                continuous
            }
        }
        .frame(height: height)
    }

    /// One gradient run across the whole row and laid over the ticks that are
    /// filled, so the colour travels with the session instead of restarting in
    /// every segment.
    ///
    /// Drawn rather than masked. It used to be the gradient masked by a row of
    /// capsules, most of them transparent, and on the phone that went wrong in
    /// exactly one case: with a single tick filled the mask's content collapsed
    /// to that one capsule and the gradient was stretched across the whole row,
    /// so the bar read as finished straight after the first set of every
    /// session. Filling one path with one gradient has no mask to collapse.
    private var segments: some View {
        Canvas { context, size in
            let spacing: CGFloat = total > 12 ? 2 : 3
            let count = max(1, total)
            let width = (size.width - spacing * CGFloat(count - 1)) / CGFloat(count)
            guard width > 0, size.height > 0 else { return }

            func tick(_ index: Int) -> Path {
                let rect = CGRect(x: CGFloat(index) * (width + spacing), y: 0, width: width, height: size.height)
                return Path(roundedRect: rect, cornerRadius: min(width, size.height) / 2)
            }

            var track = Path()
            for index in 0..<count { track.addPath(tick(index)) }
            context.fill(track, with: .color(Color.white.opacity(0.12)))

            let shading = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [phase.trail, phase.tint]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0))

            var lit = context
            lit.addFilter(.shadow(color: phase.glow, radius: 4, y: 1))
            var filled = Path()
            for index in 0..<min(completed, count) { filled.addPath(tick(index)) }
            lit.fill(filled, with: shading)

            // The tick being logged, part of the way in.
            let partial = progress - Double(completed)
            if partial > 0.001, completed < count {
                var fading = lit
                fading.opacity = partial
                fading.fill(tick(completed), with: shading)
            }
        }
    }

    private var continuous: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(phase.bar)
                    .frame(width: filledWidth(in: geo.size.width))
                    .shadow(color: phase.glow, radius: 4, y: 1)
            }
        }
    }

    /// Guarded against the zero and non-finite sizes a widget gets handed on
    /// its first layout pass.
    private func filledWidth(in width: CGFloat) -> CGFloat {
        guard width.isFinite, width > 0, total > 0 else { return 0 }
        let fraction = min(1, max(0, progress / Double(total)))
        guard fraction > 0 else { return 0 }
        return min(width, max(height, width * fraction))
    }
}
