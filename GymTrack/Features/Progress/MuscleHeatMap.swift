import SwiftUI

// MARK: - Heat ramp

/// The colour language of the heat map: cold slate for untouched, teal and
/// emerald while volume accumulates, the app's lime exactly at the weekly
/// target, then amber and orange past it. One glance answers "what have I
/// neglected" and "what have I hammered" without reading a number.
enum MuscleHeat {

    static let ceiling: Double = 1.8

    private struct Stop {
        let at: Double
        let r: Double, g: Double, b: Double
    }

    private static let stops: [Stop] = [
        Stop(at: 0.00, r: 0.125, g: 0.140, b: 0.155),
        Stop(at: 0.12, r: 0.055, g: 0.235, b: 0.220),
        Stop(at: 0.35, r: 0.075, g: 0.435, b: 0.330),
        Stop(at: 0.60, r: 0.165, g: 0.690, b: 0.400),
        Stop(at: 0.82, r: 0.420, g: 0.878, b: 0.235),
        Stop(at: 1.00, r: 0.639, g: 1.000, b: 0.071),
        Stop(at: 1.25, r: 1.000, g: 0.824, b: 0.247),
        Stop(at: 1.80, r: 1.000, g: 0.400, b: 0.220),
    ]

    static func color(_ ratio: Double) -> Color {
        let value = min(max(ratio, 0), ceiling)
        var lower = stops[0]
        var upper = stops[stops.count - 1]
        for index in 1..<stops.count where stops[index].at >= value {
            lower = stops[index - 1]
            upper = stops[index]
            break
        }
        let span = upper.at - lower.at
        let t = span > 0 ? (value - lower.at) / span : 0
        return Color(red: lower.r + (upper.r - lower.r) * t,
                     green: lower.g + (upper.g - lower.g) * t,
                     blue: lower.b + (upper.b - lower.b) * t)
    }

