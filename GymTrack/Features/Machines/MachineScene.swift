import SceneKit
import UIKit
import simd

/// A `MachineRig` drawn in SceneKit: the parts, the lights, a camera, and the
/// moving groups each adjustment drives.
///
/// Static parts are flattened into one node per group, highlight and option,
/// so a machine is a few dozen draw calls rather than hundreds. Nothing is
/// redrawn unless something moves: `step` runs only while a part or the camera
/// is still settling, and reports when it has.
@MainActor
final class MachineScene {
    let rig: MachineRig
    let scene = SCNScene()
    let cameraNode = SCNNode()
    private let root = SCNNode()

    private struct Group {
        let node: SCNNode
        let pivot: SIMD3<Double>
        let base: SIMD3<Double>
        let spec: RigGroup
    }
    private var groups: [String: Group] = [:]
    private var highlights: [String: [SCNMaterial]] = [:]
    private var optionNodes: [(node: SCNNode, opt: [String: Int])] = []
    private var cables: [(node: SCNNode, points: [RigPoint], dynamic: Bool)] = []

    /// Where each adjustment is drawn right now, and where it is heading.
    private(set) var drawn: [String: Double] = [:]
    private var targets: [String: Double] = [:]
    private var glow: [String: Double] = [:]
    private var focused: String?

    private(set) var view: RigView
    private var goalView: RigView
    private var aspect: Double = 4.0 / 3.0
    private let zoom: Double
    private var bounds: (min: SIMD3<Double>, max: SIMD3<Double>) = (.zero, .zero)

    /// Draws `rig` with `settings` applied; anything not set is drawn where the
    /// model was made.
    init(rig: MachineRig, settings: MachineSettings = MachineSettings(), zoom: Double = 1) {
        self.rig = rig
        self.view = rig.view
        self.goalView = rig.view
        self.zoom = zoom
        for a in rig.adjustments {
            let value = Double(settings[a.id] ?? a.value)
            drawn[a.id] = value
            targets[a.id] = value
            glow[a.id] = 0
        }
        scene.background.contents = UIColor.clear
        scene.rootNode.addChildNode(root)
        build()
        apply()
        stage()
        placeCamera()
    }

    /// The node for a moving group; the tests read its transform.
    func groupNode(_ id: String) -> SCNNode? { groups[id]?.node }

    // MARK: Changing what is shown

    func set(_ adjustmentID: String, to value: Int, animated: Bool = true) {
        targets[adjustmentID] = Double(value)
        if !animated { drawn[adjustmentID] = Double(value) }
        apply()
    }

    /// Lights the parts an adjustment moves and turns to look at them; nil
    /// lets every highlight fade.
    func focus(_ adjustmentID: String?) {
        focused = adjustmentID
        if let id = adjustmentID, let view = rig.adjustment(id)?.view { goalView = view }
    }

    func turn(by degrees: Double, tilt: Double = 0) {
        view = RigView(az: view.az + degrees, el: min(40, max(2, view.el + tilt)))
        goalView = view
        placeCamera()
    }

    func resize(aspect: Double) {
        guard aspect.isFinite, aspect > 0, abs(aspect - self.aspect) > 0.001 else { return }
        self.aspect = aspect
        placeCamera()
    }

    /// Advances every spring by `dt` seconds. Returns false once nothing is
    /// left moving, so the view can stop asking for frames.
    @discardableResult
    func step(_ dt: Double) -> Bool {
        let k = 1 - exp(-dt * 11)
        var moving = false
        for (id, goal) in targets {
            let now = drawn[id] ?? goal
            if abs(goal - now) > 0.0005 {
                drawn[id] = now + (goal - now) * k
                moving = true
            } else {
                drawn[id] = goal
            }
            let lit = id == focused ? 1.0 : 0.0, g = glow[id] ?? 0
            if abs(lit - g) > 0.004 {
                glow[id] = g + (lit - g) * (1 - exp(-dt * 9))
                moving = true
            } else {
                glow[id] = lit
            }
        }
        let daz = goalView.az - view.az, del = goalView.el - view.el
        if abs(daz) > 0.05 || abs(del) > 0.05 {
            view = RigView(az: view.az + daz * k, el: view.el + del * k)
            moving = true
        } else {
            view = goalView
        }
        apply()
        placeCamera()
        return moving
    }

