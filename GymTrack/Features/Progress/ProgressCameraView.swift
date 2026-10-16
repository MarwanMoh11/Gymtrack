import SwiftUI
import UIKit

/// The camera for a check-in's progress photos.
///
/// The last photo of the same pose sits over the preview, faint, so the new
/// one can be lined up with it, and a hint above says what to adjust. The
/// hint is advice: the shutter always works, whatever it says.
///
/// After each photo the camera moves on to the next pose not yet taken in
/// this check-in, and closes once all four are, so a full set is four presses
/// of the shutter. A pose can be picked again from the strip to retake it.
struct ProgressCameraView: View {
    let pending: PendingPhotos
    /// The newest saved photo of each pose, to line the new one up with.
    let references: [ProgressPhoto.Pose: URL]

    @Environment(\.dismiss) private var dismiss
    @State private var pose: ProgressPhoto.Pose
    @State private var camera = ProgressCamera()
    @State private var referenceImages: [ProgressPhoto.Pose: UIImage] = [:]
    /// The body Vision found in each reference photo. A pose whose photo has
    /// no body Vision can find gets the overlay and no hints.
    @State private var referenceBodies: [ProgressPhoto.Pose: BodyFrame] = [:]
    @State private var showsOverlay = true
    @AppStorage(SettingsKey.progressCameraTimer) private var usesTimer = false
    @State private var countdown: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var isCapturing = false
    @State private var captureError: String?

    /// The seconds the timer gives the lifter to get from the phone into the pose.
    private static let timerSeconds = 10

    init(startingAt pose: ProgressPhoto.Pose, pending: PendingPhotos, references: [ProgressPhoto.Pose: URL]) {
        self.pending = pending
        self.references = references
        _pose = State(initialValue: pose)
    }

