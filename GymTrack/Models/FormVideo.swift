import Foundation

/// A parsed YouTube video, so the bundled file, pasted links and backups all
/// follow the same rules instead of keeping whatever raw URL they received.
struct FormVideo: Hashable, Sendable {
    let videoID: String
    /// Seconds into the video, absent unless the link names a positive time.
    let start: Int?

    init?(link: String) {
        let trimmed = link.trimmingCharacters(in: .whitespacesAndNewlines)
        if Self.isVideoID(trimmed) {
            videoID = trimmed
            start = nil
            return
        }
        let address = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: address), var host = components.host?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "music."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
            break
        }
        guard ["youtube.com", "youtu.be", "youtube-nocookie.com"].contains(host) else { return nil }
        let path = components.path.split(separator: "/").map(String.init)
        let query = components.queryItems ?? []
        let id: String?
        if host == "youtu.be", path.count == 1 {
            id = path.first
        } else if host == "youtube.com", components.path == "/watch" {
            id = query.first { $0.name == "v" }?.value
        } else if path.count == 2,
                  (host == "youtube.com" && ["embed", "shorts", "live", "v"].contains(path[0]))
                    || (host == "youtube-nocookie.com" && path[0] == "embed") {
            id = path[1]
        } else {
            id = nil
        }
        guard let id, Self.isVideoID(id) else { return nil }
        videoID = id
        start = Self.seconds(query.first { $0.name == "t" || $0.name == "start" }?.value)
    }

    var link: String {
        "https://youtu.be/\(videoID)" + (start.map { "?t=\($0)" } ?? "")
    }

    var watchURL: URL {
        URL(string: "https://www.youtube.com/watch?v=\(videoID)" + (start.map { "&t=\($0)s" } ?? ""))!
    }

    var embedURL: URL {
        URL(string: "https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0" + (start.map { "&start=\($0)" } ?? ""))!
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9_-]{11}$", options: .regularExpression) != nil
    }

    private static func seconds(_ value: String?) -> Int? {
        guard let value else { return nil }
        if let seconds = Int(value), seconds > 0 { return seconds }
        guard value.range(of: "^(?:[0-9]+h)?(?:[0-9]+m)?(?:[0-9]+s)?$", options: .regularExpression) != nil,
              !value.isEmpty else { return nil }
        var total = 0
        var digits = ""
        for character in value {
            if character.isNumber {
                digits.append(character)
            } else {
                guard let count = Int(digits) else { return nil }
                let multiplier = character == "h" ? 3600 : character == "m" ? 60 : 1
                let product = count.multipliedReportingOverflow(by: multiplier)
                let sum = total.addingReportingOverflow(product.partialValue)
                guard !product.overflow, !sum.overflow else { return nil }
                total = sum.partialValue
                digits = ""
            }
        }
        return total > 0 ? total : nil
    }
}
