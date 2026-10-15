import SceneKit
import SwiftUI
import UIKit

/// The machine in 3D: drag to turn it, and it moves its parts to the settings
/// it is given, lighting the one being set.
struct MachineModelView: UIViewRepresentable {
    let rig: MachineRig
    var settings: MachineSettings
    var focus: String?

    func makeUIView(context: Context) -> MachineSCNView {
        MachineSCNView(machine: MachineScene(rig: rig, settings: settings))
    }

    func updateUIView(_ view: MachineSCNView, context: Context) {
        if view.machine.rig.id != rig.id {
            view.swap(to: MachineScene(rig: rig, settings: settings))
        }
        view.show(settings, focus: focus)
    }
}

/// Draws only while something is settling: a part moving to a new hole, a
/// highlight fading, the camera turning. Otherwise it is a still picture.
final class MachineSCNView: SCNView {
    private(set) var machine: MachineScene
    private var link: CADisplayLink?
    private var shownSettings: MachineSettings?
    private var shownFocus: String?

    init(machine: MachineScene) {
        self.machine = machine
        super.init(frame: .zero, options: nil)
        backgroundColor = .clear
        antialiasingMode = .multisampling4X
        rendersContinuously = false
        attach()
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        addGestureRecognizer(pan)
        isAccessibilityElement = true
        accessibilityTraits = .image
        accessibilityIdentifier = "machine.model"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func attach() {
        scene = machine.scene
        pointOfView = machine.cameraNode
        accessibilityLabel = "\(machine.rig.title), drag to turn"
    }

    func swap(to machine: MachineScene) {
        self.machine = machine
        shownSettings = nil
        shownFocus = nil
        attach()
        setNeedsLayout()
    }

    func show(_ settings: MachineSettings, focus: String?) {
        guard settings != shownSettings || focus != shownFocus else { return }
        let animated = shownSettings != nil && !UIAccessibility.isReduceMotionEnabled
        for a in machine.rig.adjustments {
            machine.set(a.id, to: settings[a.id] ?? a.value, animated: animated)
        }
        machine.focus(focus)
        shownSettings = settings
        shownFocus = focus
        if animated { run() } else { machine.step(10) }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.height > 0 else { return }
        machine.resize(aspect: bounds.width / bounds.height)
    }

    @objc private func dragged(_ pan: UIPanGestureRecognizer) {
        let d = pan.translation(in: self)
        pan.setTranslation(.zero, in: self)
        machine.turn(by: Double(d.x) * 0.45, tilt: Double(d.y) * 0.2)
        setNeedsDisplay()
    }

    private func run() {
        guard link == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
        isPlaying = true
    }

    @objc private func tick(_ link: CADisplayLink) {
        let dt = min(0.05, max(0.001, link.targetTimestamp - link.timestamp))
        if !machine.step(dt) {
            link.invalidate()
            self.link = nil
            isPlaying = false
        }
    }

    override func removeFromSuperview() {
        link?.invalidate()
        link = nil
        super.removeFromSuperview()
    }
}

/// Still pictures of each machine for lists, drawn once per launch.
@MainActor
enum MachineSnapshots {
    private static var cache: [String: UIImage] = [:]

    static func image(for rig: MachineRig, side: CGFloat = 120) -> UIImage? {
        let key = "\(rig.id)@\(Int(side))"
        if let hit = cache[key] { return hit }
        guard let device = MTLCreateSystemDefaultDevice() else { return nil }
        let machine = MachineScene(rig: rig, zoom: 1.15)
        machine.resize(aspect: 1)
        let renderer = SCNRenderer(device: device, options: nil)
        renderer.scene = machine.scene
        renderer.pointOfView = machine.cameraNode
        let scale = UIScreen.main.scale
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: side * scale, height: side * scale),
                                      antialiasingMode: .multisampling4X)
        cache[key] = image
        return image
    }
}

/// A machine's still picture on a dark tile.
struct MachineThumbnail: View {
    let rig: MachineRig
    var size: CGFloat = 56
    @State private var image: UIImage?

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
            .fill(Theme.well)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFit().padding(size * 0.04)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            }
            .frame(width: size, height: size)
            .accessibilityHidden(true)
            .task(id: rig.id) { image = MachineSnapshots.image(for: rig, side: max(120, size * 2)) }
    }
}
