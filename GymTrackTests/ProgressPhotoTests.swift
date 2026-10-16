import Foundation
import SwiftData
import Testing
import UIKit
@testable import GymTrack

/// Progress photos: a file only exists while a row names it, a check-in can
/// be photos alone, deleting takes the file with the row, and the camera's
/// advice compares bodies the way the hints say.
///
/// What the export writes for photos is in `BackupExportFidelityTests`, what
/// a restore keeps in `BackupRestoreTests`, and the erase in `CoachEraseTests`.
@MainActor @Suite(.serialized)
struct ProgressPhotoTests {

    private func temporaryStore() -> ProgressPhotoStore {
        ProgressPhotoStore(directory: FileManager.default.temporaryDirectory
            .appending(path: "ProgressPhotoTests-\(UUID().uuidString)"))
    }

    private func files(in store: ProgressPhotoStore) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: store.directory.path)) ?? [])
    }

    private let jpeg = Data("not really a jpeg".utf8)

    // MARK: - The folder

    @Test func aWrittenPhotoIsNamedByItsIDAndDeletingRemovesIt() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let id = UUID()
        try store.write(jpeg, as: id)
        #expect(store.contains(id))
        #expect(files(in: store) == ["\(id.uuidString).jpg"])

        store.delete([id])
        #expect(!store.contains(id))
    }

    @Test func theSweepKeepsOnlyThePhotosNamedAndDeleteAllRemovesTheFolder() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let kept = UUID()
        let orphan = UUID()
        try store.write(jpeg, as: kept)
        try store.write(jpeg, as: orphan)
        try Data().write(to: store.directory.appending(path: "leftover.tmp"))

        store.sweep(keeping: [kept])
        #expect(files(in: store) == ["\(kept.uuidString).jpg"])

        store.deleteAll()
        #expect(!FileManager.default.fileExists(atPath: store.directory.path))
    }

    /// A photo bigger than the cap shrinks to it, keeping its shape; a smaller
    /// one is never blown up.
    @Test(arguments: [
        (CGSize(width: 1500, height: 2000), CGSize(width: 1200, height: 1600)),
        (CGSize(width: 2000, height: 1000), CGSize(width: 1600, height: 800)),
        (CGSize(width: 300, height: 400), CGSize(width: 300, height: 400)),
    ])
    func aStoredPhotoIsAtMostTheLongEdge(size: CGSize, stored: CGSize) throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let data = try #require(ProgressPhotoStore.encoded(image))
        let decoded = try #require(UIImage(data: data))
        #expect(decoded.size == stored)
    }

    // MARK: - Photos taken in the sheet

    @Test func aRetakeDeletesThePhotoItReplaces() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let pending = PendingPhotos(store: store)
        try pending.add(jpeg, pose: .side, takenAt: TestClock.reference)
        let first = try #require(pending.byPose[.side])
        try pending.add(jpeg, pose: .side, takenAt: TestClock.reference.addingTimeInterval(30))
        let second = try #require(pending.byPose[.side])

        #expect(first.id != second.id)
        #expect(!store.contains(first.id), "a replaced photo must not stay on the phone")
        #expect(store.contains(second.id))
        pending.commit()
    }

    @Test func cancellingDeletesEveryPhotoTakenInTheSheet() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let pending = PendingPhotos(store: store)
        try pending.add(jpeg, pose: .frontRelaxed, takenAt: TestClock.reference)
        try pending.add(jpeg, pose: .back, takenAt: TestClock.reference)

        pending.discard()
        #expect(pending.isEmpty)
        #expect(files(in: store).isEmpty)
    }

    /// The sheet swiped away, or the app taking it down any other way, ends
    /// the same as Cancel.
    @Test func photosTheSheetNeverSavedGoWithTheSheet() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        var pending: PendingPhotos? = PendingPhotos(store: store)
        try pending?.add(jpeg, pose: .frontLatSpread, takenAt: TestClock.reference)
        #expect(files(in: store).count == 1)

        pending = nil
        #expect(files(in: store).isEmpty)
    }

    @Test func savedPhotosOutliveTheSheet() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        var pending: PendingPhotos? = PendingPhotos(store: store)
        try pending?.add(jpeg, pose: .side, takenAt: TestClock.reference)
        let id = try #require(pending?.byPose[.side]?.id)

        pending?.commit()
        pending?.discard()
        pending = nil
        #expect(store.contains(id))
    }

    // MARK: - Check-ins

    @Test func aCheckInCanBePhotosAloneAndNothingAtAllIsNotSaved() throws {
        let context = try TestStore.context()
        let photo = PendingPhoto(id: UUID(), pose: .back, takenAt: TestClock.reference)

        #expect(try CheckInRecords.record([:], photos: [], on: TestClock.reference, context: context) == nil)
        let check = try #require(try CheckInRecords.record([:], photos: [photo], on: TestClock.reference,
                                                           context: context))
        #expect(!check.hasAnyPart)
        #expect(check.hasAnything)

        let stored = try ModelContext(context.container).fetch(FetchDescriptor<ProgressPhoto>())
        #expect(stored.map(\.id) == [photo.id])
        #expect(stored.first?.pose == .back)
        #expect(stored.first?.takenAt == TestClock.reference)
        #expect(stored.first?.checkIn?.id == check.id)
    }

    /// The check-in's date is the one picked in the sheet; the photo keeps the
    /// moment it was actually taken.
    @Test func aBackdatedCheckInKeepsEachPhotosOwnTime() throws {
        let context = try TestStore.context()
        let taken = TestClock.reference
        let backdated = TestClock.calendar.date(byAdding: .day, value: -3, to: taken)!
        let photo = PendingPhoto(id: UUID(), pose: .side, takenAt: taken)
        let check = try #require(try CheckInRecords.record([.waist: 82], photos: [photo], on: backdated,
                                                           context: context))
        #expect(check.date == backdated)
        #expect(check.photos.first?.takenAt == taken)
    }

    @Test func deletingAPhotoRemovesItsFileAndKeepsACheckInThatHasGirths() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let context = try TestStore.context()
        let pending = PendingPhoto(id: UUID(), pose: .frontRelaxed, takenAt: TestClock.reference)
        try store.write(jpeg, as: pending.id)
        let check = try #require(try CheckInRecords.record([.arm: 37], photos: [pending], on: TestClock.reference,
                                                           context: context))
        let photo = try #require(check.photos.first)

        try CheckInRecords.delete(photo, context: context, store: store)

        #expect(!store.contains(pending.id))
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetchCount(FetchDescriptor<ProgressPhoto>()) == 0)
        let left = try fresh.fetch(FetchDescriptor<BodyMeasurement>())
        #expect(left.map(\.armCm) == [37])
    }

    /// A date with nothing on it is not a record.
    @Test func deletingTheLastPhotoOfAPhotoOnlyCheckInDeletesTheCheckIn() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let context = try TestStore.context()
        let front = PendingPhoto(id: UUID(), pose: .frontRelaxed, takenAt: TestClock.reference)
        let back = PendingPhoto(id: UUID(), pose: .back, takenAt: TestClock.reference)
        for photo in [front, back] { try store.write(jpeg, as: photo.id) }
        let check = try #require(try CheckInRecords.record([:], photos: [front, back], on: TestClock.reference,
                                                           context: context))

        try CheckInRecords.delete(try #require(check.photos.first { $0.id == front.id }), context: context,
                                  store: store)
        #expect(try ModelContext(context.container).fetchCount(FetchDescriptor<BodyMeasurement>()) == 1,
                "a check-in with a photo left is still a record")

        try CheckInRecords.delete(try #require(check.photos.first { $0.id == back.id }), context: context,
                                  store: store)
        let fresh = ModelContext(context.container)
        #expect(try fresh.fetchCount(FetchDescriptor<BodyMeasurement>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ProgressPhoto>()) == 0)
        #expect(files(in: store).isEmpty)
    }

    @Test func deletingACheckInDeletesItsPhotosAndTheirFiles() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let context = try TestStore.context()
        let photos = ProgressPhoto.Pose.allCases.map { PendingPhoto(id: UUID(), pose: $0, takenAt: TestClock.reference) }
        for photo in photos { try store.write(jpeg, as: photo.id) }
        let check = try #require(try CheckInRecords.record([.waist: 81], photos: photos, on: TestClock.reference,
                                                           context: context))

        try CheckInRecords.delete(check, context: context, store: store)

        let fresh = ModelContext(context.container)
        #expect(try fresh.fetchCount(FetchDescriptor<BodyMeasurement>()) == 0)
        #expect(try fresh.fetchCount(FetchDescriptor<ProgressPhoto>()) == 0)
        #expect(files(in: store).isEmpty)
    }

    /// What a crash between a file and its row leaves is deleted at the next
    /// launch; a photo that is part of a check-in is not touched.
    @Test func theLaunchSweepDeletesOnlyFilesNoPhotoNames() throws {
        let store = temporaryStore()
        defer { store.deleteAll() }
        let context = try TestStore.context()
        let saved = PendingPhoto(id: UUID(), pose: .side, takenAt: TestClock.reference)
        let stray = UUID()
        try store.write(jpeg, as: saved.id)
        try store.write(jpeg, as: stray)
        try CheckInRecords.record([:], photos: [saved], on: TestClock.reference, context: context)

        CheckInRecords.sweepOrphans(context: context, store: store)

        #expect(store.contains(saved.id))
        #expect(!store.contains(stray))
    }

    // MARK: - Guidance

    @Test(arguments: GuidanceCase.all)
    func theHintSaysWhatToAdjust(_ example: GuidanceCase) {
        #expect(PoseGuidance.hint(current: example.current, reference: example.reference) == example.hint,
                "\(example.name)")
    }

    /// Nothing to compare with is no advice, not a guess.
    @Test func noBodyOrNoEarlierPhotoGivesNoHint() {
        #expect(PoseGuidance.hint(current: nil, reference: GuidanceCase.front) == nil)
        #expect(PoseGuidance.hint(current: GuidanceCase.front, reference: nil) == nil)
    }

    @Test func blendingEasesTheJointsAndTakesAFaceAtOnce() {
        let start = BodyFrame(neck: CGPoint(x: 0.4, y: 0.3), root: CGPoint(x: 0.4, y: 0.6), nose: nil)
        let next = BodyFrame(neck: CGPoint(x: 0.6, y: 0.3), root: CGPoint(x: 0.6, y: 0.6),
                             nose: CGPoint(x: 0.6, y: 0.2))
        let blended = start.blended(toward: next, by: 0.5)
        #expect(abs(blended.neck.x - 0.5) < 1e-9)
        #expect(abs(blended.root.x - 0.5) < 1e-9)
        #expect(blended.nose == next.nose)
        #expect(next.blended(toward: start, by: 0.5).nose == nil)
    }
}

