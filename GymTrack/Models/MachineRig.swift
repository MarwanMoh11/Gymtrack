import Foundation
import simd

/// One machine model the app can draw and set up: what it is, what on it
/// adjusts, and the parts it is drawn from.
///
/// Rigs are data, not code, so a new brand or model is a new entry in
/// `machines.json` and nothing else. Lengths are metres; x points the way the
/// lifter faces, y is up and z runs across the machine.
struct MachineRig: Codable, Identifiable, Hashable, Sendable {
    let id: String
    let brand: String
    /// The maker's own name for the model, as printed on the machine.
    let model: String
    /// The maker's catalogue code, where one is known.
    let code: String?
    /// What the machine is, in plain words: "Horizontal bench press".
    let name: String
    let kind: String
    let finish: RigFinish?
    let view: RigView
    let adjustments: [RigAdjustment]
    /// Named parts of a machine that serves more than one exercise, each
    /// listing the adjustments that belong to it. Absent on a single station.
    let stations: [RigStation]?
    let groups: [RigGroup]?
    let parts: [RigPart]
    /// Catalog IDs of the movements this machine is built for. Any machine can
    /// still be chosen for any exercise; these are the ones offered first.
    let exercises: [String]

    func adjustment(_ id: String) -> RigAdjustment? { adjustments.first { $0.id == id } }

    /// "Panatta Super Horizontal Bench Press".
    var title: String { "\(brand) \(model)" }

    static func == (lhs: MachineRig, rhs: MachineRig) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Colours and metalness the machine is finished in. Every key is optional;
/// the renderer has a neutral default for each.
struct RigFinish: Codable, Sendable {
    var frame: String?
    var metal: Double?
    var paint: String?
    var upholstery: String?
    var plate: String?
    var plastic: String?
    var trim: String?
    var knob: String?
    var shroud: String?
    var shroudOpacity: Double?
}

/// A camera direction in degrees: azimuth 0 looks from +x, 90 from +z.
struct RigView: Codable, Sendable, Equatable {
    let az: Double
    let el: Double
}

/// One thing on the machine that the lifter sets: a numbered row of holes, or
/// a choice between named options.
struct RigAdjustment: Codable, Sendable, Identifiable, Equatable {
    let id: String
    let name: String
    let short: String?
    /// How many numbered positions it has, for a pin row. Nil for a choice.
    let positions: Int?
    /// The named options, for a choice. Nil for a pin row.
    let options: [String]?
    /// The position the model is drawn in when nothing has been saved. A
    /// drawing default, never shown as the lifter's setting.
    let value: Int
    /// The position the parts were modelled at; drives move relative to it.
    let base: Int?
    /// Where to look from while this adjustment is being set.
    let view: RigView?

    var label: String { short ?? name }

    /// Every value a lifter can choose: 1...positions for a pin row, the
    /// option indices for a choice.
    var range: ClosedRange<Int> {
        if let options { return 0...max(0, options.count - 1) }
        return 1...max(1, positions ?? 1)
    }

    /// "4" for a pin row, the option's name for a choice.
    func display(_ value: Int) -> String {
        if let options { return options.indices.contains(value) ? options[value] : "\(value)" }
        return "\(value)"
    }
}

struct RigStation: Codable, Sendable, Equatable {
    let name: String
    let adjustments: [String]
}

/// A set of parts that moves together when an adjustment changes, about its
/// own pivot. Groups can nest.
struct RigGroup: Codable, Sendable {
    let id: String
    let pivot: [Double]
    let drive: RigDrive?
    let parent: String?
}

/// How far a group moves per step of its adjustment: `t` translates in metres,
/// `r` rotates in degrees about x, y and z.
struct RigDrive: Codable, Sendable {
    let adj: String
    let t: [Double]?
    let r: [Double]?
}

/// One primitive of the drawing. Which fields are present depends on `s`:
/// `rbox` (size, p, rot, r), `beam`/`rod`/`grip` (a, b and w/h or r), `disc`
/// (p, r, t, axis), `ball` (p, r), `torus` (p, R, r, rot), `tube` and `cable`
/// (pts, r).
struct RigPart: Codable, Sendable {
    let s: String
    var p: [Double]?
    var size: [Double]?
    var rot: [Double]?
    var r: Double?
    var R: Double?
    var a: [Double]?
    var b: [Double]?
    var w: Double?
    var h: Double?
    var t: Double?
    var axis: String?
    var pts: [RigPoint]?
    /// Material key: frame, paint, plastic, shroud, trim, chrome, plate,
    /// upholstery, rubber, grip, tread, cable, knob or hole.
    var m: String?
    /// The group the part moves with.
    var g: String?
    /// The adjustment that lights this part up while it is being set.
    var hl: String?
    /// Drawn only while these adjustments hold these option indices.
    var opt: [String: Int]?
}

/// A point on a tube or cable: fixed in the machine's space, or riding on a
/// group, so a cable follows the carriage it hangs from.
enum RigPoint: Codable, Sendable {
    case fixed(SIMD3<Double>)
    case attached(group: String, SIMD3<Double>)

