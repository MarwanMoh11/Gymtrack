import WidgetKit

/// What every GymTrack widget is drawn from.
///
/// The app restamps the snapshot whenever anything a widget shows moves and
/// asks WidgetKit to reload, so the timeline itself only has to cover the one
/// thing the app can't predict: the training day turning over, when "today"
/// becomes a different day of the routine.
struct GymTrackEntry: TimelineEntry {
    let date: Date
    /// `nil` when the app has never published anything — which is also what an
    /// unprovisioned App Group looks like from out here. The views draw that as
    /// "open GymTrack" rather than borrowing the state for a real account with
    /// no routine, which would tell someone who has one that they don't.
    let snapshot: GymTrackSnapshot?
}

struct SnapshotProvider: TimelineProvider {

    func placeholder(in context: Context) -> GymTrackEntry {
        GymTrackEntry(date: .now, snapshot: .placeholder)
    }

    /// The gallery preview. Falls back to the placeholder so a widget being
    /// picked out never shows an empty card, whether or not the app has run.
    func getSnapshot(in context: Context, completion: @escaping (GymTrackEntry) -> Void) {
        completion(GymTrackEntry(date: .now,
                                 snapshot: SharedStore.readSnapshot()
                                     ?? (context.isPreview ? .placeholder : nil)))
    }

    /// Now, and the moments the card has to change with nobody in the app to
    /// say so: the rest running out, a session going stale, and the training
    /// day turning over.
    ///
    /// Each entry carries the snapshot as it reads at that moment — see
    /// `GymTrackSnapshot.asOf`. Reloading at midnight used to hand back the
    /// same snapshot the widget already had, so the refresh that existed to
    /// retire yesterday's session went on showing it. And a rest ending is the
    /// Live Activity's stale date, but nothing at all for a widget: the card
    /// sat on a finished countdown in amber until the app next wrote.
    ///
    /// A session nobody finished has the same problem with no end in sight: the
    /// app closes it once it has been open twelve hours, but a phone left in a
    /// locker never runs to do it, so the card would keep timing a workout that
    /// ended the night before. `asOf` retires it at that moment, and the entry
    /// here is what makes the widget look.
    func getTimeline(in context: Context, completion: @escaping (Timeline<GymTrackEntry>) -> Void) {
        let now = Date.now
        let turnover = nextRefresh()
        let snapshot = SharedStore.readSnapshot()

        var moments = [now]
        if let restEndsAt = snapshot?.session?.restEndsAt, restEndsAt > now, restEndsAt < turnover {
            moments.append(restEndsAt)
        }
        if let staleAt = snapshot?.session?.staleAt, staleAt > now, staleAt < turnover {
            moments.append(staleAt)
        }
        moments.append(turnover)
        moments.sort()

        let entries = moments.map { GymTrackEntry(date: $0, snapshot: snapshot?.asOf($0)) }
        completion(Timeline(entries: entries, policy: .after(turnover)))
    }

    /// Just after the training day turns over (see `TrainingDay`). A widget
    /// showing "Push Day" has to stop showing it when Push Day is yesterday,
    /// and nothing in the app fires at that moment. Midnight is too early:
    /// `asOf` still reads the night's day until the cutoff, so a refresh then
    /// would change nothing and leave the old day up until the next one.
    private func nextRefresh() -> Date {
        let calendar = Calendar.current
        let turnover = calendar.nextDate(after: .now,
                                         matching: DateComponents(hour: TrainingDay.cutoffHour, minute: 1),
                                         matchingPolicy: .nextTime)
        return turnover ?? Date.now.addingTimeInterval(3600)
    }
}
