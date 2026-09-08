import SwiftUI

// MARK: - Sides

enum BodySide: String, CaseIterable, Identifiable, Hashable {
    case front, back

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        }
    }
}

// MARK: - Contours

/// A closed outline authored on the anatomy canvas.
///
/// Regions are described by a handful of points rather than by bezier control
/// handles; the spline below turns them into an organic outline. Anything
/// symmetric is authored once on the body's right and mirrored, so the figure
/// can never drift out of balance.
struct Contour {
    enum Symmetry {
        /// Drawn exactly as authored — for parts that straddle the midline.
        case whole
        /// Authored on the body's right, drawn again mirrored on the left.
        case pair
        /// Authored top-centre → down the right → bottom-centre, then closed
        /// by its own mirror image.
        case halfLoop
    }

    var symmetry: Symmetry
    var points: [CGPoint]
    /// Below 1 the spline pulls towards straight lines between points.
    var tension: CGFloat

    init(_ symmetry: Symmetry, tension: CGFloat = 1, _ points: [CGPoint]) {
        self.symmetry = symmetry
        self.tension = tension
        self.points = points
    }

    var loops: [[CGPoint]] {
        switch symmetry {
        case .whole:
            [points]
        case .pair:
            [points, points.map(Anatomy.mirrored)]
        case .halfLoop:
            [points + points.dropFirst().dropLast().reversed().map(Anatomy.mirrored)]
        }
    }
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

// MARK: - Anatomy

/// Coordinates for the front and back figures on a 100 × 220 canvas.
///
/// The proportions are a stylised eight-head figure: shoulders 2.6 heads wide,
/// waist at 0.62 of the shoulder span, knees at 70% of standing height. Every
/// muscle region is large enough to hit with a thumb at the sizes the app draws
/// the figure — that constraint, not literal anatomy, decides where borders sit.
enum Anatomy {

    static let canvas = CGSize(width: 100, height: 220)
    static let aspect = canvas.width / canvas.height
    static let axis: CGFloat = 50

    static func mirrored(_ point: CGPoint) -> CGPoint {
        CGPoint(x: 2 * axis - point.x, y: point.y)
    }

    /// Scales the canvas into `rect`, preserving aspect and centring.
    static func transform(in rect: CGRect) -> CGAffineTransform {
        let scale = min(rect.width / canvas.width, rect.height / canvas.height)
        let dx = rect.minX + (rect.width - canvas.width * scale) / 2
        let dy = rect.minY + (rect.height - canvas.height * scale) / 2
        return CGAffineTransform(translationX: dx, y: dy).scaledBy(x: scale, y: scale)
    }

    // MARK: Silhouette

    private static let head = Contour(.whole, [
        pt(50, 3), pt(57, 5.5), pt(60.5, 13), pt(59, 22), pt(54, 28),
        pt(50, 29.5), pt(46, 28), pt(41, 22), pt(39.5, 13), pt(43, 5.5),
    ])

    private static let neck = Contour(.whole, [
        pt(44, 23), pt(56, 23), pt(58, 32), pt(50, 35.5), pt(42, 32),
    ])

    private static let torso = Contour(.halfLoop, [
        pt(50, 30), pt(58, 32), pt(66, 36), pt(70, 44), pt(69.5, 55),
        pt(67, 66), pt(64.5, 76), pt(66, 86), pt(70, 95), pt(68, 104),
        pt(60, 109), pt(50, 110.5),
    ])

    /// Upper arm, forearm and hand in one loop: down the outside, back up the
    /// inside. The inner edge stays clear of the ribs so the notch between arm
    /// and torso reads at a glance.
    private static let arms = Contour(.pair, [
        pt(66, 35), pt(74, 33.5), pt(80.5, 38), pt(83, 46), pt(82.5, 56),
        pt(80.5, 68), pt(78.5, 80), pt(77, 92), pt(75.5, 103), pt(74.5, 110),
        pt(75.5, 120), pt(73, 127), pt(68.5, 126.5), pt(67.5, 118), pt(68, 108),
        pt(69, 96), pt(70.5, 84), pt(71.5, 70), pt(71, 58), pt(69, 48),
        pt(67, 39),
    ])