    // MARK: Building

    private func build() {
        let materials = Self.materials(rig.finish)
        groups[""] = Group(node: root, pivot: .zero, base: .zero, spec: RigGroup(id: "", pivot: [0, 0, 0], drive: nil, parent: nil))
        var drivenBy: [String: String] = [:]
        for spec in rig.groups ?? [] {
            guard let parent = groups[spec.parent ?? ""] else { continue }
            let pivot = SIMD3(spec.pivot), base = pivot - parent.pivot
            let node = SCNNode()
            node.name = spec.id
            node.simdPosition = SIMD3<Float>(base)
            parent.node.addChildNode(node)
            groups[spec.id] = Group(node: node, pivot: pivot, base: base, spec: spec)
            if let drive = spec.drive { drivenBy[spec.id] = drive.adj }
        }

        // One bucket per group, material, highlight and option set.
        struct Bucket { var node = SCNNode(); var group: String; var hl: String; var opt: [String: Int]?; var material: SCNMaterial }
        var buckets: [String: Bucket] = [:], order: [String] = []
        var cache: [String: SCNGeometry] = [:]
        // The machine's extent, worked out from the parts as they are placed.
        // SceneKit leaves a flattened node's bounds unset until it is drawn,
        // which is too late to aim the first camera.
        var lo = SIMD3<Double>(repeating: .greatestFiniteMagnitude), hi = -lo
        func enclose(_ point: SIMD3<Double>) {
            lo = simd_min(lo, point)
            hi = simd_max(hi, point)
        }

        func add(_ part: RigPart) {
            if part.s == "cable" {
                let node = SCNNode()
                root.addChildNode(node)
                let dynamic = (part.pts ?? []).contains { if case .attached = $0 { return true } else { return false } }
                cables.append((node, part.pts ?? [], dynamic))
                return
            }
            if part.s == "tube", let pts = part.pts, let first = pts.first, let last = pts.last {
                for end in [first, last] {
                    if case .fixed(let p) = end {
                        add(RigPart(s: "ball", p: [p.x, p.y, p.z], r: part.r, m: part.m, g: part.g, hl: part.hl, opt: part.opt))
                    }
                }
            }
            let group = part.g ?? "", hl = part.hl ?? drivenBy[group] ?? ""
            guard let owner = groups[group],
                  let shape = Self.shape(part, cache: &cache) else { return }
            let optKey = part.opt.map { $0.keys.sorted().map { "\($0)=\(part.opt![$0]!)" }.joined(separator: ",") } ?? ""
            let key = [group, part.m ?? "frame", hl, optKey].joined(separator: "|")
            let geometry = shape.geometry.copy() as! SCNGeometry
            var material = materials[part.m ?? "frame"] ?? materials["frame"]!
            if !hl.isEmpty {
                // Each lit bucket gets its own material so lighting one
                // adjustment doesn't light every part that shares a finish.
                if let lit = highlights[hl]?.first(where: { $0.name == (part.m ?? "frame") }) {
                    material = lit
                } else {
                    material = material.copy() as! SCNMaterial
                    material.name = part.m ?? "frame"
                    material.emission.contents = UIColor(red: 0.639, green: 1, blue: 0.071, alpha: 1)
                    material.emission.intensity = 0
                    highlights[hl, default: []].append(material)
                }
            }
            geometry.materials = [material]
            if buckets[key] == nil {
                buckets[key] = Bucket(group: group, hl: hl, opt: part.opt, material: material)
                order.append(key)
            }
            let child = SCNNode(geometry: geometry)
            let (a, b) = shape.geometry.boundingBox
            for x in [a.x, b.x] {
                for y in [a.y, b.y] {
                    for z in [a.z, b.z] {
                        let corner = shape.transform * SIMD4<Double>(Double(x), Double(y), Double(z), 1)
                        enclose(SIMD3(corner.x, corner.y, corner.z))
                    }
                }
            }
            if part.s == "tube", let r = part.r {
                for case .fixed(let p) in part.pts ?? [] {
                    enclose(p - SIMD3(repeating: r))
                    enclose(p + SIMD3(repeating: r))
                }
            }
            var transform = shape.transform
            transform.columns.3 -= SIMD4<Double>(owner.pivot, 0)
            child.simdTransform = Self.float4x4(transform)
            buckets[key]!.node.addChildNode(child)
        }
        rig.parts.forEach(add)
        bounds = lo.x <= hi.x ? (lo, hi) : (.zero, SIMD3(1, 1, 1))

        for key in order {
            guard let bucket = buckets[key], let owner = groups[bucket.group] else { continue }
            let flat = bucket.node.flattenedClone()
            // Flattening may copy materials; the highlight has to reach the
            // ones actually drawn.
            flat.geometry?.materials = [bucket.material]
            flat.castsShadow = true
            owner.node.addChildNode(flat)
            if let opt = bucket.opt { optionNodes.append((flat, opt)) }
        }
    }

