import SwiftUI
import SwiftData

/// Shown once, right after finishing — the payoff screen.
struct SessionSummaryView: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var allSessions: [WorkoutSession]

    /// One row per exercise — a session where you worked up to a top set would
    /// otherwise list every rung of the ladder as its own record.
    private var prs: [SetLog] {
        let history = allSessions.filter { $0.id != session.id }
        let all = session.completedSets.filter { TrainingStats.isPersonalRecord($0, in: history + [session]) }
        return Dictionary(grouping: all, by: \.catalogID)
            .compactMap { _, sets in sets.max { $0.estimatedOneRepMax < $1.estimatedOneRepMax } }
            .sorted { $0.exerciseOrder < $1.exerciseOrder }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    headline
                    statGrid
                    HealthMetricsCard(session: session)
                    if !prs.isEmpty { prSection }
                    SessionNoteCard(session: session)
                    breakdown
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .gtScreenBackground()
            // Health can take a moment to receive the watch's samples, so the
            // numbers are asked for again when the summary opens rather than
            // only at the instant the session ended.
            .task {
                await HealthKitService.shared.backfillVitals(for: session)
                try? context.save()
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
        .presentationBackground(Theme.background)
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
                StatTile(value: "\(session.completedSets.count)", label: "Sets")
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

    private var prSection: some View {
        VStack(spacing: 8) {
            SectionHeader("Personal records")
            ForEach(prs) { set in
                HStack(spacing: 10) {
                    GlyphTile(symbol: "trophy.fill", tint: Theme.accent, size: 30, solid: true)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(set.exerciseName)
                            .font(Theme.rounded(14, weight: .bold))
                            .foregroundStyle(Theme.ink)
                        Text(set.tracking == .duration
                             ? "\(set.seconds)s"
                             : "\(set.weightLabel) × \(set.reps)")
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
                        .font(Theme.rounded(14, weight: .bold))
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
                            .font(.system(size: 13, weight: .semibold))
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
    /// A peak read over the set the lifter announced and a peak read over the
    /// seconds this app guessed the set occupied are different claims, and a
    /// row that read the same either way would borrow the credibility of the
    /// measured one for both.
    private func hardestSetRow(_ set: SetLog) -> some View {
        HStack(spacing: 10) {
            GlyphTile(symbol: "bolt.heart.fill", tint: Theme.negative, size: 30, solid: true)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(set.exerciseName), set \(setNumber(of: set))")
                    .font(Theme.rounded(14, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(set.heartRateWindow == .measured
                     ? "Peak \(Int((set.maxHeartRate ?? 0).rounded())) bpm, measured over the set"
                     : "Peak \(Int((set.maxHeartRate ?? 0).rounded())) bpm, over an estimated window")
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
/// window where an average doesn't. A window this app inferred is drawn with a
/// tilde and spelled out in full for VoiceOver: the number is real, the seconds
/// it was read over are this app's best guess, and a reader is owed that
/// distinction whether they're looking or listening.
struct SetHeartRateBadge: View {
    let set: SetLog

    var body: some View {
        if let peak = set.maxHeartRate {
            let bpm = Int(peak.rounded())
            let measured = set.heartRateWindow == .measured
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 8, weight: .bold))
                Text(measured ? "\(bpm)" : "~\(bpm)")
                    .font(Theme.number(11, weight: .semibold))
            }
            .foregroundStyle(Theme.negative.opacity(0.75))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(measured
                                ? "Peak \(bpm) beats per minute"
                                : "Peak about \(bpm) beats per minute, over an estimated window")
        }
    }
}

// MARK: - Session detail (read-only history)

struct SessionDetailView: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var showingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    StatTile(value: session.duration.durationString, label: "Duration")
                    StatTile(value: "\(session.completedSets.count)", label: "Sets")
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
                        ForEach(Array(group.sets.filter(\.isCompleted).enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("Set \(index + 1)")
                                    .font(Theme.rounded(12, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer()
                                // Before the weight, so the weights stay in one
                                // hard-right column down the card whether or
                                // not the watch was on that day.
                                SetHeartRateBadge(set: set)
                                Text(set.tracking == .duration
                                     ? "\(set.seconds)s"
                                     : "\(set.weightLabel) × \(set.reps)")
                                    .font(Theme.number(13, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                    .gtCard(padding: 12)
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
        .gtScreenBackground()
        .navigationTitle(session.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) { showingDeleteConfirm = true } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(Theme.negative)
                }
            }
        }
        .confirmationDialog("Delete this session?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                // Health keeps its own copy; removing the session here should
                // remove that too rather than leaving an orphan in Fitness.
                if let workoutID = session.healthWorkoutID {
                    Task { await HealthKitService.shared.deleteWorkout(id: workoutID) }
                }
                context.delete(session)
                try? context.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its sets are removed from your history and stats. This can't be undone.")
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