    private static let legs = Contour(.pair, [
        pt(50.5, 105), pt(63.5, 104.5), pt(70, 112), pt(69, 124), pt(66.5, 138),
        pt(65, 150), pt(64.5, 160), pt(63, 172), pt(60, 186), pt(58.5, 197),
        pt(62.5, 204), pt(63, 208), pt(52.5, 208), pt(52, 197), pt(53, 186),
        pt(54.5, 172), pt(55, 160), pt(54, 150), pt(53, 136), pt(52, 120),
        pt(51, 109),
    ])

    static let silhouette: [Contour] = [head, neck, torso, arms, legs]

    // MARK: Muscle regions

    /// Which muscles are drawn on a side, in painting order — overlapping
    /// regions read correctly when the deeper one goes down first.
    static func muscles(on side: BodySide) -> [Muscle] {
        switch side {
        case .front:
            [.traps, .shoulders, .chest, .obliques, .abs, .biceps, .forearms, .adductors, .quads]
        case .back:
            [.traps, .rearDelts, .upperBack, .lats, .lowerBack, .triceps, .forearms,
             .glutes, .hamstrings, .calves]
        }
    }

    /// The outline(s) for a muscle on a side. Empty when the muscle isn't
    /// visible from that angle.
    static func contours(for muscle: Muscle, on side: BodySide) -> [Contour] {
        switch (muscle, side) {

        // ---- Visible from both angles ----
        case (.traps, .front):
            [Contour(.pair, tension: 0.9, [pt(52, 30), pt(59, 32), pt(66, 36.5), pt(60, 39.5), pt(54, 35)])]
        case (.traps, .back):
            [Contour(.whole, tension: 0.85, [
                pt(50, 29), pt(56, 31), pt(61.5, 35.5), pt(61, 44), pt(56, 50),
                pt(50, 52.5), pt(44, 50), pt(39, 44), pt(38.5, 35.5), pt(44, 31),
            ])]
        case (.forearms, _):
            [Contour(.pair, tension: 0.8, [
                pt(69.5, 85.5), pt(74, 85.5), pt(77.3, 89), pt(77, 96), pt(75.6, 103),
                pt(74, 109.5), pt(70.5, 111.5), pt(68.5, 106), pt(68, 97), pt(68.4, 89.5),
            ])]

        // ---- Anterior ----
        case (.shoulders, .front):
            [Contour(.pair, tension: 0.8, [
                pt(65.5, 41), pt(68, 37), pt(72, 34.5), pt(76.5, 34.5), pt(80, 37.5),
                pt(82.5, 42), pt(83, 48), pt(81.5, 54), pt(78, 57.5), pt(73.5, 56),
                pt(69.5, 52), pt(66.5, 46),
            ])]
        case (.chest, .front):
            [Contour(.pair, tension: 0.72, [
                pt(51, 38.6), pt(56, 38), pt(61, 38.8), pt(64.8, 40.6), pt(67, 43.4),
                pt(67.4, 46.6), pt(64.6, 49.6), pt(60.8, 52.4), pt(56.4, 54.6),
                pt(52.6, 56), pt(51.2, 55), pt(51, 46),
            ])]
        case (.biceps, .front):
            [Contour(.pair, tension: 0.8, [
                pt(69.5, 56.5), pt(73.5, 56), pt(77, 59), pt(78.5, 66), pt(78, 73),
                pt(76.5, 79.5), pt(73.5, 81.5), pt(70.5, 79), pt(69, 72), pt(68.6, 63),
            ])]
        case (.abs, .front):
            [Contour(.whole, tension: 0.72, [
                pt(42.8, 60.5), pt(46, 58.8), pt(50, 58.4), pt(54, 58.8), pt(57.2, 60.5),
                pt(57.8, 66), pt(57.9, 73), pt(57.4, 80), pt(56.4, 86.5), pt(54.8, 91),
                pt(52.4, 93.5), pt(50, 94), pt(47.6, 93.5), pt(45.2, 91), pt(43.6, 86.5),
                pt(42.6, 80), pt(42.1, 73), pt(42.2, 66),
            ])]
        case (.obliques, .front):
            [Contour(.pair, tension: 0.8, [
                pt(58.6, 63), pt(62.5, 64), pt(65.4, 67), pt(66.2, 73), pt(65.4, 80),
                pt(63.2, 86), pt(60, 88.5), pt(58.2, 84), pt(57.8, 74),
            ])]
        case (.quads, .front):
            [Contour(.pair, tension: 0.75, [
                pt(52.5, 112.5), pt(57, 111.8), pt(62, 112.3), pt(66, 114.5), pt(67.6, 120),
                pt(67, 128), pt(65.8, 136), pt(64.3, 142), pt(62.3, 146.5), pt(59.6, 148),
                pt(57.2, 146.5), pt(55.8, 142), pt(55, 135), pt(54, 127), pt(53.1, 119),
            ])]
        case (.adductors, .front):
            [Contour(.pair, tension: 0.9, [pt(50.5, 113), pt(56, 114), pt(55.5, 130),
                                           pt(52.5, 142), pt(50.5, 134)])]

        // ---- Posterior ----
        case (.rearDelts, .back):
            [Contour(.pair, tension: 0.8, [
                pt(65.5, 41), pt(68, 37), pt(72, 34.5), pt(76.5, 34.5), pt(80, 37.5),
                pt(82.5, 42), pt(83, 48), pt(81.5, 54), pt(78, 57.5), pt(73.5, 56),
                pt(69.5, 52), pt(66.5, 46),
            ])]
        case (.upperBack, .back):
            [Contour(.pair, tension: 0.9, [pt(51, 54), pt(59, 56), pt(61.5, 66),
                                           pt(57, 73), pt(51, 71)])]
        case (.lats, .back):
            [Contour(.pair, tension: 0.75, [
                pt(59.5, 55.5), pt(64, 56.5), pt(67.5, 60), pt(68.6, 66), pt(67.6, 73),
                pt(64.6, 80), pt(60.5, 86), pt(57.6, 87), pt(57, 79), pt(57.3, 68),
                pt(58, 60),
            ])]
        case (.lowerBack, .back):
            [Contour(.whole, tension: 0.85, [pt(44, 73), pt(50, 71.5), pt(56, 73), pt(58, 84),
                                             pt(54, 95), pt(50, 98), pt(46, 95), pt(42, 84)])]
        case (.triceps, .back):
            [Contour(.pair, tension: 0.8, [
                pt(69, 55), pt(73.5, 54.5), pt(77.5, 57.5), pt(79, 64), pt(78.5, 72),
                pt(77, 79), pt(73.5, 81.5), pt(70.5, 78), pt(69, 70), pt(68.4, 62),
            ])]
        case (.glutes, .back):
            [Contour(.pair, tension: 0.78, [
                pt(50.5, 90.5), pt(56, 90), pt(61, 91), pt(66, 93.5), pt(69.5, 98),
                pt(70, 104), pt(68, 109.5), pt(63, 113), pt(56.5, 114), pt(51, 112.5),
            ])]
        case (.hamstrings, .back):
            [Contour(.pair, tension: 0.75, [
                pt(52.8, 116), pt(58, 115.4), pt(63, 116), pt(66.6, 118.5), pt(67.6, 124),
                pt(67, 132), pt(65.6, 139), pt(63.6, 145), pt(60.8, 148.5), pt(57.8, 148),
                pt(56, 143), pt(54.8, 135), pt(53.8, 126),
            ])]
        case (.calves, .back):
            [Contour(.pair, tension: 0.8, [
                pt(54.5, 155), pt(58.5, 153.5), pt(62.3, 156), pt(64.2, 163), pt(63.8, 171),
                pt(61.8, 180), pt(59, 185), pt(56.3, 181), pt(54.6, 172), pt(53.6, 163),
            ])]

        default:
            []
        }
    }

