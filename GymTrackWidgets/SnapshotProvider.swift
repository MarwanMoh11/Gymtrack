import WidgetKit

/// What every GymTrack widget is drawn from.
///
/// The app restamps the snapshot whenever anything a widget shows moves and
/// asks WidgetKit to reload, so the timeline itself only has to cover the one
/// thing the app can't predict: midnight, when "today" becomes a different day
/// of the routine.
struct GymTrackEntry: TimelineEntry {
    let date: Date
    let snapshot: GymTrackSnapshot
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> GymTrackEntry {
        GymTrackEntry(date: .now, snapshot: .placeholder)
    }

    /// The gallery preview. Falls back to the placeholder so a widget being
    /// picked out never shows an empty card, whether or not the app has run.
    func getSnapshot(in context: Context, completion: @escaping (GymTrackEntry) -> Void) {
        completion(GymTrackEntry(date: .now, snapshot: current(allowPlaceholder: context.isPreview)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GymTrackEntry>) -> Void) {
        let entry = GymTrackEntry(date: .now, snapshot: current(allowPlaceholder: false))
        completion(Timeline(entries: [entry], policy: .after(nextRefresh())))
    }

    /// The real snapshot, or an empty one that the views know how to draw as
    /// "open GymTrack". The placeholder's invented Push Day is only ever shown
    /// in the gallery — putting it on someone's Home Screen would be a lie.
    private func current(allowPlaceholder: Bool) -> GymTrackSnapshot {
        if let snapshot = SharedStore.readSnapshot() { return snapshot }
        return allowPlaceholder ? .placeholder : GymTrackSnapshot()
    }

    /// Just after midnight. A widget showing "Push Day" has to stop showing it
    /// when Push Day is yesterday, and nothing in the app fires at that moment.
    private func nextRefresh() -> Date {
        let calendar = Calendar.current
        let midnight = calendar.nextDate(after: .now,
                                         matching: DateComponents(hour: 0, minute: 1),
                                         matchingPolicy: .nextTime)
        return midnight ?? Date.now.addingTimeInterval(3600)
    }
}