    /// Moves every driven group to where its adjustment is drawn, shows the
    /// options that match, re-threads the cables and sets the glow.
    private func apply() {
        for (id, group) in groups where !id.isEmpty {
            guard let drive = group.spec.drive, let a = rig.adjustment(drive.adj), let value = drawn[drive.adj] else { continue }
            let k = value - Double(a.base ?? 1)
            if let t = drive.t {
                group.node.simdPosition = SIMD3<Float>(group.base + SIMD3(t) * k)
            }
            if let r = drive.r {
                group.node.simdEulerAngles = SIMD3<Float>(SIMD3(r) * k * .pi / 180)
            }
        }
        for (node, opt) in optionNodes {
            node.isHidden = !opt.allSatisfy { id, index in targets[id].map { Int($0.rounded()) } == index }
        }
        for i in cables.indices where cables[i].dynamic || cables[i].node.geometry == nil {
            let points: [SIMD3<Float>] = cables[i].points.compactMap { point in
                switch point {
                case .fixed(let p):
                    return SIMD3<Float>(p)
                case .attached(let g, let p):
                    guard let group = groups[g] else { return nil }
                    return group.node.simdConvertPosition(SIMD3<Float>(p - group.pivot), to: root)
                }
            }
            let geometry = TubeMesh.make(path: points, radius: 0.0045, sides: 6)
            geometry.materials = [Self.cableMaterial]
            cables[i].node.geometry = geometry
        }
        for (id, materials) in highlights {
            let level = (glow[id] ?? 0) * 0.55
            for material in materials { material.emission.intensity = level }
        }
    }

    // MARK: Stage

    private func stage() {
        let center = (bounds.min + bounds.max) / 2
        let radius = simd_length(bounds.max - bounds.min) / 2

        let key = SCNLight()
        key.type = .directional
        key.intensity = 1250
        key.castsShadow = true
        key.shadowMapSize = CGSize(width: 2048, height: 2048)
        key.shadowRadius = 6
        key.shadowSampleCount = 8
        key.shadowColor = UIColor.black.withAlphaComponent(0.55)
        key.orthographicScale = radius * 1.3
        key.zNear = 0.1
        key.zFar = radius * 8
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.simdPosition = SIMD3<Float>(center + SIMD3(radius * 0.9, radius * 2.6, radius * 1.2))
        keyNode.simdLook(at: SIMD3<Float>(center))
        scene.rootNode.addChildNode(keyNode)

        // Low and behind, so it catches vertical edges without turning a black
        // frame's top faces white.
        let rim = SCNLight()
        rim.type = .directional
        rim.intensity = 650
        rim.color = UIColor(red: 0.87, green: 0.91, blue: 1, alpha: 1)
        let rimNode = SCNNode()
        rimNode.light = rim
        rimNode.simdPosition = SIMD3<Float>(center + SIMD3(-radius * 1.6, radius * 0.45 - center.y, -radius * 0.7))
        rimNode.simdLook(at: SIMD3<Float>(center))
        scene.rootNode.addChildNode(rimNode)

        let fill = SCNLight()
        fill.type = .ambient
        fill.intensity = 180
        fill.color = UIColor(red: 0.91, green: 0.93, blue: 0.96, alpha: 1)
        let fillNode = SCNNode()
        fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)

