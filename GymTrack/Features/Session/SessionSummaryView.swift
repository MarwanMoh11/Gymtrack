import SwiftUI
import SwiftData

/// Shown once, right after finishing — the payoff screen.
struct SessionSummaryView: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    /// One row per exercise and kind that set a record today: a session where
    /// you worked up to a top set would otherwise list every rung of the ladder
    /// as its own record.
    ///
    /// Worked out once, in `.task`, rather than read from the history on each
    /// draw. Typing in the session note saves on every character, and a draw
    /// that walked a year of sessions per keystroke made the one field on this
    /// screen lag.
    @State private var prs: [SetLog] = []

    /// Changes only when the session's own sets do; see `SummaryRecordsKey`.
    private var recordsKey: TrainingStats.SummaryRecordsKey { .init(session) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headline
                    statGrid
                    HealthMetricsCard(session: session)
                    if !prs.isEmpty { prSection(prs) }
                    SessionNoteCard(session: session)
                    breakdown
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .gtScreenBackground()
            // Health can take a moment to receive the watch's samples, and a
            // phone locked in a bag can't read them at all, so the numbers are
            // asked for again when the summary opens and each time the app
            // comes back to it, rather than only at the instant the session
            // ended.
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                await HealthKitService.shared.backfillVitals(for: session)
                try? context.save()
            }
            .task(id: recordsKey) {
                prs = (try? SummaryRecords.sets(for: session, in: context)) ?? []
            }
            .navigationTitle("Session complete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.rounded(15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .gtSheetBackground()
    }

    /// The one moment in the app worth a flourish: the session's own colour
    /// blooming out behind a filled medallion, the way the Live Activity closes
    /// out.
    private var headline: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 70, height: 70)
                .background {
                    Circle().fill(SessionPhase.done.gradient)
                    Circle().fill(LinearGradient(colors: [Color.white.opacity(0.28), .clear],
                                                 startPoint: .top, endPoint: .center))
                }
                .shadow(color: SessionPhase.done.glow, radius: 22, y: 8)
                .padding(.bottom, 2)
            Text(session.title)
                .font(Theme.rounded(24, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity)
        .background {
            SessionPhase.done.bloom(strength: 1.1)
                .mask(RadialGradient(colors: [.white, .clear], center: .center, startRadius: 0, endRadius: 200))
        }
    }

    private var statGrid: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                StatTile(value: session.duration.durationString, label: "Duration")
                StatTile(value: "\(session.effortSets.count)", label: "Sets")
                StatTile(value: AppSettings.shared.weight(session.totalVolumeKg, showUnit: false),
                         label: "Volume \(AppSettings.shared.weightUnit.short)")
            }
            paceRow
        }
    }

    /// The half of the session nobody was asked about: how long you actually
    /// took between sets, and how much work that hour held. Both are read off
    /// the timestamps every logged set already carried.
    ///
    /// The rest says which kind of number it is. Where every set was announced
    /// as starting it is the rest and nothing else; otherwise it still has the
    /// set inside it, and a tile that read the same either way would quietly
    /// claim a precision it only sometimes has.
    @ViewBuilder
    private var paceRow: some View {
        let rest = session.typicalRestSeconds
        let density = session.densityKgPerMinute
        if rest != nil || density > 0 {
            HStack(spacing: 10) {
                if let rest {
                    StatTile(value: TimeInterval(rest).clockString,
                             label: "Typical rest",
                             caption: session.restIsMeasured ? "measured" : "between sets",
                             tint: SessionPhase.resting.tint)
                }
                if density > 0 {
                    StatTile(value: AppSettings.shared.weight(density, showUnit: false, decimals: 0),
                             label: "\(AppSettings.shared.weightUnit.short) per min",
                             caption: "how dense it was")
                }
                if let feel = TrainingStats.feel(of: session.completedSets) {
                    StatTile(value: feel.label, label: "Felt", caption: feel.detail, tint: feel.tint)
                }
            }
        }
    }

    /// A set read out the way you'd say it, for the chips that draw it short.
    private func setSpoken(_ set: SetLog) -> String {
        if set.tracking == .duration { return "\(set.seconds) seconds" }
        if set.weightKg == 0 { return "\(set.reps) reps" }
        return "\(set.weightLabel) for \(set.reps) reps"
    }

    private func prSection(_ prs: [SetLog]) -> some View {
        VStack(spacing: 8) {
            SectionHeader("Personal records")
            ForEach(prs) { set in
                HStack(spacing: 10) {
                    GlyphTile(symbol: "trophy.fill", tint: Theme.accent, size: 30, solid: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(set.exerciseName)
                            .gtFont(size: 14, weight: .bold, relativeTo: .subheadline)
                            .foregroundStyle(Theme.ink)
                        Text(TrainingStats.setLabel(set))
                            .font(Theme.number(12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .gtCard(padding: 12, phase: .working)
            }
        }
    }

    private var breakdown: some View {
        VStack(spacing: 8) {
            SectionHeader("What you did")
            ForEach(session.exerciseGroups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    Text(group.name)
                        .gtFont(size: 14, weight: .bold, relativeTo: .subheadline)
                        .foregroundStyle(Theme.ink)
                    if let note = session.note(for: group.catalogID), !note.isEmpty {
                        NoteReadout(text: note.text, tags: note.tags)
                            .padding(.bottom, 2)
                    }
                    FlowRow(spacing: 6) {
                        ForEach(group.sets.filter(\.isCompleted)) { set in
                            // A rated set carries a dot in the colour of the
                            // answer. The word itself would be four chips wide;
                            // the colour says the same thing at a glance, and
                            // the label spells it out for VoiceOver.
                            HStack(spacing: 4) {
                                Text(set.tracking == .duration
                                     ? "\(set.seconds)s"
                                     : (set.weightKg == 0
                                        ? "\(set.reps)"
                                        : "\(set.loadScale.format(set.weightKg, showUnit: false))×\(set.reps)"))
                                    .font(Theme.number(12, weight: .semibold))
                                if let feel = set.feel {
                                    Circle()
                                        .fill(feel.tint)
                                        .frame(width: 5, height: 5)
                                }
                            }
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Theme.panel, in: Capsule())
                            .overlay { Capsule().strokeBorder(Theme.edge, lineWidth: 1) }
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel(set.feel.map { "\(setSpoken(set)), felt \($0.label)" }
                                                ?? setSpoken(set))
                        }
                    }
                }
                .gtCard(padding: 12)
            }
        }
    }
}

// MARK: - What the watch and Health recorded

/// Heart rate, energy and where the session ended up. Draws nothing at all
/// when there's none of it — an empty card would just be a reminder that the
/// watch wasn't worn.
struct HealthMetricsCard: View {
    let session: WorkoutSession

    var body: some View {
        let hardest = session.hardestSet
        if session.hasHealthMetrics || session.healthWorkoutID != nil || hardest != nil {
            VStack(spacing: 8) {
                SectionHeader(session.wasWatchDriven ? "From your watch" : "From Health")

                if let hardest { hardestSetRow(hardest) }

                if session.hasHealthMetrics {
                    HStack(spacing: 10) {
                        if let average = session.averageHeartRate {
                            StatTile(value: "\(Int(average.rounded()))", label: "Avg BPM",
                                     caption: "heart rate", tint: Theme.negative)
                        }
                        if let max = session.maxHeartRate {
                            StatTile(value: "\(Int(max.rounded()))", label: "Peak BPM",
                                     caption: "heart rate", tint: Theme.warning)
                        }
                        if let energy = session.activeEnergyKcal, energy >= 1 {
                            StatTile(value: "\(Int(energy.rounded()))", label: "Active kcal",
                                     caption: "energy", tint: Theme.accent)
                        }
                    }
                }

                if session.healthWorkoutID != nil {
                    HStack(spacing: 8) {
                        Image(systemName: "heart.text.square.fill")
                            .gtIcon(size: 13, weight: .semibold, relativeTo: .caption)
                            .foregroundStyle(Theme.negative.wash)
                        Text("Saved to Health as a strength workout")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                    }
                    .gtCard(padding: 12)
                }
            }
        }
    }

    /// The one set that cost the most, named. A session average says a workout
    /// happened; this says which part of it was the work, and it is the whole
    /// reason per-set heart rate is worth attributing at all.
    ///
    /// The caption says which kind of number it is, the way the rest tile does.
    /// A peak read over the set the lifter announced, over the set as the heart
    /// rate drew it, and over the seconds this app guessed the set occupied are
    /// three different claims, and a row that read the same either way would
    /// lend the measured one's credibility to the others.
    private func hardestSetRow(_ set: SetLog) -> some View {
        HStack(spacing: 10) {
            GlyphTile(symbol: "bolt.heart.fill", tint: Theme.negative, size: 30, solid: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(set.exerciseName), set \(setNumber(of: set))")
                    .gtFont(size: 14, weight: .bold, relativeTo: .subheadline)
                    .foregroundStyle(Theme.ink)
                Text(peakCaption(for: set))
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Text("HARDEST")
                .font(Theme.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
        }
        .gtCard(padding: 12)
        .accessibilityElement(children: .combine)
    }

    /// The hardest set's peak, and what it was read over. A window read off the
    /// heart rate also says how long the set took — the number nobody tapped
    /// for — so the caption says it too.
    private func peakCaption(for set: SetLog) -> String {
        let peak = "Peak \(Int((set.maxHeartRate ?? 0).rounded())) bpm"
        switch set.heartRateWindow {
        case .measured:
            return "\(peak), measured over the set"
        case .detected:
            // A restored backup can name the window without carrying it.
            guard let length = set.detectedDuration else { return "\(peak), read off your heart rate" }
            return "\(peak) over a \(Int(length.rounded())) s set, read off your heart rate"
        case .inferred, nil:
            return "\(peak), over an estimated window"
        }
    }

    /// What the set is called on the card it belongs to — 1, 2, 3 down the
    /// exercise, not its index in the session.
    private func setNumber(of set: SetLog) -> String {
        session.exerciseGroups.first { $0.catalogID == set.catalogID }?.label(for: set) ?? "1"
    }
}

/// The heart rate a single set was worked at, small enough to sit in a row of
/// numbers without becoming one of them.
///
/// The peak and not the average, because the peak is the thing a set is asked
/// about — how hard did this go — and because a peak survives a slightly wrong
/// window where an average doesn't. A window this app worked out — read off the
/// heart rate or estimated from the reps — is drawn with a tilde and spelled
/// out in full for VoiceOver: the number is real, the seconds it was read over
/// are this app's reading rather than anybody's tap, and a reader is owed that
/// distinction whether they're looking or listening.
struct SetHeartRateBadge: View {
    let set: SetLog

    var body: some View {
        if let peak = set.maxHeartRate {
            let bpm = Int(peak.rounded())
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .gtIcon(size: 8, weight: .bold, relativeTo: .caption2)
                Text(isMeasured ? "\(bpm)" : "~\(bpm)")
                    .font(Theme.number(11, weight: .semibold))
            }
            .foregroundStyle(Theme.negative.opacity(0.75))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken(bpm))
        }
    }

    private var isMeasured: Bool { self.set.heartRateWindow == .measured }

    private func spoken(_ bpm: Int) -> String {
        switch set.heartRateWindow {
        case .measured:
            return "Peak \(bpm) beats per minute"
        case .detected:
            guard let length = set.detectedDuration else {
                return "Peak about \(bpm) beats per minute, over a window read off your heart rate"
            }
            return "Peak about \(bpm) beats per minute, over a \(Int(length.rounded())) second set read off your heart rate"
        case .inferred, nil:
            return "Peak about \(bpm) beats per minute, over an estimated window"
        }
    }
}

// MARK: - Session detail (read-only history)

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    StatTile(value: session.duration.durationString, label: "Duration")
                    StatTile(value: "\(session.effortSets.count)", label: "Sets")
                    StatTile(value: AppSettings.shared.weight(session.totalVolumeKg, showUnit: false),
                             label: "Volume \(AppSettings.shared.weightUnit.short)")
                }

                HealthMetricsCard(session: session)

                // Still writable here, because the summary it was offered on is
                // shown once. What you remember on the way home has somewhere
                // to go; the per-exercise notes stay as they were written,
                // which is what keeps this screen a record rather than a draft.
                SessionNoteCard(session: session)

                ForEach(session.exerciseGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name)
                            .font(Theme.rounded(15, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        if let note = session.note(for: group.catalogID), !note.isEmpty {
                            NoteReadout(text: note.text, tags: note.tags)
                                .padding(.bottom, 2)
                        }
                        ForEach(group.sets.filter(\.isCompleted)) { set in
                            HistorySetRow(set: set, number: group.label(for: set))
                        }
                    }
                    .gtCard(padding: 12)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .gtScreenBackground()
        // The summary is shown at the instant a session ends, and a wrist
        // finish with the phone locked shows none at all, so this page is
        // where a session's late heart rate gets its next chance. Health is
        // asked only for what is still missing, or was read here off a trace
        // that may since have filled in.
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await HealthKitService.shared.backfillVitals(for: session)
            try? context.save()
        }
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.negative)
                }
                .accessibilityLabel("Delete session")
            }
        }
        .confirmationDialog("Delete this session?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteSession() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its sets are removed from your history and stats. This can't be undone.")
        }
    }

    /// Deletes the session, and hands its Health workout to the durable
    /// cleanup list rather than firing one delete and forgetting it. Health
    /// keeps its own copy, and it is usually the watch's, which the phone may
    /// be unable to see or remove on the first try; the list retries it.
    ///
    /// The workout is queued only once the delete has reached disk. Queued
    /// first, a failed save would remove the workout of a session still in
    /// the list.
    private func deleteSession() {
        let workoutID = session.healthWorkoutID
        let sessionID = session.id
        context.delete(session)
        let saved = (try? context.save()) != nil
        if saved, let workoutID {
            HealthKitService.shared.discardWorkout(workoutID, ofDeletedSession: sessionID)
        }
        dismiss()
    }
}

