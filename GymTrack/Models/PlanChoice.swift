import Foundation

extension Plan {
    /// The plan the app describes as current: the active one, else the one
    /// created first.
    ///
    /// One rule for every screen and every path that has to say what "today"
    /// is: the Today card, the root view, the widgets, and the wrist's headless
    /// path, which fetches its plans with no sort. The rule used to be written
    /// out at each of them, and the headless copy took `plans.first` of
    /// whatever order the store returned. With no active plan and more than one
    /// plan, the wrist could then start a different routine from the one Today
    /// was showing. Ordering here makes the answer the same however the caller
    /// fetched.
    ///
    /// Its own file because every script that compiles the command center has
    /// to compile the rule too, and `WidgetPublisher`, which wraps it for the
    /// widgets, is replaced by a stub in nearly all of them.
    static func displayed(among plans: [Plan]) -> Plan? {
        let ordered = plans.sorted { $0.createdAt < $1.createdAt }
        return ordered.first(where: \.isActive) ?? ordered.first
    }
}
