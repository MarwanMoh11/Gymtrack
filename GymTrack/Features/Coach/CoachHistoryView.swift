import SwiftUI
import SwiftData

/// What came of the coach's reviews, opened from Settings: the latest
/// decision, its ratings, and the way back from it.
///
/// This is the only place a decision can be reverted, and the only place the
/// coach's file being unreadable is said. Today never mentions either, because
/// a lifter who isn't using the coach must not be able to tell it shipped.
struct CoachHistoryView: View {
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var openSessions: [WorkoutSession]

    @State private var handingOver = false
    @State private var confirmingRevert = false
    @State private var revertRefusal: String?

    private var inbox: CoachInbox { .shared }
    private var workoutRunning: Bool { !openSessions.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .gtScreenBackground()
        .navigationTitle("Plan review")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog("Put the plan back?", isPresented: $confirmingRevert, titleVisibility: .visible) {
            Button("Revert", role: .destructive) { revert() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The plan returns to how it was before this change. The record keeps that you applied it and then reverted it. If you have edited those exercises since, nothing is changed and you are told why.")
        }
        .onAppear { inbox.reload() }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if handingOver {
            CoachHandOffPanel(subject: .decision) { handingOver = false }
        } else {
            if let reason = inbox.unreadableReason { unreadable(reason) }
            if inbox.showsOnToday { waiting }
            if let decision = inbox.latestDecision {
                decisionCard(decision)
                outcomes(of: decision)
                if inbox.ratableDecision != nil {
                    CoachRatingsSection(title: "Ratings", caption: ratingCaption, subject: .decision) { handingOver = true }
                }
                if let revertible = inbox.revertibleDecision { revertSection(revertible) }
            } else if !inbox.showsOnToday {
                unactionable
            }
        }
    }

    private func unreadable(_ reason: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.warning)
                .accessibilityHidden(true)
            Text(reason + " Push it again from your Mac.")
                .font(Theme.rounded(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .gtCard(padding: 12)
    }

    /// A review that arrived after the last decision. It has its own screen;
    /// this is only the way to it.
    private var waiting: some View {
        NavigationLink {
            CoachReviewView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("A plan review is ready")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DisclosureChevron()
            }
            .gtCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    /// A proposal in the inbox with nothing to decide: every change is out of
    /// date or breaks a rule. Shown so the Settings row is never a dead end.
    @ViewBuilder private var unactionable: some View {
        if let proposal = inbox.proposal {
            VStack(alignment: .leading, spacing: 6) {
                Text(proposal.summary)
                    .font(Theme.rounded(20, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("None of these changes fit your plan as it is now, so there is nothing to decide.")
                    .font(Theme.rounded(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Changes")
                ForEach(inbox.rows) { CoachChangeCard(row: $0) }
            }
        }
    }

    // MARK: - The decision

    private func decisionCard(_ decision: CoachDecision) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("LATEST REVIEW")
                .font(Theme.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            Text(decision.headline)
                .font(Theme.rounded(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(decision.breakdown)
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("Decided \(CoachWording.moment(decision.decidedAt))")
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            if let reverted = decision.revertedAt {
                Text("Reverted \(CoachWording.moment(reverted))")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.warning)
            }
        }
        .gtCard()
    }

    /// The record keeps each change's id, outcome and note, not its wording, so
    /// a change is named only while its proposal is still in the inbox.
    private func outcomes(of decision: CoachDecision) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("What you decided")
            VStack(alignment: .leading, spacing: 14) {
                ForEach(decision.changes, id: \.id) { change in
                    outcomeRow(change, in: decision)
                }
            }
            .gtCard()
        }
    }

    private func outcomeRow(_ change: CoachChangeDecision, in decision: CoachDecision) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name(of: change, in: decision))
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                Pill(text: change.decision.label, color: change.decision.tint)
            }
            if let note = change.note, !note.isEmpty {
                Text(note)
                    .font(Theme.rounded(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func name(of change: CoachChangeDecision, in decision: CoachDecision) -> String {
        let sameProposal = inbox.proposal.map { $0.id.caseInsensitiveCompare(decision.proposalID) == .orderedSame } ?? false
        let found = sameProposal ? inbox.rows.first { $0.id == change.id }?.exerciseName : nil
        return found ?? "Change \(change.id)"
    }

    // MARK: - Ratings

    /// Ratings belong to the decision on the proposal in the inbox, else the
    /// latest one, declines included. When that is not the decision shown
    /// above, the screen says which it is.
    private var ratingCaption: String? {
        guard let rated = inbox.ratableDecision, rated.proposalID != inbox.latestDecision?.proposalID else { return nil }
        return "For the review decided \(CoachWording.moment(rated.decidedAt))."
    }

    // MARK: - Reverting

    private func revertSection(_ target: CoachDecision) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Back out")
            Button(revertTitle(for: target)) { confirmingRevert = true }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(workoutRunning)
            if workoutRunning {
                Text("Finish the workout that's running first. The plan can't change under it.")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let revertRefusal {
                Text(revertRefusal)
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.negative)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func revertTitle(for target: CoachDecision) -> String {
        guard target.proposalID == inbox.latestDecision?.proposalID else {
            return "Revert the change from \(CoachWording.moment(target.appliedAt ?? target.decidedAt))"
        }
        return "Revert this change"
    }

    private func revert() {
        revertRefusal = inbox.revert()?.reason
    }
}
