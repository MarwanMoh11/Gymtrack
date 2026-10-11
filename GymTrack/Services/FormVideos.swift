import Foundation
import SwiftData

/// Bundled form videos and the lifter's replacements, resolved by movement.
enum FormVideos {
    static let suggestions: [String: FormVideo] = {
        guard let url = Bundle.main.url(forResource: "exercise-videos", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let links = try? JSONDecoder().decode([String: String].self, from: data) else {
            assertionFailure("Missing or unreadable exercise-videos.json")
            return [:]
        }
        return links.compactMapValues { FormVideo(link: $0) }
    }()

    static func suggestion(for catalogID: String) -> FormVideo? {
        suggestions[ExerciseCatalog.canonicalID(for: catalogID)]
    }

    static func override(for catalogID: String, in records: [FormVideoRecord]) -> FormVideoRecord? {
        let canonical = ExerciseCatalog.canonicalID(for: catalogID)
        return records.filter { ExerciseCatalog.canonicalID(for: $0.catalogID) == canonical }
            .max { $0.updatedAt < $1.updatedAt }
    }

    static func video(for catalogID: String, records: [FormVideoRecord]) -> FormVideo? {
        let replacement = override(for: catalogID, in: records).flatMap { FormVideo(link: $0.link) }
        return replacement ?? suggestion(for: catalogID)
    }

    static func set(_ video: FormVideo, for catalogID: String, context: ModelContext) {
        deleteOverrides(catalogID, context: context)
        let canonical = ExerciseCatalog.canonicalID(for: catalogID)
        if video != suggestion(for: canonical) {
            context.insert(FormVideoRecord(catalogID: canonical, link: video.link))
        }
        try? context.save()
    }

    static func reset(_ catalogID: String, context: ModelContext) {
        deleteOverrides(catalogID, context: context)
        try? context.save()
    }

    private static func deleteOverrides(_ catalogID: String, context: ModelContext) {
        let canonical = ExerciseCatalog.canonicalID(for: catalogID)
        let records = (try? context.fetch(FetchDescriptor<FormVideoRecord>())) ?? []
        for record in records where ExerciseCatalog.canonicalID(for: record.catalogID) == canonical {
            context.delete(record)
        }
    }
}