        scene.lightingEnvironment.contents = StudioEnvironment.image
        scene.lightingEnvironment.intensity = 0.85

        // The floor only catches the shadow; the card behind shows through.
        let floor = SCNPlane(width: radius * 5, height: radius * 5)
        let shadowOnly = SCNMaterial()
        shadowOnly.lightingModel = .shadowOnly
        floor.materials = [shadowOnly]
        let floorNode = SCNNode(geometry: floor)
        floorNode.simdEulerAngles = SIMD3<Float>(-.pi / 2, 0, 0)
        floorNode.simdPosition = SIMD3<Float>(Float(center.x), 0.001, Float(center.z))
        floorNode.castsShadow = false
        scene.rootNode.addChildNode(floorNode)

        let camera = SCNCamera()
        camera.fieldOfView = 28
        camera.zNear = 0.05
        camera.zFar = 50
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = -0.2
        camera.bloomIntensity = 0
        cameraNode.camera = camera
        scene.rootNode.addChildNode(cameraNode)
    }

    /// Puts the camera on the current view and backs it off until the whole
    /// machine, floor to top, fits the frame.
    private func placeCamera() {
        let az = view.az * .pi / 180, el = view.el * .pi / 180
        let forward = SIMD3(-cos(el) * cos(az), -sin(el), -cos(el) * sin(az))
        let right = simd_normalize(simd_cross(forward, SIMD3(0, 1, 0)))
        let up = simd_cross(right, forward)
        let center = (bounds.min + bounds.max) / 2
        let tanV = tan(14 * Double.pi / 180) * 0.9 * zoom, tanH = tanV * aspect
        var distance = 0.5
        for x in [bounds.min.x, bounds.max.x] {
            for y in [0, bounds.max.y] {
                for z in [bounds.min.z, bounds.max.z] {
                    let rel = SIMD3(x, y, z) - center
                    let depth = simd_dot(rel, forward)
                    distance = max(distance,
                                   abs(simd_dot(rel, right)) / tanH - depth,
                                   abs(simd_dot(rel, up)) / tanV - depth)
                }
            }
        }
        let eye = center - forward * distance
        cameraNode.simdPosition = SIMD3<Float>(eye)
        cameraNode.simdLook(at: SIMD3<Float>(center), up: SIMD3<Float>(0, 1, 0), localFront: SIMD3<Float>(0, 0, -1))
    }

    // MARK: Shapes

    private struct Shape {
        let geometry: SCNGeometry
        let transform: simd_double4x4
    }

    private static func shape(_ part: RigPart, cache: inout [String: SCNGeometry]) -> Shape? {
        func memo(_ key: String, _ make: () -> SCNGeometry) -> SCNGeometry {
            if let hit = cache[key] { return hit }
            let made = make()
            cache[key] = made
            return made
        }
        func k(_ v: Double) -> String { String(Int((v * 1e4).rounded())) }
        let r = part.r ?? 0
        switch part.s {
        case "rbox":
            guard let size = part.size, size.count == 3, let p = part.p else { return nil }
            let chamfer = part.r ?? min(0.03, size.min()! * 0.3)
            let geometry = memo("b\(k(size[0])),\(k(size[1])),\(k(size[2])),\(k(chamfer))") {
                let box = SCNBox(width: size[0], height: size[1], length: size[2], chamferRadius: min(chamfer, size.min()! / 2))
                box.chamferSegmentCount = chamfer < 0.009 ? 1 : chamfer < 0.02 ? 2 : 3
                return box
            }
            return Shape(geometry: geometry, transform: placed(SIMD3(p), part.rot))
        case "beam":
            guard let a = part.a, let b = part.b, let w = part.w, let h = part.h else { return nil }
            let (m, len) = along(SIMD3(a), SIMD3(b))
            let chamfer = part.r ?? min(w, h) * 0.24
            let geometry = memo("b\(k(w)),\(k(len)),\(k(h)),\(k(chamfer))") {
                let box = SCNBox(width: w, height: len, length: h, chamferRadius: min(chamfer, min(w, h, len) / 2))
                box.chamferSegmentCount = chamfer < 0.009 ? 1 : 2
                return box
            }
            return Shape(geometry: geometry, transform: m)
        case "rod":
            guard let a = part.a, let b = part.b else { return nil }
            let (m, len) = along(SIMD3(a), SIMD3(b))
            let geometry = memo("c\(k(r)),\(k(len))") {
                let cylinder = SCNCylinder(radius: r, height: len)
                cylinder.radialSegmentCount = r > 0.014 ? 22 : 12
                return cylinder
            }
            return Shape(geometry: geometry, transform: m)
        case "grip":
            guard let a = part.a, let b = part.b else { return nil }
            let (m, len) = along(SIMD3(a), SIMD3(b))
            let geometry = memo("g\(k(r)),\(k(len))") {
                let capsule = SCNCapsule(capRadius: r, height: len + 2 * r)
                capsule.radialSegmentCount = 16
                capsule.capSegmentCount = 8
                return capsule
            }
            return Shape(geometry: geometry, transform: m)
        case "disc":
            guard let p = part.p, let t = part.t else { return nil }
            let geometry = memo("d\(k(r)),\(k(t))") {
                let cylinder = SCNCylinder(radius: r, height: t)
                cylinder.radialSegmentCount = r < 0.02 ? 10 : 36
                return cylinder
            }
            let rot: [Double]? = part.axis == "x" ? [0, 0, 90] : part.axis == "z" ? [90, 0, 0] : nil
            return Shape(geometry: geometry, transform: placed(SIMD3(p), rot))
        case "ball":
            guard let p = part.p else { return nil }
            let geometry = memo("s\(k(r))") {
                let sphere = SCNSphere(radius: r)
                sphere.segmentCount = 20
                return sphere
            }
            return Shape(geometry: geometry, transform: placed(SIMD3(p), nil))
        case "torus":
            guard let p = part.p, let ring = part.R else { return nil }
            let geometry = memo("t\(k(ring)),\(k(r))") {
                let torus = SCNTorus(ringRadius: ring, pipeRadius: r)
                torus.ringSegmentCount = 36
                torus.pipeSegmentCount = 10
                return torus
            }
            // SceneKit's torus rings the y axis; the rig's, like three.js's,
            // rings z. A quarter turn about x first makes them the same.
            return Shape(geometry: geometry, transform: placed(SIMD3(p), part.rot) * rotation([90, 0, 0]))
        case "tube":
            guard let pts = part.pts else { return nil }
            let path = pts.compactMap { point -> SIMD3<Double>? in
                if case .fixed(let p) = point { return p } else { return nil }
            }
            let curve = CatmullRom.sample(path, perSegment: 14).map { SIMD3<Float>($0) }
            return Shape(geometry: TubeMesh.make(path: curve, radius: Float(r), sides: 16), transform: matrix_identity_double4x4)
        default:
            return nil
        }
    }

    private static func float4x4(_ m: simd_double4x4) -> simd_float4x4 {
        simd_float4x4(columns: (SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1),
                                SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)))
    }

    /// A frame whose y axis runs from `a` to `b`, centred between them.
    private static func along(_ a: SIMD3<Double>, _ b: SIMD3<Double>) -> (simd_double4x4, Double) {
        let d = b - a, len = simd_length(d)
        let y = len > 0 ? d / len : SIMD3(0, 1, 0)
        let ref = abs(y.z) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 0, 1)
        let x = simd_normalize(simd_cross(ref, y))
        let z = simd_normalize(simd_cross(x, y))
        let mid = (a + b) / 2
        return (simd_double4x4(columns: (SIMD4(x, 0), SIMD4(y, 0), SIMD4(z, 0), SIMD4(mid, 1))), len)
    }

    /// Rotation in degrees about x, then y, then z of the parent frame — the
    /// order three.js reads an Euler triple in, which is what the rigs use.
    private static func rotation(_ deg: [Double]?) -> simd_double4x4 {
        guard let deg, deg.count == 3 else { return matrix_identity_double4x4 }
        let r = deg.map { $0 * .pi / 180 }
        let rx = simd_double4x4(simd_quatd(angle: r[0], axis: SIMD3(1, 0, 0)))
        let ry = simd_double4x4(simd_quatd(angle: r[1], axis: SIMD3(0, 1, 0)))
        let rz = simd_double4x4(simd_quatd(angle: r[2], axis: SIMD3(0, 0, 1)))
        return rx * ry * rz
    }

    private static func placed(_ p: SIMD3<Double>, _ rot: [Double]?) -> simd_double4x4 {
        var m = rotation(rot)
        m.columns.3 = SIMD4(p, 1)
        return m
    }

    // MARK: Materials

    private static func color(_ hex: String?, _ fallback: String) -> UIColor {
        let digits = (hex ?? fallback).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return .gray }
        return UIColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                       blue: CGFloat(value & 0xff) / 255, alpha: 1)
    }

    private static func pbr(_ color: UIColor, metal: Double, rough: Double, coat: Double = 0) -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = color
        m.metalness.contents = metal
        m.roughness.contents = rough
        if coat > 0 {
            m.clearCoat.contents = coat
            m.clearCoatRoughness.contents = 0.35
        }
        return m
    }

    private static let cableMaterial = pbr(color(nil, "#0d0d0f"), metal: 0.3, rough: 0.42)

    /// The rig's finish keys as SceneKit materials, matching the web engine's.
    private static func materials(_ f: RigFinish?) -> [String: SCNMaterial] {
        let shroud = pbr(color(f?.shroud, "#a9b0b8"), metal: 0.1, rough: 0.25)
        shroud.transparency = f?.shroudOpacity ?? 0.32
        shroud.blendMode = .alpha
        shroud.writesToDepthBuffer = false
        return [
            "frame": pbr(color(f?.frame, "#2a2d31"), metal: f?.metal ?? 0.2, rough: 0.46, coat: 0.3),
            "paint": pbr(color(f?.paint, "#b3121b"), metal: 0.15, rough: 0.38, coat: 0.55),
            "plastic": pbr(color(f?.plastic, "#2a2c30"), metal: 0, rough: 0.62),
            "shroud": shroud,
            "trim": pbr(color(f?.trim, "#c4c9cf"), metal: 0.9, rough: 0.26),
            "chrome": pbr(color(nil, "#eef1f4"), metal: 1, rough: 0.09),
            "plate": pbr(color(f?.plate, "#2c2e33"), metal: 0.65, rough: 0.36),
            "upholstery": pbr(color(f?.upholstery, "#18181a"), metal: 0, rough: 0.58, coat: 0.12),
            "rubber": pbr(color(nil, "#111113"), metal: 0, rough: 0.95),
            "grip": pbr(color(nil, "#1b1b1e"), metal: 0, rough: 0.85),
            "tread": pbr(color(nil, "#18191b"), metal: 0, rough: 0.96),
            "cable": cableMaterial,
            "knob": pbr(color(f?.knob, "#d4d8dd"), metal: 0.15, rough: 0.32),
            "hole": pbr(color(nil, "#040405"), metal: 0, rough: 1),
        ]
    }
}

