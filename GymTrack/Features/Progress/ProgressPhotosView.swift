import SwiftData
import SwiftUI
import UIKit

/// Every progress photo, a pose at a time: two dates side by side under a
/// slider, or the whole run scrubbed through in order.
///
/// A photo is deleted from the timeline. It leaves nothing behind: its file
/// goes with its row, and a check-in left with nothing else goes too.
struct ProgressPhotosSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \ProgressPhoto.takenAt) private var photos: [ProgressPhoto]

    @State private var chosenPose: ProgressPhoto.Pose?
    @State private var mode: Mode = .compare
    @State private var beforeID: UUID?
    @State private var afterID: UUID?
    @State private var position: Double = .infinity
    @State private var doomed: ProgressPhoto?
    @State private var deleteError: String?

    enum Mode: String, CaseIterable, Identifiable {
        case compare = "Compare"
        case timeline = "Timeline"
        var id: String { rawValue }
    }

    private let store = ProgressPhotoStore.shared

    /// Only poses that have a photo are offered.
    private var poses: [ProgressPhoto.Pose] {
        ProgressPhoto.Pose.allCases.filter { pose in photos.contains { $0.pose == pose } }
    }

    private var pose: ProgressPhoto.Pose? {
        if let chosenPose, poses.contains(chosenPose) { return chosenPose }
        return poses.first
    }

    /// The pose's photos, oldest first.
    private var series: [ProgressPhoto] {
        guard let pose else { return [] }
        return photos.filter { $0.pose == pose }
    }

    private var before: ProgressPhoto? {
        series.first { $0.id == beforeID } ?? series.first
    }

    private var after: ProgressPhoto? {
        series.first { $0.id == afterID } ?? series.last
    }

    /// The timeline starts on the newest photo, and stays in range as photos
    /// are deleted.
    private var timelineIndex: Int {
        guard !series.isEmpty else { return 0 }
        return min(max(Int(position.isFinite ? position : Double(series.count - 1)), 0), series.count - 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if poses.isEmpty {
                        Text("No progress photos.")
                            .font(Theme.rounded(15, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, 40)
                    } else {
                        pickers
                        switch mode {
                        case .compare: compare
                        case .timeline: timeline
                        }
                    }
                }
                .padding(16)
            }
            .gtScreenBackground()
            .navigationTitle("Progress photos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .gtSheetBackground()
        .confirmationDialog("Delete this photo?", isPresented: Binding(
            get: { doomed != nil },
            set: { if !$0 { doomed = nil } }
        ), titleVisibility: .visible) {
            Button("Delete photo", role: .destructive) { deleteDoomed() }
            Button("Cancel", role: .cancel) { doomed = nil }
        } message: {
            Text("It is removed from this iPhone and from what the coach can pull. A check-in with nothing else in it goes too.")
        }
        .alert("Couldn't delete the photo", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK") { deleteError = nil }
        } message: {
            Text(deleteError ?? "Please try again.")
        }
    }

    // MARK: - Pieces

    private var pickers: some View {
        VStack(spacing: 10) {
            Picker("Pose", selection: Binding(get: { pose ?? .frontRelaxed }, set: { newPose in
                chosenPose = newPose
                beforeID = nil
                afterID = nil
                position = .infinity
            })) {
                ForEach(poses) { Text($0.shortTitle).tag($0) }
            }
            .pickerStyle(.segmented)
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("progressPhotos.mode")
        }
    }

    @ViewBuilder
    private var compare: some View {
        if let before, let after, before.id != after.id {
            BeforeAfterSlider(before: store.url(for: before.id), after: store.url(for: after.id),
                              beforeLabel: label(before), afterLabel: label(after))
        } else if let only = after {
            PhotoImage(url: store.url(for: only.id))
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
            Text(singleCaption(only))
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        if series.count > 1, let before, let after {
            HStack(spacing: 12) {
                datePicker("Before", selection: $beforeID, current: before)
                datePicker("After", selection: $afterID, current: after)
            }
        }
    }

    private func singleCaption(_ photo: ProgressPhoto) -> String {
        guard series.count == 1 else { return "Pick two different dates to compare." }
        let pose = photo.pose?.title.lowercased() ?? "progress"
        return "One \(pose) photo so far, from \(Self.label(photo.takenAt)). The next one can be compared with it."
    }

    private func datePicker(_ title: String, selection: Binding<UUID?>, current: ProgressPhoto) -> some View {
        Menu {
            ForEach(series) { photo in
                Button(label(photo)) { selection.wrappedValue = photo.id }
            }
        } label: {
            VStack(spacing: 2) {
                Text(title.uppercased())
                    .font(Theme.eyebrow)
                    .foregroundStyle(Theme.textTertiary)
                Text(label(current))
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        }
        .accessibilityLabel("\(title) photo, \(label(current))")
    }

    @ViewBuilder
    private var timeline: some View {
        if !series.isEmpty {
            let photo = series[timelineIndex]
            PhotoImage(url: store.url(for: photo.id))
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
                .accessibilityLabel("\(photo.pose?.title ?? "Photo"), \(label(photo))")
            Text(label(photo))
                .font(Theme.rounded(17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .accessibilityIdentifier("progressPhotos.date")
            if series.count > 1 {
                Slider(value: Binding(get: { Double(timelineIndex) }, set: { position = $0.rounded() }),
                       in: 0...Double(series.count - 1), step: 1)
                    .tint(Theme.accent)
                    .accessibilityLabel("Photo date")
                    .accessibilityValue(label(photo))
                    .accessibilityIdentifier("progressPhotos.scrubber")
                HStack {
                    Text(label(series[0]))
                    Spacer()
                    Text(label(series[series.count - 1]))
                }
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            }
            Button(role: .destructive) {
                doomed = photo
            } label: {
                Label("Delete this photo", systemImage: "trash")
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.negative)
            }
            .padding(.top, 4)
            .accessibilityIdentifier("progressPhotos.delete")
        }
    }

    private func deleteDoomed() {
        guard let photo = doomed else { return }
        doomed = nil
        do {
            try CheckInRecords.delete(photo, context: context)
            Haptics.tick()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    private static func label(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    /// The photo's date, with the time when another photo of the pose was
    /// taken the same day, so two dates in a comparison never read as one.
    private func label(_ photo: ProgressPhoto) -> String {
        let calendar = Calendar.current
        let sameDay = series.contains { $0.id != photo.id && calendar.isDate($0.takenAt, inSameDayAs: photo.takenAt) }
        guard sameDay else { return Self.label(photo.takenAt) }
        return photo.takenAt.formatted(.dateTime.day().month(.abbreviated).hour().minute())
    }
}

// MARK: - Before and after

/// Two photos of one pose stacked, the earlier one on the left of a divider
/// that is dragged across to wipe between them.
struct BeforeAfterSlider: View {
    let before: URL
    let after: URL
    let beforeLabel: String
    let afterLabel: String

    @State private var split: CGFloat = 0.5

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            ZStack(alignment: .topLeading) {
                PhotoImage(url: after)
                PhotoImage(url: before)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * split)
                    }
                Rectangle()
                    .fill(Theme.textPrimary)
                    .frame(width: 2)
                    .overlay {
                        Circle()
                            .fill(Theme.textPrimary)
                            .frame(width: 30, height: 30)
                            .overlay {
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Color.black)
                            }
                    }
                    .offset(x: width * split - 1)
                corner(beforeLabel, alignment: .topLeading)
                corner(afterLabel, alignment: .topTrailing)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                split = min(max(drag.location.x / max(width, 1), 0), 1)
            })
        }
        .aspectRatio(3 / 4, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadiusSmall, style: .continuous))
        .accessibilityElement()
        .accessibilityLabel("Before \(beforeLabel), after \(afterLabel)")
        .accessibilityValue("\(Int((split * 100).rounded())) percent before")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: split = min(split + 0.1, 1)
            case .decrement: split = max(split - 0.1, 0)
            @unknown default: break
            }
        }
        .accessibilityIdentifier("progressPhotos.slider")
    }

    private func corner(_ text: String, alignment: Alignment) -> some View {
        Text(text)
            .font(Theme.rounded(12, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
    }
}

// MARK: - Loading

/// A stored photo, read off the main thread and filling its frame.
struct PhotoImage: View {
    let url: URL
    /// The size to decode to, for a thumbnail; nil decodes the whole photo.
    var thumbnail: CGSize?

    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Theme.surface)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: url) {
                let size = thumbnail
                image = await Task.detached(priority: .userInitiated) { () -> UIImage? in
                    guard let full = UIImage(contentsOfFile: url.path) else { return nil }
                    if let size { return full.preparingThumbnail(of: size) }
                    return full.preparingForDisplay()
                }.value
            }
    }
}