    var body: some View {
        VStack(spacing: 14) {
            topBar
            frame
            poseStrip
            controls
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.ignoresSafeArea())
        .task { await camera.start(pose: pose) }
        .task(id: pose) { await loadReference(for: pose) }
        .onChange(of: pose) { _, newPose in camera.show(newPose) }
        .onDisappear {
            countdownTask?.cancel()
            camera.stop()
        }
        .alert("Couldn't take the photo", isPresented: Binding(
            get: { captureError != nil },
            set: { if !$0 { captureError = nil } }
        )) {
            Button("OK") { captureError = nil }
        } message: {
            Text(captureError ?? "Please try again.")
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Close camera")
            .accessibilityIdentifier("progressCamera.close")
            Spacer()
            Text(pose.title)
                .font(Theme.rounded(17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("progressCamera.pose")
            Spacer()
            Button {
                showsOverlay.toggle()
            } label: {
                Image(systemName: showsOverlay ? "square.on.square.dashed" : "square.dashed")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            // Kept in the layout so the title stays centred, and shown only
            // when there is a last photo to hide.
            .opacity(referenceImages[pose] == nil ? 0 : 1)
            .disabled(referenceImages[pose] == nil)
            .accessibilityHidden(referenceImages[pose] == nil)
            .accessibilityLabel(showsOverlay ? "Hide last photo" : "Show last photo")
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var frame: some View {
        ZStack(alignment: .top) {
            preview
            if showsOverlay, let reference = referenceImages[pose] {
                Image(uiImage: reference)
                    .resizable()
                    .aspectRatio(3 / 4, contentMode: .fill)
                    .opacity(0.35)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            if let countdown {
                Text("\(countdown)")
                    .font(Theme.number(120))
                    .foregroundStyle(Theme.textPrimary)
                    .shadow(radius: 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel("Photo in \(countdown) seconds")
            }
            caption
                .padding(12)
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var preview: some View {
        switch camera.status {
        case .running:
            if let still = camera.standInFrame {
                Image(uiImage: still)
                    .resizable()
                    .aspectRatio(3 / 4, contentMode: .fill)
            } else {
                CameraPreview(session: camera.engine.session)
            }
        case .starting:
            Theme.surface
        case .denied:
            unavailableMessage("GymTrack can't use the camera. Turn it on in Settings to take progress photos.",
                               offersSettings: true)
        case .unavailable:
            unavailableMessage("This camera isn't available on this device.", offersSettings: false)
        }
    }

    private func unavailableMessage(_ text: String, offersSettings: Bool) -> some View {
        VStack(spacing: 14) {
            Text(text)
                .font(Theme.rounded(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if offersSettings, let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { UIApplication.shared.open(url) }
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.surface)
    }

    /// The hint, large enough to read from where the lifter stands. With no
    /// earlier photo of this pose there is nothing to line up with, and that
    /// is said once in small print instead.
    @ViewBuilder
    private var caption: some View {
        if camera.status == .running {
            if referenceImages[pose] == nil, references[pose] == nil {
                Text("First \(pose.title.lowercased()) photo. Later ones line up with it.")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.black.opacity(0.55), in: Capsule())
            } else if let hint = PoseGuidance.hint(current: camera.body, reference: referenceBodies[pose]) {
                hintPill(hint)
            }
        }
    }

    private func hintPill(_ hint: PoseHint) -> some View {
        Label(hint.text, systemImage: hint.symbol)
            .font(Theme.rounded(24, weight: .bold))
            .foregroundStyle(hint == .linedUp ? Color.black : Theme.textPrimary)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .background(hint == .linedUp ? Theme.accent : Color.black.opacity(0.6), in: Capsule())
            .accessibilityIdentifier("progressCamera.hint")
    }

    private var poseStrip: some View {
        HStack(spacing: 8) {
            ForEach(ProgressPhoto.Pose.allCases) { option in
                Button {
                    Haptics.tick()
                    pose = option
                } label: {
                    HStack(spacing: 4) {
                        if pending.byPose[option] != nil {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                        }
                        Text(option.shortTitle)
                            .font(Theme.rounded(12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(option == pose ? Color.black : Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(option == pose ? Theme.accent : Theme.surfaceRaised, in: Capsule())
                }
                .accessibilityAddTraits(option == pose ? .isSelected : [])
                .accessibilityValue(pending.byPose[option] != nil ? "Taken" : "")
            }
        }
    }

    private var controls: some View {
        HStack {
            Button {
                usesTimer.toggle()
            } label: {
                Label(usesTimer ? "\(Self.timerSeconds)s" : "Off", systemImage: "timer")
                    .font(Theme.rounded(14, weight: .semibold))
                    .foregroundStyle(usesTimer ? Theme.accent : Theme.textSecondary)
                    .frame(width: 80, height: 44)
            }
            .accessibilityLabel(usesTimer ? "Timer on, \(Self.timerSeconds) seconds" : "Timer off")
            Spacer()
            shutter
            Spacer()
            Button {
                Task { await camera.flip() }
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 80, height: 44)
            }
            .disabled(countdown != nil || isCapturing)
            .accessibilityLabel(camera.usesFrontCamera ? "Use back camera" : "Use front camera")
        }
    }

    private var shutter: some View {
        Button {
            shutterPressed()
        } label: {
            ZStack {
                Circle().strokeBorder(Theme.textPrimary, lineWidth: 4)
                    .frame(width: 74, height: 74)
                Circle().fill(countdown == nil ? Theme.textPrimary : Theme.negative)
                    .frame(width: 60, height: 60)
            }
        }
        .disabled(camera.status != .running || isCapturing)
        .accessibilityLabel(countdown == nil ? "Take photo" : "Cancel timer")
        .accessibilityIdentifier("progressCamera.shutter")
    }

    // MARK: - Taking the photo

    /// With the timer on, the first press starts the count and a second press
    /// during it cancels.
    private func shutterPressed() {
        if countdownTask != nil {
            countdownTask?.cancel()
            countdownTask = nil
            countdown = nil
            return
        }
        guard usesTimer else {
            Task { await take() }
            return
        }
        Haptics.tick()
        countdownTask = Task {
            for remaining in stride(from: Self.timerSeconds, to: 0, by: -1) {
                countdown = remaining
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
            }
            countdown = nil
            countdownTask = nil
            await take()
        }
    }

    private func take() async {
        guard !isCapturing else { return }
        isCapturing = true
        defer { isCapturing = false }
        let taken = pose
        do {
            let image = try await camera.capture(pose: taken)
            let moment = Date.now
            guard let jpeg = await Task.detached(priority: .userInitiated, operation: {
                ProgressPhotoStore.encoded(image)
            }).value else { throw CaptureEngine.CaptureError.noImage }
            try pending.add(jpeg, pose: taken, takenAt: moment)
            Haptics.success()
            advance(after: taken)
        } catch {
            captureError = error.localizedDescription
        }
    }

    /// On to the next pose not yet taken, after this one and then from the
    /// start; when every pose is taken, the camera has done its job.
    private func advance(after taken: ProgressPhoto.Pose) {
        let order = ProgressPhoto.Pose.allCases
        let start = order.firstIndex(of: taken) ?? 0
        let rotated = order[(start + 1)...] + order[..<start]
        if let next = rotated.first(where: { pending.byPose[$0] == nil }) {
            pose = next
        } else {
            dismiss()
        }
    }

    /// Loads the reference photo and finds the body in it, once per pose.
    private func loadReference(for pose: ProgressPhoto.Pose) async {
        guard referenceImages[pose] == nil, let url = references[pose] else { return }
        let loaded = await Task.detached(priority: .userInitiated) { () -> (UIImage, BodyFrame?)? in
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            return (image, image.cgImage.flatMap(BodyFrame.detect(in:)))
        }.value
        guard let loaded else { return }
        referenceImages[pose] = loaded.0
        if let body = loaded.1 { referenceBodies[pose] = body }
    }
}