/// A small photo studio for reflections: a dark room with soft boxes, so
/// chrome and clear-coated steel have something to catch.
enum StudioEnvironment {
    @MainActor static let image: UIImage = {
        let size = CGSize(width: 512, height: 256)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor(red: 0.118, green: 0.125, blue: 0.141, alpha: 1).setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            func box(_ rect: CGRect, _ k: CGFloat) {
                UIColor(white: min(1, k / 3.6), alpha: 1).setFill()
                ctx.cgContext.fill(rect)
            }
            box(CGRect(x: 0, y: 0, width: 512, height: 30), 3.2)      // overhead
            box(CGRect(x: 40, y: 70, width: 70, height: 110), 3.6)    // left
            box(CGRect(x: 300, y: 80, width: 60, height: 100), 1.8)   // right
            box(CGRect(x: 170, y: 100, width: 90, height: 50), 1.4)   // front
            box(CGRect(x: 420, y: 170, width: 80, height: 14), 0.8)   // low back
        }
    }()
}

/// Uniform Catmull-Rom through a list of points, as three.js samples it with
/// tension 0.5, with the end tangents extrapolated.
enum CatmullRom {
    static func sample(_ points: [SIMD3<Double>], perSegment: Int) -> [SIMD3<Double>] {
        guard points.count > 2 else { return points }
        var out: [SIMD3<Double>] = []
        let n = points.count
        for i in 0..<(n - 1) {
            let p0 = i == 0 ? 2 * points[0] - points[1] : points[i - 1]
            let p1 = points[i], p2 = points[i + 1]
            let p3 = i + 2 < n ? points[i + 2] : 2 * points[n - 1] - points[n - 2]
            let t0 = 0.5 * (p2 - p0), t1 = 0.5 * (p3 - p1)
            for s in 0..<perSegment {
                let t = Double(s) / Double(perSegment), t2 = t * t, t3 = t2 * t
                let a = 2 * t3 - 3 * t2 + 1, b = t3 - 2 * t2 + t, c = -2 * t3 + 3 * t2, d = t3 - t2
                out.append(a * p1 + b * t0 + c * p2 + d * t1)
            }
        }
        out.append(points[n - 1])
        return out
    }
}

