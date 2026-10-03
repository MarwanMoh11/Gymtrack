import Foundation

/// When this copy of the app stops opening, on a build signed with a
/// development profile.
///
/// A free Apple ID signs for seven days, counted from when the profile was
/// made rather than from the install. Xcode reuses a cached profile until it
/// runs out, so a fresh install can have far less than a week left: the 2.1
/// build installed on 29 September carried a profile from the 24th, stopped
/// opening on 1 October, and a workout went unlogged. The date is read from
/// the profile inside the bundle, so it is the real one, whatever was used to
/// install it. `nil` on a build that carries no profile, which is how the App
/// Store ships one.
enum BuildExpiry {

    static let date: Date? = readEmbeddedProfile()

    /// How long before the date Today starts saying so. `scripts/install-phone.sh`
    /// refreshes the signing every two days, so a healthy install never gets
    /// this close; seeing the line means the refresh has stopped reaching the
    /// phone, with time left to reinstall before a gym day.
    static let warningLead: TimeInterval = 3 * 24 * 60 * 60

    /// The expiry, when it is close enough to mention.
    static func upcoming(now: Date = .now) -> Date? {
        guard let date, date.timeIntervalSince(now) < warningLead else { return nil }
        return date
    }

    private static func readEmbeddedProfile() -> Date? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url) else { return nil }
        // A signed envelope around a plain XML property list. The list can be
        // cut out without checking the signature, which iOS has already done
        // by letting the app run at all.
        guard let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex)
        else { return nil }
        let plist = try? PropertyListSerialization.propertyList(
            from: data[start.lowerBound..<end.upperBound], format: nil
        ) as? [String: Any]
        return plist?["ExpirationDate"] as? Date
    }
}
