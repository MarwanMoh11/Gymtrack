import SwiftUI

/// A front/back body map shaded by how much each muscle has been trained.
///
/// The figure is assembled from tapered, rotated capsules on a 100 × 210 canvas
/// rather than traced anatomy — it stays crisp at any size, matches the app's
/// geometric look, and every region is big enough to hit with a thumb.
struct BodyMapView: View {
    /// Sets per muscle over the window being visualised.
    let volumes: [Muscle: Double]
    var selected: Muscle?
    var onSelect: (Muscle) -> Void

    var body: some View {
        HStack(spacing: 14) {
            figure(front: true, caption: "Front")
            figure(front: false, caption: "Back")
        }
    }

    private func figure(front: Bool, caption: String) -> some View {
        VStack(spacing: 8) {
            ZStack {
                BodyPartShape(parts: BodyGeometry.frame)
                    .fill(Color.white.opacity(0.06))

                ForEach(Muscle.allCases.filter { front ? $0.isAnterior : !$0.isAnterior }) { muscle in
                    let shape = BodyPartShape(parts: BodyGeometry.parts(for: muscle))
                    shape
                        .fill(fill(for: muscle))
                        .overlay(
                            shape.stroke(selected == muscle ? Theme.accent : Color.black.opacity(0.35),
                                         lineWidth: selected == muscle ? 1.6 : 0.8)
                        )
                        .contentShape(shape)
                        .onTapGesture {
                            onSelect(muscle)
                            Haptics.tick()
                        }
                }
            }
            .aspectRatio(BodyGeometry.canvas.width / BodyGeometry.canvas.height, contentMode: .fit)
            .animation(.easeInOut(duration: 0.2), value: selected)

            Text(caption.uppercased())
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// Shade relative to each muscle's own weekly target, so a small muscle
    /// isn't permanently dark next to quads.
    private func fill(for muscle: Muscle) -> Color {
        let ratio = (volumes[muscle] ?? 0) / Double(muscle.weeklySetTarget)
        if ratio <= 0.01 { return Color.white.opacity(0.11) }
        if ratio < 0.5 { return Theme.accent.opacity(0.30) }
        if ratio < 0.85 { return Theme.accent.opacity(0.55) }
        if ratio <= 1.15 { return Theme.accent.opacity(0.82) }
        return Theme.accent
    }
}

// MARK: - Geometry

/// One primitive of the figure, in canvas coordinates. A capsule with an
/// optional rotation covers every shape the body needs.
struct BodyPart {
    var rect: CGRect
    var cornerRadius: CGFloat
    var rotation: Angle = .zero

    init(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat,
         radius: CGFloat, rotation: Double = 0) {
        self.rect = CGRect(x: x, y: y, width: width, height: height)
        self.cornerRadius = radius
        self.rotation = .degrees(rotation)
    }
}

/// Draws a muscle group, scaling the canvas to whatever rect it's given.
struct BodyPartShape: Shape {
    let parts: [BodyPart]

    func path(in rect: CGRect) -> Path {
        let canvas = BodyGeometry.canvas
        let scale = min(rect.width / canvas.width, rect.height / canvas.height)
        let dx = rect.minX + (rect.width - canvas.width * scale) / 2
        let dy = rect.minY + (rect.height - canvas.height * scale) / 2

        var path = Path()
        for part in parts {
            let scaled = CGRect(
                x: part.rect.minX * scale + dx,
                y: part.rect.minY * scale + dy,
                width: part.rect.width * scale,
                height: part.rect.height * scale
            )
            var piece = Path(roundedRect: scaled,
                             cornerSize: CGSize(width: part.cornerRadius * scale,
                                                height: part.cornerRadius * scale),
                             style: .continuous)
            if part.rotation != .zero {
                let centre = CGPoint(x: scaled.midX, y: scaled.midY)
                piece = piece.applying(
                    CGAffineTransform(translationX: centre.x, y: centre.y)
                        .rotated(by: part.rotation.radians)
                        .translatedBy(x: -centre.x, y: -centre.y)
                )
            }
            path.addPath(piece)
        }
        return path
    }
}

enum BodyGeometry {
    static let canvas = CGSize(width: 100, height: 210)

    private static func p(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                          _ r: CGFloat, _ rotation: Double = 0) -> BodyPart {
        BodyPart(x, y, w, h, radius: r, rotation: rotation)
    }

    /// A complete dark silhouette drawn under the muscle groups. Without it the
    /// gaps between regions read as holes rather than as a body.
    static let frame: [BodyPart] = [
        p(41, 2, 18, 21, 9),          // head
        p(45, 19, 10, 9, 4),          // neck
        p(35, 26, 30, 56, 11),        // torso
        p(36, 76, 28, 18, 8),         // pelvis
        p(22, 30, 12, 30, 6),         // left upper arm
        p(66, 30, 12, 30, 6),         // right upper arm
        p(21, 58, 11, 30, 5.5),       // left forearm
        p(68, 58, 11, 30, 5.5),       // right forearm
        p(21, 86, 11, 12, 5),         // left hand
        p(68, 86, 11, 12, 5),         // right hand
        p(36, 90, 13, 46, 6.5),       // left thigh
        p(51, 90, 13, 46, 6.5),       // right thigh
        p(37, 132, 11, 40, 5.5),      // left lower leg
        p(52, 132, 11, 40, 5.5),      // right lower leg
        p(35, 168, 13, 9, 4),         // left foot
        p(52, 168, 13, 9, 4),         // right foot
    ]

    static func parts(for muscle: Muscle) -> [BodyPart] {
        switch muscle {

        // ---- Anterior ----
        case .shoulders:
            [p(22, 27, 15, 16, 7.5, -10), p(63, 27, 15, 16, 7.5, 10)]
        case .chest:
            [p(37, 32, 12, 16, 5), p(51, 32, 12, 16, 5)]
        case .biceps:
            [p(23, 42, 11, 18, 5.5), p(66, 42, 11, 18, 5.5)]
        case .forearms:
            [p(21, 60, 10, 26, 5), p(69, 60, 10, 26, 5)]
        case .abs:
            [p(43, 50, 14, 28, 5)]
        case .obliques:
            [p(36, 52, 6, 24, 3), p(58, 52, 6, 24, 3)]
        case .quads:
            [p(36, 92, 12, 42, 6), p(52, 92, 12, 42, 6)]
        case .adductors:
            [p(46, 92, 8, 28, 4)]

        // ---- Posterior ----
        case .traps:
            [p(41, 26, 18, 16, 7)]
        case .rearDelts:
            [p(22, 27, 15, 16, 7.5, -10), p(63, 27, 15, 16, 7.5, 10)]
        case .upperBack:
            [p(42, 41, 16, 13, 5)]
        case .lats:
            [p(35, 43, 8, 26, 4, 4), p(57, 43, 8, 26, 4, -4)]
        case .lowerBack:
            [p(42, 55, 16, 25, 5)]
        case .triceps:
            [p(23, 42, 11, 18, 5.5), p(66, 42, 11, 18, 5.5)]
        case .glutes:
            [p(36, 86, 13, 18, 7), p(51, 86, 13, 18, 7)]
        case .hamstrings:
            [p(36, 104, 12, 32, 6), p(52, 104, 12, 32, 6)]
        case .calves:
            [p(37, 136, 11, 28, 5.5), p(52, 136, 11, 28, 5.5)]
        }
    }
}

#if DEBUG
#Preview("Body map") {
    BodyMapView(
        volumes: [.chest: 14, .quads: 7, .biceps: 3, .lats: 16, .glutes: 12,
                  .shoulders: 10, .abs: 5, .traps: 2],
        selected: .chest,
        onSelect: { _ in }
    )
    .frame(height: 260)
    .padding()
    .background(Theme.background)
}
#endif
