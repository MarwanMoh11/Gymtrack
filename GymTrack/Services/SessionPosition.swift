import Foundation

/// Where a running session is up to, worked out from the session alone.
///
/// `ActiveWorkout` answers these questions for the logger on screen. The
/// Lock Screen card and the Home Screen widget need the same answers when a
/// watch message wakes the app with no logger at all, and building an
/// `ActiveWorkout` there means starting a rest timer, a Live Activity and a
/// watch push just to read six numbers. So the answers are given here, by the
/// same rules, and a test holds the two in step.
///
/// `ActiveWorkout`'s `currentGroup`, `nextSet`, `nextSetNumber`,
/// `currentSetTotal`, `nextTargetLabel` and `upNextName` read this rather than
/// keep a second copy, so the rules live in one place.
@MainActor
struct SessionPosition {

    let session: WorkoutSession
    let groups: [SessionExerciseGroup]

    init(_ session: WorkoutSession) {
        self.session = session
        self.groups = session.exerciseGroups
    }

    /// Over groups the caller has already built. `exerciseGroups` sorts the
    /// whole session, and the logger asks these questions many times a pass.
    init(_ session: WorkoutSession, groups: [SessionExerciseGroup]) {
        self.session = session
        self.groups = groups
    }

    /// Counted as efforts, the same as the logger; see `WorkoutSession.effortCount`.
    var completedCount: Int { session.effortSets.count }
    var totalCount: Int { session.effortCount }

    /// The exercise holding the next unlogged set — what the session is "on".
    /// Normally the first one that isn't finished, unless the lifter has picked
    /// a different one to work on.
    var currentGroup: SessionExerciseGroup? {
        if let preferred = session.preferredExerciseID,
           let group = groups.first(where: { $0.catalogID == preferred && !$0.isComplete }) {
            return group
        }
        return groups.first { !$0.isComplete } ?? groups.last
    }

    /// The set about to be performed.
    var nextSet: SetLog? {
        currentGroup?.sets.first { !$0.isCompleted }
    }

    /// What `nextSet` is called on its card — efforts, not rows.
    var nextSetNumber: Int {
        guard let group = currentGroup else { return 0 }
        guard let next = nextSet else { return group.effortCount }
        return group.number(of: next)
    }

    /// How many sets the exercise that's up holds, counted the same way.
    var currentSetTotal: Int { currentGroup?.effortCount ?? 0 }

    /// "60 kg × 8–12" — the prescription for the set that's up.
    var nextTargetLabel: String {
        guard let set = nextSet else { return "" }
        if set.tracking == .duration { return "\(set.seconds)s" }
        let reps = set.targetRepsHigh > 0
            ? (set.targetRepsLow == set.targetRepsHigh
               ? "\(set.targetRepsLow)"
               : "\(set.targetRepsLow)–\(set.targetRepsHigh)")
            : "\(set.reps)"
        if set.weightKg == 0 { return "\(reps) reps" }
        return "\(set.weightLabel) × \(reps)"
    }

    /// The exercise queued behind the current one.
    var upNextName: String {
        guard let current = currentGroup else { return "" }
        return groups.first { $0.order > current.order && !$0.isComplete }?.name ?? ""
    }
}