/// One body against last time's, and the hint it should get.
struct GuidanceCase: Sendable, CustomTestStringConvertible {
    let name: String
    let reference: BodyFrame
    let current: BodyFrame
    let hint: PoseHint

    var testDescription: String { name }

    /// Facing the phone, centred, torso 0.3 of the frame tall.
    static let front = BodyFrame(neck: CGPoint(x: 0.5, y: 0.3), root: CGPoint(x: 0.5, y: 0.6),
                                 nose: CGPoint(x: 0.5, y: 0.22))
    static let back = BodyFrame(neck: CGPoint(x: 0.5, y: 0.3), root: CGPoint(x: 0.5, y: 0.6), nose: nil)
    /// In profile, nose 0.12 of the width to the left of the neck: 0.4 torsos.
    static let side = BodyFrame(neck: CGPoint(x: 0.5, y: 0.3), root: CGPoint(x: 0.5, y: 0.6),
                                nose: CGPoint(x: 0.38, y: 0.22))

    /// `frame` moved by `dx`, `dy` and scaled about its neck by `scale`.
    static func moved(_ frame: BodyFrame, dx: Double = 0, dy: Double = 0, scale: Double = 1,
                      noseDX: Double = 0) -> BodyFrame {
        func place(_ point: CGPoint) -> CGPoint {
            CGPoint(x: frame.neck.x + (point.x - frame.neck.x) * scale + dx,
                    y: frame.neck.y + (point.y - frame.neck.y) * scale + dy)
        }
        return BodyFrame(neck: place(frame.neck), root: place(frame.root),
                         nose: frame.nose.map { place(CGPoint(x: $0.x + noseDX, y: $0.y)) })
    }

