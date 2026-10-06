import SwiftUI
import SwiftData

/// The coach's proposal, laid out so each change can be accepted or declined on
/// its own. Opened from Today's quiet line, or from Settings while a review is
/// still waiting.
///
/// Once applied, the screen stays up and says so, with Undo for a mis-tap. Undo
/// exists only on this instance of the screen: leave it and the way back is
/// Revert in Settings, which keeps a record that the change was tried.
struct CoachReviewView: View {
    /// True where the screen is a sheet of its own and needs a way out.
    var showsClose = false

    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var openSessions: [WorkoutSession]

    @State private var choices: [String: CoachChoice] = [:]
    @State private var notes: [String: String] = [:]
    @State private var refusal: String?
    /// The decision made on this screen, kept here and nowhere else so that
    /// Undo is offered after deciding and only until the screen is left.
    @State private var decided: CoachDecision?
    /// The cards as they read before the apply. Afterwards the plan holds the
    /// new values, so rows recomputed from it would show a change as already
    /// being what it changes to.
    @State private var decidedRows: [CoachValidator.Row] = []
    @State private var undoRefusal: String?

    private var inbox: CoachInbox { .shared }

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
        .toolbar {
            if showsClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .font(Theme.rounded(15, weight: .bold))
                }
            }
        }
        .onAppear { inbox.reload() }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if let proposal = inbox.proposal {
            header(proposal)
            if let decided { decidedStatus(decided) }
            changes
            advice
            if decided == nil { decideArea }
        } else {
            EmptyStateView(icon: "checklist", title: "Nothing to review",
                           message: "A review from your coach shows up here when there is one.")
        }
    }

    private func header(_ proposal: CoachProposal) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("WRITTEN \(CoachWording.day(proposal.createdAt).uppercased())")
                .font(Theme.eyebrow)
                .tracking(1.4)
                .foregroundStyle(Theme.textTertiary)
            Text(proposal.summary)
                .font(Theme.rounded(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Changes

    private var shownRows: [CoachValidator.Row] { decided == nil ? inbox.rows : decidedRows }

    private var changes: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader("Changes")
            ForEach(shownRows) { row in
                card(for: row)
            }
        }
    }

    @ViewBuilder private func card(for row: CoachValidator.Row) -> some View {
        if let decided {
            let entry = decided.changes.first { $0.id == row.id }
            CoachChangeCard(row: row, outcome: entry?.decision, decidedNote: entry?.note)
        } else {
            CoachChangeCard(row: row, choice: choiceBinding(row.id), note: noteBinding(row.id))
        }
    }

    private func choiceBinding(_ id: String) -> Binding<CoachChoice?> {
        Binding(get: { choices[id] }, set: { choices[id] = $0; refusal = nil })
    }

    private func noteBinding(_ id: String) -> Binding<String> {
        Binding(get: { notes[id] ?? "" }, set: { notes[id] = $0 })
    }

    // MARK: - Advice

    @ViewBuilder private var advice: some View {
        let lines = inbox.advice.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionHeader("Coach's notes")
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Circle().fill(Theme.textTertiary).frame(width: 5, height: 5)
                                .accessibilityHidden(true)
                            Text(line)
                                .font(Theme.rounded(15, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Text("These don't change your plan.")
                        .font(Theme.rounded(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .gtCard()
            }
        }
    }

    // MARK: - Deciding

    private var applicableRows: [CoachValidator.Row] { inbox.rows.filter { $0.status.isApplicable } }
    private var acceptedCount: Int { applicableRows.filter { choices[$0.id] == .accept }.count }
    private var declinedCount: Int { applicableRows.filter { choices[$0.id] == .decline }.count }
    private var undecidedCount: Int { applicableRows.count - acceptedCount - declinedCount }
    private var workoutRunning: Bool { !openSessions.isEmpty }
    private var canApply: Bool { !applicableRows.isEmpty && undecidedCount == 0 && !workoutRunning }

    private var applyLabel: String {
        if undecidedCount == applicableRows.count { return "Accept or decline each change" }
        if undecidedCount > 0 { return "Choose for \(undecidedCount) more" }
        if acceptedCount == 0 { return "Decline all" }
        if declinedCount == 0 { return "Apply \(acceptedCount)" }
        return "Apply \(acceptedCount), decline \(declinedCount)"
    }

    @ViewBuilder private var decideArea: some View {
        if applicableRows.isEmpty {
            note("None of these changes fit your plan as it is now, so there is nothing to decide. The next review will start from the plan as it is.")
        } else {
            VStack(spacing: 10) {
                if let refusal { note(refusal, color: Theme.negative) }
                if workoutRunning {
                    note("Finish the workout that's running first. The plan can't change under it.")
                }
                Button(applyLabel) { apply() }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: canApply))
                    .disabled(!canApply)
            }
        }
    }

    private func note(_ text: String, color: Color = Theme.textSecondary) -> some View {
        Text(text)
            .font(Theme.rounded(13, weight: .semibold))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func apply() {
        refusal = nil
        let accepted = Set(applicableRows.filter { choices[$0.id] == .accept }.map(\.id))
        let rowsBefore = inbox.rows
        switch inbox.apply(accepted: accepted, notes: keptNotes) {
        case .success(let decision):
            decidedRows = rowsBefore
            decided = decision
            undoRefusal = nil
            Haptics.success()
        case .failure(let failure):
            refusal = failure.reason
        }
    }

    /// Notes with something in them. An empty field is no note, and the record
    /// is written without the key.
    private var keptNotes: [String: String] {
        notes.compactMapValues { text in
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? nil : clean
        }
    }

    // MARK: - After deciding

    private var canUndo: Bool { decided != nil && inbox.canUndoLastDecision }

    /// A decline changed no slot, so its Undo has nothing to put back and no
    /// Revert to fall back on later; saying "puts the plan back" would be false.
    private var undoExplanation: String {
        if decided?.appliedAt == nil {
            return "Undo brings this review back undecided and leaves no record that you declined it."
        }
        return "Undo puts the plan back and leaves no record that this happened. Once you close this screen, Settings has Revert instead, which keeps the record."
    }

    private func decidedStatus(_ decision: CoachDecision) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: decision.appliedAt == nil ? "minus.circle.fill" : "checkmark.circle.fill")
                    .gtIcon(size: 22, relativeTo: .title2)
                    .foregroundStyle(decision.appliedAt == nil ? Theme.textSecondary : Theme.positive)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(decision.headline)
                        .font(Theme.rounded(17, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(decision.breakdown)
                        .font(Theme.rounded(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if canUndo {
                Button("Undo") { undo() }
                    .buttonStyle(SecondaryButtonStyle())
                Text(undoExplanation)
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let undoRefusal { note(undoRefusal, color: Theme.negative) }
        }
        .gtCard()
    }

    private func undo() {
        if let failure = inbox.undoLastDecision() {
            undoRefusal = failure.reason
        } else {
            undoRefusal = nil
            decided = nil
            decidedRows = []
        }
    }
}
