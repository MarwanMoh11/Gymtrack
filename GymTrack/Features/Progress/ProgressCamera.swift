import AVFoundation
import SwiftUI
import UIKit

/// The progress-photo camera: the capture session, the body Vision finds in
/// the live view, and the shutter.
///
/// The preview, the frames Vision reads and the photo are all turned upright
/// and, on the front camera, mirrored, so all three show what the screen
/// shows. That is what lets the last photo, laid over the preview, line up
/// with the new one, and what lets a joint in one be compared with the other.
///
/// A simulator has no camera, so there a drawn stand-in takes its place and
/// the check-in, the comparison and their tests can still be run end to end.
@Observable @MainActor
final class ProgressCamera {
    enum Status: Equatable {
        case starting, running, denied, unavailable
    }

    private(set) var status: Status = .starting
    /// The body in the live view, eased over the last few frames, or nil when
    /// none has been found lately.
    private(set) var body: BodyFrame?
    private(set) var usesFrontCamera: Bool
    /// What the stand-in shows, in a simulator; nil on a phone.
    private(set) var standInFrame: UIImage?

    /// Made on first use: SwiftUI builds a camera each time the view that
    /// owns it is rebuilt and keeps only the first, and the others need no
    /// capture session.
    @ObservationIgnored lazy var engine = CaptureEngine()
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var misses = 0
    /// Counted across cameras, so each stand-in photo differs from the last.
    private static var standInShots = 0

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // The front camera unless the lifter chose otherwise: propped against
        // a wall, it is the one that lets them see the overlay and the hints.
        usesFrontCamera = defaults.object(forKey: SettingsKey.progressCameraFront) as? Bool ?? true
    }

    func start(pose: ProgressPhoto.Pose) async {
        #if targetEnvironment(simulator)
        standInFrame = Self.standIn(pose: pose, shot: Self.standInShots)
        status = .running
        #else
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                status = .denied
                return
            }
        default:
            status = .denied
            return
        }
        engine.onBody = { [weak self] found in
            Task { @MainActor in self?.receive(found) }
        }
        guard await engine.configure(front: usesFrontCamera) else {
            status = .unavailable
            return
        }
        engine.start()
        status = .running
        #endif
    }

    func stop() {
        engine.stop()
    }

    func flip() async {
        usesFrontCamera.toggle()
        defaults.set(usesFrontCamera, forKey: SettingsKey.progressCameraFront)
        body = nil
        #if !targetEnvironment(simulator)
        if status == .running, !(await engine.configure(front: usesFrontCamera)) {
            status = .unavailable
        }
        #endif
    }

    /// The stand-in shows the pose it is taking, in a simulator.
    func show(_ pose: ProgressPhoto.Pose) {
        #if targetEnvironment(simulator)
        standInFrame = Self.standIn(pose: pose, shot: Self.standInShots)
        #endif
    }

    func capture(pose: ProgressPhoto.Pose) async throws -> UIImage {
        #if targetEnvironment(simulator)
        Self.standInShots += 1
        let shot = Self.standIn(pose: pose, shot: Self.standInShots)
        standInFrame = shot
        return shot
        #else
        return try await engine.capture()
        #endif
    }

    /// A body missing from one frame is usually a blur, so the last one is
    /// kept for a moment rather than the hint blinking off.
    private func receive(_ found: BodyFrame?) {
        guard let found else {
            misses += 1
            if misses >= 3 { body = nil }
            return
        }
        misses = 0
        body = body.map { $0.blended(toward: found, by: 0.5) } ?? found
    }

    /// A figure on a plain ground with the pose and the shot number, so each
    /// stand-in photo is told apart from the last in the comparison.
    private static func standIn(pose: ProgressPhoto.Pose, shot: Int) -> UIImage {
        let size = CGSize(width: 1200, height: 1600)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            let hue = CGFloat(shot % 6) / 6
            UIColor(hue: hue, saturation: 0.35, brightness: 0.25, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.85, alpha: 1).setFill()
            let width: CGFloat = pose == .side ? 220 : 380 + CGFloat(shot % 3) * 30
            UIBezierPath(ovalIn: CGRect(x: 520, y: 220, width: 160, height: 190)).fill()
            UIBezierPath(roundedRect: CGRect(x: 600 - width / 2, y: 430, width: width, height: 560),
                         cornerRadius: 90).fill()
            UIBezierPath(roundedRect: CGRect(x: 470, y: 980, width: 110, height: 480), cornerRadius: 50).fill()
            UIBezierPath(roundedRect: CGRect(x: 620, y: 980, width: 110, height: 480), cornerRadius: 50).fill()
            let label = "\(pose.title)\nStand-in \(shot)" as NSString
            label.draw(in: CGRect(x: 60, y: 1460, width: 1080, height: 140), withAttributes: [
                .font: UIFont.systemFont(ofSize: 56, weight: .bold),
                .foregroundColor: UIColor.white,
            ])
        }
    }
}

