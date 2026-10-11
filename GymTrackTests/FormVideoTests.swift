import Foundation
import SwiftData
import Testing
@testable import GymTrack

/// One parser for suggestions, pasted links and backups, and reversible
/// replacements stored under the movement's canonical ID.
@MainActor
@Suite(.serialized)
struct FormVideoTests {
    @Test(arguments: [
        ("https://www.youtube.com/watch?v=rT7DgCr-3pg", nil as Int?),
        ("https://youtu.be/rT7DgCr-3pg?si=abc", nil),
        ("https://youtu.be/rT7DgCr-3pg?t=42", 42),
        ("https://m.youtube.com/watch?v=rT7DgCr-3pg&t=1m30s", 90),
        ("youtube.com/shorts/rT7DgCr-3pg", nil),
        ("https://www.youtube.com/embed/rT7DgCr-3pg?start=15", 15),
        ("https://www.youtube-nocookie.com/embed/rT7DgCr-3pg", nil),
        ("https://www.youtube.com/live/rT7DgCr-3pg", nil),
        ("  rT7DgCr-3pg  ", nil),
        ("https://youtu.be/rT7DgCr-3pg?t=0", nil),
        ("https://music.youtube.com/watch?v=rT7DgCr-3pg&t=1h2m3s", 3723),
        ("https://youtube.com/v/rT7DgCr-3pg?t=90s", 90),
        ("https://youtu.be/rT7DgCr-3pg?t=invalid", nil),
    ])
    func parsesValidLinks(input: String, start: Int?) throws {
        let video = try #require(FormVideo(link: input))
        #expect(video.videoID == "rT7DgCr-3pg")
        #expect(video.start == start)
    }

    @Test(arguments: ["", "https://vimeo.com/123", "https://youtube.com/watch?v=short",
                      "https://www.youtube.com/playlist?list=PL123", "not a link",
                      "https://evil.com/watch?v=rT7DgCr-3pg", "https://youtube.com.evil.com/watch?v=rT7DgCr-3pg"])
    func rejectsInvalidLinks(_ input: String) {
        #expect(FormVideo(link: input) == nil)
    }

    @Test func canonicalOutputFormats() throws {
        let plain = try #require(FormVideo(link: "rT7DgCr-3pg"))
        #expect(plain.link == "https://youtu.be/rT7DgCr-3pg")
        #expect(plain.watchURL.absoluteString == "https://www.youtube.com/watch?v=rT7DgCr-3pg")
        #expect(plain.embedURL.absoluteString == "https://www.youtube-nocookie.com/embed/rT7DgCr-3pg?playsinline=1&rel=0")
        let timed = try #require(FormVideo(link: "https://youtube.com/watch?v=rT7DgCr-3pg&t=1m30s"))
        #expect(timed.link == "https://youtu.be/rT7DgCr-3pg?t=90")
        #expect(timed.watchURL.absoluteString == "https://www.youtube.com/watch?v=rT7DgCr-3pg&t=90s")
        #expect(timed.embedURL.absoluteString == "https://www.youtube-nocookie.com/embed/rT7DgCr-3pg?playsinline=1&rel=0&start=90")
    }

    @Test func bundledVideosCoverTheCatalogWithOnlyExplicitGaps() throws {
        let url = try #require(Bundle.main.url(forResource: "exercise-videos", withExtension: "json"))
        let links = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: url))
        let builtIn = Set(ExerciseCatalog.shared.builtIn.map(\.id))
        let withoutVideo: Set<String> = []
        #expect(Set(links.keys).isSubset(of: builtIn))
        #expect(links.values.allSatisfy { FormVideo(link: $0) != nil })
        #expect(Set(FormVideos.suggestions.keys) == builtIn.subtracting(withoutVideo))
    }

    @Test func mergedIDsResolveTheSurvivorsSuggestion() {
        #expect(FormVideos.suggestion(for: "scaption-dumbbell") == FormVideos.suggestion(for: "scaption"))
    }

    @Test func replacingAndResettingLeavesOnlyTheChosenVideo() throws {
        let context = try TestStore.context()
        let id = "barbell-bench-press"
        let custom = try #require(FormVideo(link: "https://youtu.be/aaaaaaaaaaa?t=42"))
        let other = try #require(FormVideo(link: "bbbbbbbbbbb"))
        func records() throws -> [FormVideoRecord] { try context.fetch(FetchDescriptor<FormVideoRecord>()) }
        FormVideos.set(custom, for: id, context: context)
        #expect(FormVideos.video(for: id, records: try records()) == custom)
        FormVideos.set(other, for: id, context: context)
        #expect(try records().count == 1)
        #expect(FormVideos.video(for: id, records: try records()) == other)
        FormVideos.reset(id, context: context)
        #expect(try records().isEmpty)
        #expect(FormVideos.video(for: id, records: try records()) == FormVideos.suggestion(for: id))
        FormVideos.set(custom, for: id, context: context)
        FormVideos.set(try #require(FormVideos.suggestion(for: id)), for: id, context: context)
        #expect(try records().isEmpty)
    }

    @Test func mergedReplacementsAreStoredUnderTheSurvivor() throws {
        let context = try TestStore.context()
        let custom = try #require(FormVideo(link: "aaaaaaaaaaa"))
        FormVideos.set(custom, for: "scaption-dumbbell", context: context)
        let rows = try context.fetch(FetchDescriptor<FormVideoRecord>())
        #expect(rows.count == 1 && rows.first?.catalogID == "scaption")
        #expect(FormVideos.video(for: "scaption", records: rows) == custom)
    }

    @Test func customExerciseReturnsToHavingNoVideo() throws {
        let context = try TestStore.context()
        let id = "custom-form-video"
        #expect(FormVideos.suggestion(for: id) == nil)
        let custom = try #require(FormVideo(link: "aaaaaaaaaaa"))
        FormVideos.set(custom, for: id, context: context)
        #expect(FormVideos.video(for: id, records: try context.fetch(FetchDescriptor<FormVideoRecord>())) == custom)
        FormVideos.reset(id, context: context)
        #expect(FormVideos.video(for: id, records: try context.fetch(FetchDescriptor<FormVideoRecord>())) == nil)
    }

    @Test func newestCanonicalReplacementWinsAndInvalidLinksFallBack() throws {
        let older = FormVideoRecord(catalogID: "scaption", link: "https://youtu.be/aaaaaaaaaaa")
        older.updatedAt = Date(timeIntervalSince1970: 1)
        let newer = FormVideoRecord(catalogID: "scaption-dumbbell", link: "https://youtu.be/bbbbbbbbbbb")
        newer.updatedAt = Date(timeIntervalSince1970: 2)
        #expect(FormVideos.video(for: "scaption", records: [newer, older]) == FormVideo(link: newer.link))
        newer.link = "invalid"
        #expect(FormVideos.video(for: "scaption", records: [older, newer]) == FormVideos.suggestion(for: "scaption"))
    }
}