    // MARK: Definition lines

    /// Open strokes drawn over the fills. They cost nothing and are what stops
    /// the figure reading as a set of pills — the sternum, the ab creases and
    /// the spine are how the eye recognises a torso.
    static func detailLines(on side: BodySide) -> [Contour] {
        switch side {
        case .front:
            [
                Contour(.whole, [pt(50, 40), pt(50, 50), pt(50, 59)]),
                Contour(.whole, [pt(50, 62), pt(50, 79), pt(50, 96)]),
                Contour(.whole, [pt(44.8, 70), pt(50, 71), pt(55.2, 70)]),
                Contour(.whole, [pt(45.2, 80), pt(50, 81), pt(54.8, 80)]),
                Contour(.pair, [pt(52.5, 32.5), pt(59, 34.5), pt(65.5, 37.5)]),
                Contour(.pair, [pt(56.5, 151), pt(59.5, 154), pt(64, 151)]),
            ]
        case .back:
            [
                Contour(.whole, [pt(50, 33), pt(50, 62), pt(50, 97)]),
                Contour(.pair, [pt(53, 52), pt(60, 55), pt(62.5, 64)]),
                Contour(.whole, [pt(50, 92), pt(50, 102), pt(50, 113)]),
                Contour(.pair, [pt(56, 152), pt(59.5, 155), pt(64, 152)]),
            ]
        }
    }
}

// MARK: - Shapes

/// Fills a set of contours, scaled to whatever rect it is given.
struct AnatomyShape: Shape {
    var contours: [Contour]