/// The capture session, on a queue of its own: starting one blocks for a
/// moment, and frames arrive many times a second.
final class CaptureEngine: NSObject, @unchecked Sendable {
    let session = AVCaptureSession()
    /// Called on the engine's queue about five times a second, with the body
    /// found in the latest frame or nil.
    var onBody: (@Sendable (BodyFrame?) -> Void)?

    private let queue = DispatchQueue(label: "com.marwanmohamed.gymtrack.progress-camera")
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private var input: AVCaptureDeviceInput?
    private var lastLook: CFAbsoluteTime = 0
    private var pendingPhoto: CheckedContinuation<UIImage, Error>?

    enum CaptureError: LocalizedError {
        case busy, noImage

        var errorDescription: String? {
            switch self {
            case .busy: "A photo is already being taken."
            case .noImage: "The camera returned no picture. Try again."
            }
        }
    }

    /// Sets the session up on the front or the back camera. False when the
    /// device has no such camera.
    func configure(front: Bool) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: self.configureOnQueue(front: front)) }
        }
    }

    func start() {
        queue.async { if !self.session.isRunning { self.session.startRunning() } }
    }

    func stop() {
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }

    func capture() async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.pendingPhoto == nil else {
                    continuation.resume(throwing: CaptureError.busy)
                    return
                }
                self.pendingPhoto = continuation
                self.photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
            }
        }
    }

    private func configureOnQueue(front: Bool) -> Bool {
        let position: AVCaptureDevice.Position = front ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
              let newInput = try? AVCaptureDeviceInput(device: device) else { return false }

        session.beginConfiguration()
        session.sessionPreset = .photo
        if let input { session.removeInput(input) }
        guard session.canAddInput(newInput) else {
            if let input { session.addInput(input) }
            session.commitConfiguration()
            return false
        }
        session.addInput(newInput)
        input = newInput
        if !session.outputs.contains(photoOutput), session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        if !session.outputs.contains(videoOutput), session.canAddOutput(videoOutput) {
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.setSampleBufferDelegate(self, queue: queue)
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()

        // Upright, and mirrored on the front camera as its preview is, so the
        // photo and the frames Vision reads are the picture on the screen.
        for connection in [photoOutput.connection(with: .video), videoOutput.connection(with: .video)] {
            guard let connection else { continue }
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = front
            }
        }
        return true
    }
}

extension CaptureEngine: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        let now = CFAbsoluteTimeGetCurrent()
        guard now - lastLook >= 0.2, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastLook = now
        onBody?(BodyFrame.detect(in: buffer))
    }
}

extension CaptureEngine: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto,
                     error: Error?) {
        let result: Result<UIImage, Error>
        if let error {
            result = .failure(error)
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            result = .success(image)
        } else {
            result = .failure(CaptureError.noImage)
        }
        queue.async {
            self.pendingPhoto?.resume(with: result)
            self.pendingPhoto = nil
        }
    }
}

/// The live preview, upright, filling a 3:4 frame exactly as the photo will.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            // The connection exists only once the session has an input, which
            // can be after this view first appears.
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}