/// A round tube swept along a path, for bent frame tubes and cables.
enum TubeMesh {
    static func make(path: [SIMD3<Float>], radius: Float, sides: Int) -> SCNGeometry {
        let path = path.enumerated().filter { i, p in i == 0 || simd_distance(p, path[i - 1]) > 1e-6 }.map(\.element)
        guard path.count > 1 else { return SCNGeometry() }
        var positions: [SIMD3<Float>] = [], normals: [SIMD3<Float>] = [], indices: [UInt32] = []
        var normal = SIMD3<Float>(0, 0, 0)
        for (i, p) in path.enumerated() {
            let next = path[min(i + 1, path.count - 1)], prev = path[max(i - 1, 0)]
            let tangent = simd_normalize(next - prev)
            if i == 0 {
                let ref: SIMD3<Float> = abs(tangent.y) < 0.9 ? [0, 1, 0] : [1, 0, 0]
                normal = simd_normalize(simd_cross(tangent, ref))
            } else {
                // Carry the previous ring's normal along, so the tube doesn't
                // twist where the path bends.
                let projected = normal - simd_dot(normal, tangent) * tangent
                if simd_length(projected) > 1e-5 { normal = simd_normalize(projected) }
            }
            let binormal = simd_cross(tangent, normal)
            for s in 0..<sides {
                let angle = Float(s) / Float(sides) * 2 * .pi
                let out = cos(angle) * normal + sin(angle) * binormal
                positions.append(p + out * radius)
                normals.append(out)
            }
        }
        for i in 0..<(path.count - 1) {
            for s in 0..<sides {
                let a = UInt32(i * sides + s), b = UInt32(i * sides + (s + 1) % sides)
                let c = a + UInt32(sides), d = b + UInt32(sides)
                indices += [a, c, b, b, c, d]
            }
        }
        let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: positions.map { SCNVector3($0) }),
                                             SCNGeometrySource(normals: normals.map { SCNVector3($0) })],
                                   elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
        return geometry
    }
}