/// One logged set, read back from the record.
///
/// Numbered the way the logger numbered it, efforts rather than rows. This
/// screen used to count rows, so a session with one drop in it had a "Set 4"
/// here that the logger, the Lock Screen and the wrist had all called set 3 —
/// and the hardest-set line on the same screen, which does count efforts,
/// named a set the list below it didn't have.
///
/// A drop or cluster row carries its word instead of a number of its own, and
/// a set that was rated carries the answer. Both were in the record all along
/// and this was the only screen that read it back without them.
private struct HistorySetRow: View {
    let set: SetLog
    let number: String

    var body: some View {
        HStack(spacing: 6) {
            if let continuation = set.continuation {
                Label(continuation.label, systemImage: SetContinuation.symbol)
                    .labelStyle(.titleAndIcon)
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.accent.wash)
                    .padding(.leading, 10)
                    .accessibilityLabel(continuation.spoken)
            } else {
                Text("Set \(number)")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            if let feel = set.feel {
                Text(feel.label)
                    .gtFont(size: 10, weight: .bold, relativeTo: .caption2, maxScale: 1.5)
                    .foregroundStyle(feel.tint)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(feel.tint.opacity(0.14), in: Capsule())
                    .accessibilityLabel("Felt \(feel.label)")
            }
            Spacer()
            // Before the weight, so the weights stay in one hard-right column
            // down the card whether or not the watch was on that day.
            SetHeartRateBadge(set: set)
            Text(TrainingStats.setLabel(set))
                .font(Theme.number(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Flow layout

/// Wraps its children onto new lines when they run out of width.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
