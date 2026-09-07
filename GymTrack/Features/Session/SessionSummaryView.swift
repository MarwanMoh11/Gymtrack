import SwiftUI
import SwiftData

/// Shown once, right after finishing — the payoff screen.
struct SessionSummaryView: View {
    let session: WorkoutSession
    @Environment(\.dismiss) private var dismiss
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
                    if !prs.isEmpty { prSection }
                    breakdown
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .gtScreenBackground()
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

    private var headline: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(.black)
                .frame(width: 70, height: 70)
                .background(Theme.accent, in: Circle())
            Text(session.title)
                .font(Theme.rounded(24, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text(session.startedAt.formatted(date: .abbreviated, time: .shortened))
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 8)
    }

    private var statGrid: some View {
        HStack(spacing: 10) {
            StatTile(value: session.duration.durationString, label: "Duration")
            StatTile(value: "\(session.completedSets.count)", label: "Sets")
            StatTile(value: AppSettings.shared.weight(session.totalVolumeKg, showUnit: false),
                     label: "Volume \(AppSettings.shared.weightUnit.short)")
        }
    }

    private var prSection: some View {
        VStack(spacing: 8) {
            SectionHeader("Personal records")
            ForEach(prs) { set in
                HStack(spacing: 10) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.black)
                        .frame(width: 30, height: 30)
                        .background(Theme.accent, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(set.exerciseName)
                            .font(Theme.rounded(14, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(set.tracking == .duration
                             ? "\(set.seconds)s"
                             : "\(AppSettings.shared.weight(set.weightKg)) × \(set.reps)")
                            .font(Theme.number(12, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                .gtCard(padding: 12, background: Theme.accentDim.opacity(0.6))
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
                        .foregroundStyle(Theme.textPrimary)
                    FlowRow(spacing: 6) {
                        ForEach(group.sets.filter(\.isCompleted)) { set in
                            Text(set.tracking == .duration
                                 ? "\(set.seconds)s"
                                 : (set.weightKg == 0 ? "\(set.reps)" : "\(AppSettings.shared.weight(set.weightKg, showUnit: false))×\(set.reps)"))
                                .font(Theme.number(12, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                                .padding(.horizontal, 8).padding(.vertical, 4)
                                .background(Theme.surfaceRaised, in: Capsule())
                        }
                    }
                }
                .gtCard(padding: 12)
            }
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

                ForEach(session.exerciseGroups) { group in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(group.name)
                            .font(Theme.rounded(15, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        ForEach(Array(group.sets.filter(\.isCompleted).enumerated()), id: \.element.id) { index, set in
                            HStack {
                                Text("Set \(index + 1)")
                                    .font(Theme.rounded(12, weight: .medium))
                                    .foregroundStyle(Theme.textTertiary)
                                Spacer()
                                Text(set.tracking == .duration
                                     ? "\(set.seconds)s"
                                     : "\(AppSettings.shared.weight(set.weightKg)) × \(set.reps)")
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