    private struct Attached: Codable { let g: String; let p: [Double] }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let xyz = try? container.decode([Double].self) {
            self = .fixed(SIMD3(xyz))
        } else {
            let attached = try container.decode(Attached.self)
            self = .attached(group: attached.g, SIMD3(attached.p))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .fixed(let p): try container.encode([p.x, p.y, p.z])
        case .attached(let g, let p): try container.encode(Attached(g: g, p: [p.x, p.y, p.z]))
        }
    }
}

extension SIMD3 where Scalar == Double {
    /// A three-number array from the rig file; anything shorter pads with zero
    /// rather than trapping on a hand-edited entry.
    init(_ xyz: [Double]) {
        self.init(xyz.count > 0 ? xyz[0] : 0, xyz.count > 1 ? xyz[1] : 0, xyz.count > 2 ? xyz[2] : 0)
    }
}

/// The bundled machine models.
enum MachineCatalog {
    static let all: [MachineRig] = load(Bundle.main)

    static func load(_ bundle: Bundle) -> [MachineRig] {
        guard let url = bundle.url(forResource: "machines", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rigs = try? JSONDecoder().decode([MachineRig].self, from: data) else {
            assertionFailure("Missing or unreadable machines.json")
            return []
        }
        return rigs
    }

    static func rig(_ id: String) -> MachineRig? { all.first { $0.id == id } }

    /// Machines built for this movement, in catalogue order.
    static func suited(to catalogID: String) -> [MachineRig] {
        let canonical = ExerciseCatalog.canonicalID(for: catalogID)
        return all.filter { rig in rig.exercises.contains { ExerciseCatalog.canonicalID(for: $0) == canonical } }
    }

    /// Whether this exercise is done on a machine at all, so the logger offers
    /// a setup only where there is something to set.
    static func offersSetup(for exercise: CatalogExercise) -> Bool {
        !suited(to: exercise.id).isEmpty
            || exercise.equipment.contains("Machine") || exercise.equipment.contains("Cable")
    }
}

/// What the lifter set on a machine: adjustment ID to position (1-based) or
/// option index. Only adjustments the lifter has actually set have a key.
struct MachineSettings: Equatable, Sendable {
    var values: [String: Int]

    init(_ values: [String: Int] = [:]) { self.values = values }

    /// Reads the stored JSON; anything unreadable is treated as nothing set.
    init(raw: String?) {
        guard let raw, let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String: Int].self, from: data) else {
            self.values = [:]
            return
        }
        self.values = values
    }

    var isEmpty: Bool { values.isEmpty }

    /// Sorted keys, so the same settings always store as the same string.
    var raw: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return (try? encoder.encode(values)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    subscript(_ id: String) -> Int? { values[id] }

    /// Drops what this rig doesn't have or can't hold, so a value from an older
    /// model file or a hand-edited backup never reaches the screen as fact.
    func valid(for rig: MachineRig) -> MachineSettings {
        MachineSettings(values.filter { id, value in rig.adjustment(id)?.range.contains(value) ?? false })
    }

    /// "Stop 2 · Grip Neutral", in the rig's own order.
    func summary(for rig: MachineRig) -> String {
        rig.adjustments.compactMap { a in values[a.id].map { "\(a.label) \(a.display($0))" } }
            .joined(separator: " · ")
    }
}