    /// A touch of top-lighting so a muscle reads as a volume, not a sticker.
    static func gradient(_ ratio: Double) -> LinearGradient {
        let base = color(ratio)
        return LinearGradient(
            colors: [base.opacity(1.0), base.opacity(0.72)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// How much bloom a muscle throws — nothing until it is meaningfully
    /// trained, full by the time it reaches target.
    static func glow(_ ratio: Double) -> Double {
        min(max((ratio - 0.4) / 0.6, 0), 1)
    }

    static func label(_ ratio: Double) -> String {
        switch ratio {
        case ..<0.02: "Untouched"
        case ..<0.5: "Light"
        case ..<0.85: "Building"
        case ..<1.16: "On target"
        case ..<1.45: "Over target"
        default: "Hammered"
        }
    }

    static func tint(_ ratio: Double) -> Color {
        ratio < 0.02 ? Theme.textTertiary : color(max(ratio, 0.35))
    }
}

// MARK: - One muscle

/// Conforming the *view* to `Animatable` — rather than the shape — means
/// SwiftUI interpolates the heat value itself, so a muscle warms through the
/// ramp instead of snapping between colours when the window changes.
private struct MuscleFill: View, Animatable {
    var ratio: Double
    var contours: [Contour]
    /// Strength of the rim light. Zero for the blurred bloom pass, where an
    /// edge would only muddy the glow.
    var edge: Double = 1
    var lineWidth: CGFloat = 0.7

    var animatableData: Double {
        get { ratio }
        set { ratio = newValue }
    }

    var body: some View {
        let shape = AnatomyShape(contours: contours)
        shape
            .fill(MuscleHeat.gradient(ratio))
            // Lit from above, shadowed below: the edge is what makes a flat
            // fill read as a muscle belly rather than a sticker.
            .overlay(
                shape.stroke(
                    LinearGradient(colors: [Color.white.opacity(0.22 * edge),
                                            Color.black.opacity(0.55 * edge)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: lineWidth)
            )
    }
}

// MARK: - Figure

/// One side of the body, shaded by training volume.
struct MuscleFigure: View {
    let side: BodySide
    /// Sets logged ÷ weekly target, per muscle.
    let ratios: [Muscle: Double]
    var selected: Muscle?
    var isRevealed: Bool = true
    var onSelect: ((Muscle) -> Void)?

    private var muscles: [Muscle] { Anatomy.muscles(on: side) }

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.height / Anatomy.canvas.height

            ZStack {
                silhouette(unit: unit)
                bloom(unit: unit)
                fills(unit: unit)
                definition(unit: unit)
                selectionRing(unit: unit)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(Anatomy.aspect, contentMode: .fit)
    }

    // The body underneath. Without it the gaps between muscles read as holes.
    private func silhouette(unit: CGFloat) -> some View {
        let shape = AnatomyShape(contours: Anatomy.silhouette)
        return shape
            .fill(LinearGradient(
                colors: [Color.white.opacity(0.085), Color.white.opacity(0.045)],
                startPoint: .top, endPoint: .bottom))
            .overlay(shape.stroke(Color.white.opacity(0.16), lineWidth: max(0.8, unit * 0.55)))
            .shadow(color: .black.opacity(0.6), radius: unit * 3, y: unit * 1.5)
    }

    /// A single blurred pass over the same fills. Trained muscles bleed light
    /// onto the silhouette, which is what makes a hard week *look* like one.
    private func bloom(unit: CGFloat) -> some View {
        ZStack {
            ForEach(muscles) { muscle in
                MuscleFill(ratio: heat(muscle),
                           contours: Anatomy.contours(for: muscle, on: side),
                           edge: 0,
                           lineWidth: 0)
                    .opacity(MuscleHeat.glow(heat(muscle)))
            }
        }
        .blur(radius: unit * 3.2)
        .blendMode(.plusLighter)
        .opacity(0.75)
        .allowsHitTesting(false)
    }

    private func fills(unit: CGFloat) -> some View {
        ZStack {
            ForEach(muscles) { muscle in
                let contours = Anatomy.contours(for: muscle, on: side)
                MuscleFill(ratio: heat(muscle),
                           contours: contours,
                           lineWidth: max(0.6, unit * 0.35))
                    .opacity(dimming(muscle))
                    .contentShape(AnatomyShape(contours: contours))
                    .onTapGesture {
                        guard let onSelect else { return }
                        onSelect(muscle)
                        Haptics.tick()
                    }
                    .accessibilityElement()
                    .accessibilityLabel(muscle.name)
                    .accessibilityValue(MuscleHeat.label(ratios[muscle] ?? 0))
                    .accessibilityAddTraits(.isButton)
            }
        }
    }

    /// Sternum, ab creases, spine — cheap strokes that turn shapes into a body.
    private func definition(unit: CGFloat) -> some View {
        AnatomyLineShape(contours: Anatomy.detailLines(on: side))
            .stroke(Color.black.opacity(0.34),
                    style: StrokeStyle(lineWidth: max(0.7, unit * 0.4), lineCap: .round))
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func selectionRing(unit: CGFloat) -> some View {
        if let selected, !Anatomy.contours(for: selected, on: side).isEmpty {
            let shape = AnatomyShape(contours: Anatomy.contours(for: selected, on: side))
            shape
                .stroke(Color.white, lineWidth: max(1.2, unit * 0.75))
                .shadow(color: MuscleHeat.tint(heat(selected)).opacity(0.9), radius: unit * 2)
                .allowsHitTesting(false)
                .transition(.opacity)
        }
    }

    private func heat(_ muscle: Muscle) -> Double {
        isRevealed ? (ratios[muscle] ?? 0) : 0
    }

    private func dimming(_ muscle: Muscle) -> Double {
        guard let selected, selected != muscle else { return 1 }
        return 0.34
    }
}

// MARK: - Legend

/// A continuous ramp rather than four swatches — the fill is continuous, so the
/// key should be too.
struct HeatLegend: View {
    var body: some View {
        VStack(spacing: 5) {
            LinearGradient(
                colors: stride(from: 0.0, through: MuscleHeat.ceiling, by: 0.1).map { MuscleHeat.color($0) },
                startPoint: .leading, endPoint: .trailing
            )
            .frame(height: 6)
            .clipShape(Capsule())
            .overlay(alignment: .leading) {
                // Where the weekly target sits on the ramp.
                GeometryReader { geo in
                    Rectangle()
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 1.5, height: 10)
                        .offset(x: geo.size.width / MuscleHeat.ceiling, y: -2)
                }
            }

            HStack {
                Text("NONE")
                Spacer()
                Text("TARGET")
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("OVER")
            }
            .font(Theme.rounded(9, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Side switch

/// Two-state switch with the selection sliding between the labels.
struct BodySideSwitch: View {
    @Binding var side: BodySide
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 2) {
            ForEach(BodySide.allCases) { option in
                Button {
                    guard side != option else { return }
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) { side = option }
                    Haptics.tick()
                } label: {
                    Text(option.title.uppercased())
                        .font(Theme.rounded(11, weight: .bold))
                        .tracking(0.9)
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(side == option ? Color.black : Theme.textSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background {
                            if side == option {
                                Capsule()
                                    .fill(Theme.accent)
                                    .matchedGeometryEffect(id: "side", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }
}

// MARK: - Card

/// The heat map as it appears on the progress screen: an aura tinted by how
/// well the week is covered, the figure, and a flip between front and back.
struct MuscleHeatMapView: View {
    let ratios: [Muscle: Double]
    @Binding var side: BodySide
    @Binding var selected: Muscle?
    var height: CGFloat = 320

    @State private var isRevealed = false

    private var flipAngle: Double { side == .front ? 0 : 180 }

    /// Average completion across every muscle — drives the aura.
    private var coverage: Double {
        let values = Muscle.allCases.map { min(ratios[$0] ?? 0, 1) }
        return values.reduce(0, +) / Double(values.count)
    }

    /// The three warmest and three coldest groups, so the empty space beside a
    /// standing figure carries the summary the figure implies.
    private var ranked: [(Muscle, Double)] {
        Muscle.allCases
            .map { ($0, ratios[$0] ?? 0) }
            .sorted { lhs, rhs in
                lhs.1 == rhs.1 ? lhs.0.weeklySetTarget > rhs.0.weeklySetTarget : lhs.1 > rhs.1
            }
    }

    var body: some View {
        HStack(alignment: .center, spacing: 4) {
            MuscleRankColumn(title: "Hottest",
                             entries: Array(ranked.prefix(3)),
                             alignment: .leading,
                             onSelect: select)

            ZStack {
                aura
                figures
            }
            .frame(maxWidth: .infinity)

            MuscleRankColumn(title: "Coldest",
                             entries: Array(ranked.suffix(3).reversed()),
                             alignment: .trailing,
                             onSelect: select)
        }
        .frame(height: height)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { selected = nil }
        .onAppear {
            guard !isRevealed else { return }
            withAnimation(.easeOut(duration: 1.1).delay(0.15)) { isRevealed = true }
        }
    }

    private func select(_ muscle: Muscle) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            if Anatomy.contours(for: muscle, on: side).isEmpty {
                side = muscle.isAnterior ? .front : .back
            }
            selected = selected == muscle ? nil : muscle
        }
        Haptics.tick()
    }

    private var aura: some View {
        RadialGradient(
            colors: [MuscleHeat.color(max(coverage, 0.25)).opacity(isRevealed ? 0.22 : 0.04),
                     .clear],
            center: .center,
            startRadius: 0,
            endRadius: height * 0.62
        )
        .blur(radius: 24)
        .allowsHitTesting(false)
    }

    private var figures: some View {
        ZStack {
            figure(.front)
                .opacity(side == .front ? 1 : 0)
            figure(.back)
                .rotation3DEffect(.degrees(180), axis: (x: 0, y: 1, z: 0))
                .opacity(side == .back ? 1 : 0)
        }
        .rotation3DEffect(.degrees(flipAngle), axis: (x: 0, y: 1, z: 0), perspective: 0.4)
    }

    private func figure(_ figureSide: BodySide) -> some View {
        MuscleFigure(side: figureSide,
                     ratios: ratios,
                     selected: selected,
                     isRevealed: isRevealed) { muscle in
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                selected = selected == muscle ? nil : muscle
            }
        }
        .frame(height: height)
    }
}

/// A ranked list beside the figure. Each row is a name over a bar filled to the
/// same heat colour the muscle is drawn in, so the two readings agree.
struct MuscleRankColumn: View {
    let title: String
    let entries: [(Muscle, Double)]
    let alignment: HorizontalAlignment
    var onSelect: (Muscle) -> Void

    var body: some View {
        VStack(alignment: alignment, spacing: 11) {
            Text(title.uppercased())
                .font(Theme.rounded(8.5, weight: .black))
                .tracking(0.9)
                .foregroundStyle(Theme.textTertiary)

            ForEach(entries, id: \.0) { muscle, ratio in
                Button {
                    onSelect(muscle)
                } label: {
                    VStack(alignment: alignment, spacing: 3) {
                        Text(muscle.name)
                            .font(Theme.rounded(10.5, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                        HStack(spacing: 3) {
                            if alignment == .trailing { Spacer(minLength: 0) }
                            Capsule()
                                .fill(MuscleHeat.gradient(ratio))
                                .frame(width: max(4, 44 * min(ratio, 1.2) / 1.2), height: 3.5)
                            if alignment == .leading { Spacer(minLength: 0) }
                        }
                        .frame(height: 3.5)
                        Text("\(Int((ratio * 100).rounded()))%")
                            .font(Theme.number(9, weight: .bold))
                            .foregroundStyle(MuscleHeat.tint(ratio))
                    }
                    .frame(width: 64, alignment: alignment == .leading ? .leading : .trailing)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 18)
    }
}

#if DEBUG
private struct HeatMapPreview: View {
    @State private var side: BodySide = .front
    @State private var selected: Muscle?

    private let ratios: [Muscle: Double] = [
        .chest: 1.05, .quads: 0.5, .biceps: 0.25, .lats: 1.35, .glutes: 0.85,
        .shoulders: 0.7, .abs: 0.4, .traps: 0.15, .hamstrings: 1.6, .calves: 0.05,
        .triceps: 0.95, .upperBack: 0.6, .forearms: 0.3,
    ]

    var body: some View {
        VStack(spacing: 16) {
            BodySideSwitch(side: $side)
            MuscleHeatMapView(ratios: ratios, side: $side, selected: $selected)
            HeatLegend()
        }
        .padding()
        .background(Theme.background)
    }
}

#Preview("Muscle heat map") { HeatMapPreview() }
#endif