    static let all: [GuidanceCase] = [
        GuidanceCase(name: "the same body is lined up", reference: front, current: front, hint: .linedUp),
        GuidanceCase(name: "small jitter is still lined up", reference: front,
                     current: moved(front, dx: 0.02, dy: -0.02, scale: 1.04), hint: .linedUp),
        GuidanceCase(name: "a bigger torso is too close", reference: front, current: moved(front, scale: 1.2),
                     hint: .stepBack),
        GuidanceCase(name: "a smaller torso is too far", reference: front, current: moved(front, scale: 0.8),
                     hint: .comeCloser),
        GuidanceCase(name: "right of last time moves left", reference: front, current: moved(front, dx: 0.1),
                     hint: .moveLeft),
        GuidanceCase(name: "left of last time moves right", reference: front, current: moved(front, dx: -0.1),
                     hint: .moveRight),
        GuidanceCase(name: "lower in the frame lowers the phone", reference: front, current: moved(front, dy: 0.1),
                     hint: .lowerPhone),
        GuidanceCase(name: "higher in the frame raises the phone", reference: front,
                     current: moved(front, dy: -0.1), hint: .raisePhone),
        GuidanceCase(name: "no face where there was one", reference: front, current: back, hint: .faceThePhone),
        GuidanceCase(name: "a face where last time showed the back", reference: back, current: front,
                     hint: .turnYourBack),
        GuidanceCase(name: "nose further right turns left", reference: front, current: moved(front, noseDX: 0.06),
                     hint: .turnLeft),
        GuidanceCase(name: "nose further left turns right", reference: front, current: moved(front, noseDX: -0.06),
                     hint: .turnRight),
        GuidanceCase(name: "the other profile faces the other way", reference: side,
                     current: moved(side, noseDX: 0.24), hint: .faceTheOtherWay),
        GuidanceCase(name: "the back is compared without a face", reference: back, current: moved(back, scale: 0.8),
                     hint: .comeCloser),
        GuidanceCase(name: "facing comes before distance", reference: front, current: moved(back, scale: 1.3),
                     hint: .faceThePhone),
        GuidanceCase(name: "distance comes before position", reference: front,
                     current: moved(front, dx: 0.1, scale: 1.2), hint: .stepBack),
    ]
}
