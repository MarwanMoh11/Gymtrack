import Foundation
import SwiftData
import UIKit

/// Where progress photos live: one JPEG per photo, named by the photo's `id`.
///
/// The folder is `Library/Application Support/ProgressPhotos`, not
/// `Documents`, because the app shares Documents with the Files app and these
/// are pictures of the lifter's body. The coach's `coach pull` copies this
/// folder by that path, so it is part of the contract in `docs/AI_COACH.md`.
///
/// Files follow the rows (`ProgressPhoto`): a file is written before its row
/// is saved, a row's file is deleted once the row's delete is saved, and
/// `sweep` deletes any file no row names. A test passes its own folder.
struct ProgressPhotoStore: Sendable {
    let directory: URL

    /// A test, unit or UI, gets a folder of its own: its store is in memory
    /// and names no photos, so the launch sweep would otherwise delete the
    /// photos of whatever install shares the simulator.
    static let shared = ProgressPhotoStore(directory: LaunchMode.isTesting
        ? FileManager.default.temporaryDirectory.appending(path: "ProgressPhotos-Testing")
        : URL.applicationSupportDirectory.appending(path: "ProgressPhotos"))

    /// The longest side of a stored photo, in pixels. Enough to judge shape
    /// and definition, and a month of four poses stays around two megabytes.
    static let longEdge: CGFloat = 1600

    func url(for id: UUID) -> URL {
        directory.appending(path: "\(id.uuidString).jpg")
    }

    func contains(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: url(for: id).path)
    }

    /// Writes `jpeg` as photo `id`. Unreadable while the phone is locked: these
    /// are only ever shown with the app open, or copied off an unlocked phone.
    func write(_ jpeg: Data, as id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try jpeg.write(to: url(for: id), options: [.atomic, .completeFileProtection])
    }

    func delete(_ ids: some Sequence<UUID>) {
        for id in ids { try? FileManager.default.removeItem(at: url(for: id)) }
    }

    /// Deletes every file in the folder except the photos in `ids`: what a
    /// crash between a file and its row left behind, and what a restore left
    /// unclaimed. Nothing else is ever kept in this folder.
    func sweep(keeping ids: Set<UUID>) {
        let kept = Set(ids.map { url(for: $0).lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where !kept.contains(file.lastPathComponent) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// For "Erase all data".
    func deleteAll() {
        try? FileManager.default.removeItem(at: directory)
    }

    /// The photo as a JPEG at most `longEdge` on its long side, drawn afresh so
    /// the camera's orientation is baked in and none of its metadata (place,
    /// device, time) comes along.
    static func encoded(_ image: UIImage, longEdge: CGFloat = longEdge) -> Data? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let scale = min(1, longEdge / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let drawn = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return drawn.jpegData(compressionQuality: 0.8)
    }
}

/// A photo taken in the check-in sheet that has not been saved with a
/// check-in yet. Its file is already on disk.
struct PendingPhoto: Identifiable, Equatable {
    let id: UUID
    let pose: ProgressPhoto.Pose
    let takenAt: Date
}

/// The photos taken in one check-in sheet, at most one per pose.
///
/// Whatever was not saved with a check-in is deleted: a retake deletes the
/// photo it replaces, Cancel deletes them all, and so does this object going
/// away with the sheet however it was closed. A photo nobody kept is not a
/// record, and must not sit on the phone where the coach would pull it.
@Observable
final class PendingPhotos {
    private(set) var byPose: [ProgressPhoto.Pose: PendingPhoto] = [:]
    @ObservationIgnored let store: ProgressPhotoStore
    @ObservationIgnored private var committed = false

    init(store: ProgressPhotoStore = .shared) {
        self.store = store
    }

    var all: [PendingPhoto] {
        ProgressPhoto.Pose.allCases.compactMap { byPose[$0] }
    }

    var isEmpty: Bool { byPose.isEmpty }

    /// Stores `jpeg` as the photo for `pose`, replacing and deleting any taken
    /// for that pose earlier in this sheet.
    func add(_ jpeg: Data, pose: ProgressPhoto.Pose, takenAt: Date) throws {
        let photo = PendingPhoto(id: UUID(), pose: pose, takenAt: takenAt)
        try store.write(jpeg, as: photo.id)
        if let replaced = byPose[pose] { store.delete([replaced.id]) }
        byPose[pose] = photo
    }

    /// The photos now belong to a saved check-in, so nothing is deleted.
    func commit() {
        committed = true
    }

    func discard() {
        guard !committed else { return }
        store.delete(byPose.values.map(\.id))
        byPose = [:]
    }

    deinit {
        if !committed { store.delete(byPose.values.map(\.id)) }
    }
}

/// Saving and deleting check-ins, so a photo's file and its row come and go
/// together.
@MainActor
enum CheckInRecords {

    /// Saves a check-in of `parts` and `photos` dated `date`. Only measured
    /// parts arrive, and a check-in with nothing in it is not saved. The
    /// photos' files are already written; on a failed save the caller still
    /// holds them, so a second try or Cancel decides what happens to them.
    @discardableResult
    static func record(_ parts: [BodyMeasurement.Part: Double], photos: [PendingPhoto], on date: Date,
                       context: ModelContext) throws -> BodyMeasurement? {
        let check = BodyMeasurement(date: date)
        for (part, cm) in parts { check.set(cm, for: part) }
        guard check.hasAnyPart || !photos.isEmpty else { return nil }
        context.insert(check)
        for pending in photos {
            let photo = ProgressPhoto(id: pending.id, pose: pending.pose, takenAt: pending.takenAt)
            context.insert(photo)
            photo.checkIn = check
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return check
    }

    /// A hard delete of a check-in and its photos: a mis-taken check-in is not
    /// data, and a copy left anywhere would still reach the coach.
    static func delete(_ check: BodyMeasurement, context: ModelContext,
                       store: ProgressPhotoStore = .shared) throws {
        let files = check.photos.map(\.id)
        context.delete(check)
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        store.delete(files)
    }

    /// Deletes one photo. A check-in left with no girth and no other photo
    /// goes with it, since a date with nothing on it is not a record.
    static func delete(_ photo: ProgressPhoto, context: ModelContext,
                       store: ProgressPhotoStore = .shared) throws {
        let id = photo.id
        let check = photo.checkIn
        context.delete(photo)
        if let check, !check.hasAnyPart, !check.photos.contains(where: { $0.id != id }) {
            context.delete(check)
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        store.delete([id])
    }

    /// Deletes the files no saved photo names. Run at launch, which catches a
    /// crash between a file and its row, and after a restore. A store that
    /// cannot be read is left alone rather than taken to mean "no photos".
    static func sweepOrphans(context: ModelContext, store: ProgressPhotoStore = .shared) {
        guard let photos = try? context.fetch(FetchDescriptor<ProgressPhoto>()) else { return }
        store.sweep(keeping: Set(photos.map(\.id)))
    }
}
