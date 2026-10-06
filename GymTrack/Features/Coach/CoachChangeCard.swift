import SwiftUI

/// What the lifter said about one change. Nothing is preselected: a choice that
/// was never made must not be read as one.
enum CoachChoice {
    case accept
    case decline
}

/// One change from a coach review: the slot before and after, the coach's
/// reason, and what the reviewer made of it.
///
/// The same card serves three moments. With `choice` it asks for a decision;
/// with `outcome` it shows what was decided; with neither it only reads. A
/// change that cannot be applied is dimmed and says why, and never offers a
/// choice, since there is nothing for the choice to do.
struct CoachChangeCard: View {
    let row: CoachValidator.Row
    var choice: Binding<CoachChoice?>?
    var note: Binding<String>?
    var outcome: CoachChangeDecision.Outcome?
    var decidedNote: String?

    @State private var noteOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if showsSlot { slot }
            if let reason = row.change.reason, !reason.isEmpty { reasonBlock(reason) }
            reviewerBlock
            if let problem = row.status.reason { problemLine(problem) }
            if let decidedNote, !decidedNote.isEmpty { labelled("Your note", decidedNote) }
            if canChoose {
                choiceRow
                noteField
            }
        }
        .gtCard(dimmed: !row.status.isApplicable)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Pieces

    private var title: String { row.exerciseName ?? "A change to the plan" }

    private var canChoose: Bool { row.status.isApplicable && choice != nil && outcome == nil }

    private var showsSlot: Bool { !(row.before.isEmpty && row.after.isEmpty) }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.rounded(17, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let day = row.dayName {
                    Text(day)
                        .font(Theme.rounded(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 8)
            badge
        }
    }

    @ViewBuilder private var badge: some View {
        if let outcome {
            Pill(text: outcome.label, color: outcome.tint)
        } else if case .stale = row.status {
            Pill(text: "Out of date", color: Theme.warning)
        } else if case .invalid = row.status {
            Pill(text: "Can't be applied", color: Theme.negative)
        }
    }

    private var slot: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                beforeText.lineLimit(1).fixedSize(horizontal: true, vertical: false)
                arrow("arrow.right")
                afterText.lineLimit(1).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 4) {
                beforeText
                arrow("arrow.down")
                afterText
            }
        }
        .gtWell()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.before), changing to \(row.after)")
    }

    private var beforeText: some View {
        Text(row.before)
            .font(Theme.rounded(15, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
    }

    private var afterText: some View {
        Text(row.after)
            .font(Theme.rounded(15, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
    }

    private func arrow(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .gtIcon(size: 13, weight: .bold, relativeTo: .footnote)
            .foregroundStyle(Theme.textTertiary)
            .accessibilityHidden(true)
    }

    private func labelled(_ label: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(Theme.eyebrow)
                .tracking(1.2)
                .foregroundStyle(Theme.textTertiary)
            Text(text)
                .font(Theme.rounded(15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func reasonBlock(_ reason: String) -> some View {
        labelled(isDisputed ? "The coach's reason" : "Why", reason)
    }

    private func problemLine(_ problem: String) -> some View {
        Text(problem)
            .font(Theme.rounded(13, weight: .semibold))
            .foregroundStyle(Theme.warning)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Reviewer

    private var isDisputed: Bool { row.change.review?.disputed == true }

    @ViewBuilder private var reviewerBlock: some View {
        if let review = row.change.review, review.hasSomethingToSay {
            if review.disputed == true {
                disputedBlock(review)
            } else {
                reviewerLine(review)
            }
        }
    }

    private func reviewerLine(_ review: CoachReviewNote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(review.tint).frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(review.line)
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            if let text = review.trimmedNote {
                Text(text)
                    .font(Theme.rounded(15, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Both sides at once. The reviewer kept objecting after a second look and
    /// the lifter kept the change anyway; hiding either side would make that
    /// look like agreement.
    private func disputedBlock(_ review: CoachReviewNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Pill(text: "Disputed", color: Theme.warning)
            Text("The reviewer still objected after a second look, and this change was kept anyway.")
                .font(Theme.rounded(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            labelled("The reviewer's objection", review.trimmedNote ?? "No note was left.")
        }
        .gtWell()
    }

    // MARK: - Deciding

    private var choiceRow: some View {
        HStack(spacing: 10) {
            CoachChoiceButton(title: "Accept", symbol: "checkmark", isAccept: true,
                              isSelected: choice?.wrappedValue == .accept) { pick(.accept) }
            CoachChoiceButton(title: "Decline", symbol: "xmark", isAccept: false,
                              isSelected: choice?.wrappedValue == .decline) { pick(.decline) }
        }
    }

    private func pick(_ value: CoachChoice) {
        choice?.wrappedValue = value
        Haptics.tick()
    }

    /// Behind a disclosure so a lifter who has nothing to add never sees a
    /// text field.
    @ViewBuilder private var noteField: some View {
        if let note {
            DisclosureGroup(isExpanded: $noteOpen) {
                TextField("Why, if you want to say", text: note, axis: .vertical)
                    .lineLimit(1...4)
                    .font(Theme.rounded(15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .gtWell()
                    .padding(.top, 8)
            } label: {
                Text(note.wrappedValue.isEmpty ? "Add a note" : "Your note")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .tint(Theme.textSecondary)
        }
    }
}

/// Accept or Decline. Accept lights up in the accent; Decline lifts without a
/// colour, since declining a suggestion is not a warning.
private struct CoachChoiceButton: View {
    let title: String
    let symbol: String
    let isAccept: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .gtIcon(size: 13, weight: .bold, relativeTo: .footnote)
                Text(title)
                    .font(Theme.rounded(16, weight: .bold))
            }
            .foregroundStyle(labelStyle)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background { fill }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Theme.edge, lineWidth: 1) }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 14, style: .continuous) }

    private var labelStyle: Color {
        if isSelected && isAccept { return Color.black }
        return isSelected ? Theme.textPrimary : Theme.textSecondary
    }

    @ViewBuilder private var fill: some View {
        if isSelected && isAccept {
            Theme.accent
        } else if isSelected {
            Theme.surfaceRaised.overlay(Color.white.opacity(0.14))
        } else {
            Theme.surface
        }
    }
}

// MARK: - Reviewer wording

private extension CoachReviewNote {

    var trimmedNote: String? {
        let text = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }

    /// The verdict in a word, or nil for one this app does not know. An
    /// unfamiliar verdict from a newer coach is shown as a plain reviewer's
    /// note rather than guessed at.
    var verdictWord: String? {
        switch verdict?.lowercased() {
        case "agree": "agrees"
        case "doubt": "has doubts"
        case "reject": "objects"
        default: nil
        }
    }

    var line: String { verdictWord.map { "Reviewer \($0)" } ?? "Reviewer's note" }

    var tint: Color {
        switch verdict?.lowercased() {
        case "agree": Theme.positive
        case "doubt": Theme.warning
        case "reject": Theme.negative
        default: Theme.textTertiary
        }
    }

    var hasSomethingToSay: Bool { verdictWord != nil || trimmedNote != nil || disputed == true }
}
