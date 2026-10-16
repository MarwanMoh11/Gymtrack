import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// The daily check's note: read from the inbox only when this build can show
/// it, shown until the next workout, and erased with everything else.
@MainActor
@Suite(.serialized)
struct CoachDayNoteTests {

    static let cairo = TestClock.calendar(in: "Africa/Cairo")

    nonisolated static func noteJSON(day: String = "2026-10-16", format: String = CoachDayNote.format, version: Int = 1,
                         verdict: String = "A mixed back day.", watch: [String]? = ["Lat pulldown dropped."]) -> Data {
        var object: [String: Any] = ["format": format, "version": version,
                                     "id": "6F1C2A4E-1D2B-4C3D-9E8F-0A1B2C3D4E5F",
                                     "createdAt": "2026-10-16T20:00:00Z", "day": day, "verdict": verdict,
                                     "wentWell": ["Row up to 55 kg.", "  "], "nextTime": ["Start the pulldown lighter."]]
        if let watch { object["watch"] = watch }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    private func inbox(with data: Data?) throws -> (CoachInbox, CoachStore) {
        let store = CoachFixture.temporaryStore()
        store.prepare()
        if let data { try data.write(to: store.dayNoteURL) }
        return (CoachInbox(context: try TestStore.context(), store: store), store)
    }

    @Test func aPushedNoteIsReadWithItsBlankLinesLeftOut() throws {
        let (inbox, store) = try inbox(with: Self.noteJSON())
        defer { CoachFixture.discard(store) }
        let note = try #require(inbox.dayNote)
        #expect(note.verdict == "A mixed back day.")
        #expect(note.wentWellLines == ["Row up to 55 kg."])
        #expect(note.watchLines == ["Lat pulldown dropped."])
        #expect(note.nextTimeLines == ["Start the pulldown lighter."])
    }

    @Test func anAbsentPartIsEmptyNotAnError() throws {
        let (inbox, store) = try inbox(with: Self.noteJSON(watch: nil))
        defer { CoachFixture.discard(store) }
        #expect(try #require(inbox.dayNote).watchLines.isEmpty)
    }

    @Test(arguments: [
        CoachDayNoteTests.noteJSON(format: "gymtrack-coach-proposal"),
        CoachDayNoteTests.noteJSON(version: 2),
        CoachDayNoteTests.noteJSON(verdict: "  "),
        CoachDayNoteTests.noteJSON(day: "16/10/2026"),
        Data("not json".utf8),
    ])
    func aNoteThisBuildCannotShowIsNotShown(data: Data) throws {
        let (inbox, store) = try inbox(with: data)
        defer { CoachFixture.discard(store) }
        #expect(inbox.dayNote == nil)
    }

    @Test func noFileMeansNoNote() throws {
        let (inbox, store) = try inbox(with: nil)
        defer { CoachFixture.discard(store) }
        #expect(inbox.dayNote == nil)
    }

    @Test func theNextTrainedDayRetiresTheNoteButTheSmallHoursDoNot() throws {
        let note = try CoachJSON.decoded(CoachDayNote.self, from: Self.noteJSON(day: "2026-10-16"))
        let sameEvening = TestClock.at("2026-10-16T21:33:00", in: "Africa/Cairo")
        let afterMidnight = TestClock.at("2026-10-17T01:30:00", in: "Africa/Cairo")
        let nextDay = TestClock.at("2026-10-17T18:00:00", in: "Africa/Cairo")
        let dayBefore = TestClock.at("2026-10-13T20:00:00", in: "Africa/Cairo")
        #expect(note.isCurrent(trainedStarts: [dayBefore, sameEvening], calendar: Self.cairo))
        #expect(note.isCurrent(trainedStarts: [afterMidnight], calendar: Self.cairo),
                "A session before 04:00 is still the night of the note")
        #expect(!note.isCurrent(trainedStarts: [sameEvening, nextDay], calendar: Self.cairo))
    }

    @Test(arguments: [
        ("2026-10-16T22:30:00", "today's workout"),
        ("2026-10-17T02:00:00", "today's workout"),
        ("2026-10-17T09:00:00", "yesterday's workout"),
        ("2026-10-19T09:00:00", "Friday's workout"),
        ("2026-10-23T09:00:00", "your last workout"),
    ])
    func theLineNamesTheWorkoutByHowLongAgoItWas(now: String, expected: String) throws {
        let note = try CoachJSON.decoded(CoachDayNote.self, from: Self.noteJSON(day: "2026-10-16"))
        #expect(note.workoutName(now: TestClock.at(now, in: "Africa/Cairo"), calendar: Self.cairo) == expected)
    }

    @Test func eraseRemovesTheNote() throws {
        let (inbox, store) = try inbox(with: Self.noteJSON())
        defer { CoachFixture.discard(store) }
        #expect(inbox.dayNote != nil)
        inbox.erase()
        inbox.reload()
        #expect(inbox.dayNote == nil)
        #expect(!FileManager.default.fileExists(atPath: store.dayNoteURL.path))
    }
}