    func path(in rect: CGRect) -> Path {
        let transform = Anatomy.transform(in: rect)
        var path = Path()
        for contour in contours {
            for loop in contour.loops {
                path.addPath(Spline.closed(loop.map { $0.applying(transform) },
                                           tension: contour.tension))
            }
        }
        return path
    }
}

/// Strokes a set of contours as open curves.
struct AnatomyLineShape: Shape {
    var contours: [Contour]

    func path(in rect: CGRect) -> Path {
        let transform = Anatomy.transform(in: rect)
        var path = Path()
        for contour in contours {
            for loop in contour.loops {
                path.addPath(Spline.open(loop.map { $0.applying(transform) },
                                         tension: contour.tension))
            }
        }
        return path
    }
}

// MARK: - Spline

/// Centripetal Catmull-Rom through a list of points.
///
/// Centripetal parameterisation (α = 0.5) is the one variant guaranteed not to
/// loop back on itself at tight corners — which matters here, because armpits
/// and the crotch are exactly that.
enum Spline {

    static func closed(_ points: [CGPoint], tension: CGFloat = 1) -> Path {
        guard points.count > 2 else { return polyline(points, closed: true) }
        var path = Path()
        path.move(to: points[0])
        let n = points.count
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n]
            let p1 = points[i]
            let p2 = points[(i + 1) % n]
            let p3 = points[(i + 2) % n]
            let (c1, c2) = controls(p0, p1, p2, p3, tension)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        path.closeSubpath()
        return path
    }

    static func open(_ points: [CGPoint], tension: CGFloat = 1) -> Path {
        guard points.count > 2 else { return polyline(points, closed: false) }
        var path = Path()
        path.move(to: points[0])
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)]
            let p1 = points[i]
            let p2 = points[i + 1]
            let p3 = points[min(i + 2, points.count - 1)]
            let (c1, c2) = controls(p0, p1, p2, p3, tension)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }

    private static func polyline(_ points: [CGPoint], closed: Bool) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
        if closed { path.closeSubpath() }
        return path
    }

    /// Bezier control points for the segment p1 → p2, from the non-uniform
    /// Catmull-Rom tangents (Barry–Goldman).
    private static func controls(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint,
                                 _ tension: CGFloat) -> (CGPoint, CGPoint) {
        let d1 = knot(p0, p1), d2 = knot(p1, p2), d3 = knot(p2, p3)

        var m1 = CGPoint(
            x: ((p1.x - p0.x) / d1 - (p2.x - p0.x) / (d1 + d2) + (p2.x - p1.x) / d2) * d2,
            y: ((p1.y - p0.y) / d1 - (p2.y - p0.y) / (d1 + d2) + (p2.y - p1.y) / d2) * d2
        )
        var m2 = CGPoint(
            x: ((p2.x - p1.x) / d2 - (p3.x - p1.x) / (d2 + d3) + (p3.x - p2.x) / d3) * d2,
            y: ((p2.y - p1.y) / d2 - (p3.y - p1.y) / (d2 + d3) + (p3.y - p2.y) / d3) * d2
        )
        m1.x *= tension; m1.y *= tension
        m2.x *= tension; m2.y *= tension

        return (CGPoint(x: p1.x + m1.x / 3, y: p1.y + m1.y / 3),
                CGPoint(x: p2.x - m2.x / 3, y: p2.y - m2.y / 3))
    }

    /// Centripetal knot spacing, floored so coincident points can't divide by zero.
    private static func knot(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let distance = hypot(b.x - a.x, b.y - a.y)
        return max(sqrt(distance), 0.0001)
    }
}
