import CoreGraphics
import CoreVideo
import Vision

/// The few points of a body that the camera's advice compares, in the picture
/// as it is shown: x from the left edge and y from the top, each a fraction of
/// the 3:4 frame. The preview, the frames Vision reads and the stored photo
/// are all upright and mirrored the same way, so a point means the same spot
/// in all three.
///
/// Worked out live and never stored: a body found in a photo is a guess about
/// the photo, not a measurement of the lifter.
struct BodyFrame: Equatable, Sendable {
    var neck: CGPoint
    /// The centre of the hips.
    var root: CGPoint
    /// Nil when no face is seen, as from behind.
    var nose: CGPoint?

    /// Neck to hips, which stays in view in every pose and shrinks as the
    /// lifter steps away, so it stands in for distance.
    var torso: Double { hypot(root.x - neck.x, root.y - neck.y) }

    /// Eases toward `next` by `weight`, so a hint doesn't flicker as the
    /// joints jitter from one frame to the next. A face that appears or goes
    /// is taken at once: it is the difference between facing and not.
    func blended(toward next: BodyFrame, by weight: Double) -> BodyFrame {
        func mix(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
            CGPoint(x: a.x + (b.x - a.x) * weight, y: a.y + (b.y - a.y) * weight)
        }
        let nose: CGPoint? = switch (self.nose, next.nose) {
        case (.some(let a), .some(let b)): mix(a, b)
        default: next.nose
        }
        return BodyFrame(neck: mix(neck, next.neck), root: mix(root, next.root), nose: nose)
    }
}

/// One thing to adjust before the photo, or that it already matches.
enum PoseHint: Equatable, CaseIterable, Sendable {
    case faceThePhone, turnYourBack, faceTheOtherWay, turnLeft, turnRight
    case stepBack, comeCloser, moveLeft, moveRight, raisePhone, lowerPhone
    case linedUp

    /// Left and right are the screen's. With the front camera the preview is
    /// a mirror, so they are the lifter's own left and right.
    var text: String {
        switch self {
        case .faceThePhone: "Face the phone"
        case .turnYourBack: "Turn your back to the phone"
        case .faceTheOtherWay: "Face the other way"
        case .turnLeft: "Turn a little left"
        case .turnRight: "Turn a little right"
        case .stepBack: "Step back"
        case .comeCloser: "Come closer"
        case .moveLeft: "Move left"
        case .moveRight: "Move right"
        case .raisePhone: "Raise the phone"
        case .lowerPhone: "Lower the phone"
        case .linedUp: "Lined up with last time"
        }
    }

    var symbol: String {
        switch self {
        case .faceThePhone: "person.fill"
        case .turnYourBack: "arrow.uturn.backward"
        case .faceTheOtherWay: "arrow.left.arrow.right"
        case .turnLeft: "arrow.turn.up.left"
        case .turnRight: "arrow.turn.up.right"
        case .stepBack: "minus.magnifyingglass"
        case .comeCloser: "plus.magnifyingglass"
        case .moveLeft: "arrow.left"
        case .moveRight: "arrow.right"
        case .raisePhone: "arrow.up"
        case .lowerPhone: "arrow.down"
        case .linedUp: "checkmark"
        }
    }
}

/// How the body in the live view differs from the last photo of the same pose.
///
/// Advice only: nothing here can hold the shutter back, and nothing it works
/// out is kept. One hint at a time, the one that changes the picture most
/// first: which way the lifter faces, then distance, then side to side, then
/// the phone's height. Each is checked once the ones before it are close
/// enough, because a body too near also sits too high and too far off centre.
enum PoseGuidance {
    /// How far the torso's length may differ, as a fraction of last time's.
    static let distanceTolerance = 0.08
    /// How far the hips may sit from last time's, as a fraction of the width.
    static let shiftTolerance = 0.05
    /// How far the neck may sit from last time's, as a fraction of the height.
    static let heightTolerance = 0.05
    /// How far the nose may sit from last time's, beside the neck, in torso lengths.
    static let turnTolerance = 0.12
    /// A nose this far beside the neck, in torso lengths, is a side view.
    static let sideView = 0.25

    /// Nil when there is nothing to compare: no earlier photo with a body in
    /// it, or no body in view.
    static func hint(current: BodyFrame?, reference: BodyFrame?) -> PoseHint? {
        guard let current, let reference, current.torso > 0, reference.torso > 0 else { return nil }

        switch (reference.nose, current.nose) {
        case (.some, nil):
            return .faceThePhone
        case (nil, .some):
            return .turnYourBack
        case (.some(let then), .some(let now)):
            let was = (then.x - reference.neck.x) / reference.torso
            let isNow = (now.x - current.neck.x) / current.torso
            if abs(was) > sideView, abs(isNow) > sideView, (was > 0) != (isNow > 0) {
                return .faceTheOtherWay
            }
            // The nose further right than last time: turning left brings it back.
            if isNow - was > turnTolerance { return .turnLeft }
            if was - isNow > turnTolerance { return .turnRight }
        case (nil, nil):
            break
        }

        let scale = current.torso / reference.torso
        if scale > 1 + distanceTolerance { return .stepBack }
        if scale < 1 - distanceTolerance { return .comeCloser }

        let shift = current.root.x - reference.root.x
        if shift > shiftTolerance { return .moveLeft }
        if shift < -shiftTolerance { return .moveRight }

        // A phone held higher than last time shows the body lower in the frame.
        let drop = current.neck.y - reference.neck.y
        if drop > heightTolerance { return .lowerPhone }
        if drop < -heightTolerance { return .raisePhone }

        return .linedUp
    }
}

// MARK: - Vision

extension BodyFrame {
    /// Joints Vision is less sure of than this are treated as not seen.
    static let minimumConfidence: Float = 0.3

    init?(_ observation: VNHumanBodyPoseObservation) {
        func point(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let found = try? observation.recognizedPoint(joint),
                  found.confidence >= Self.minimumConfidence else { return nil }
            // Vision measures up from the bottom; the frame measures down from the top.
            return CGPoint(x: found.location.x, y: 1 - found.location.y)
        }
        guard let neck = point(.neck), let root = point(.root) else { return nil }
        self.init(neck: neck, root: root, nose: point(.nose))
        guard torso > 0.02 else { return nil }
    }

    /// The largest body in view, which is the lifter rather than someone
    /// walking past behind them.
    static func largest(in observations: [VNHumanBodyPoseObservation]) -> BodyFrame? {
        observations.compactMap(BodyFrame.init).max { $0.torso < $1.torso }
    }

    /// The body in an upright image, such as a stored photo.
    static func detect(in image: CGImage) -> BodyFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
        return largest(in: request.results ?? [])
    }

    /// The body in a live frame, which the camera has already turned upright.
    static func detect(in buffer: CVPixelBuffer) -> BodyFrame? {
        let request = VNDetectHumanBodyPoseRequest()
        try? VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
        return largest(in: request.results ?? [])
    }
}
