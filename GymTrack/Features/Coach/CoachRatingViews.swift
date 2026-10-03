import SwiftUI

/// A score from one to five and an optional note, with a name field when the
/// phone has been handed to someone.
///
/// Nothing is asked until a score is chosen: the note and the button appear
/// with it, so a lifter who doesn't want to rate is never shown a form. Tapping
/// the chosen score again clears it.
struct CoachRatingForm: View {
    var asksName = false
    let submitLabel: String
    /// Returns whether the rating was stored, so a failure is said out loud
    /// instead of looking like a saved rating.
    let submit: (_ score: Int, _ name: String, _ note: String) -> Bool

    @State private var score = 0
    @State private var name = ""
    @State private var note = ""
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if asksName { nameField }
            stars
            if score > 0 {
                noteField
                Button(submitLabel) { send() }
                    .buttonStyle(PrimaryButtonStyle())
            }
            if failed {
                Text("The rating could not be saved, so nothing was recorded.")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.negative)
            }
        }
        .animation(.snappy, value: score)
    }

    private var nameField: some View {
        TextField("Your name (optional)", text: $name)
            .textInputAutocapitalization(.words)
            .font(Theme.rounded(15, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .gtWell()
    }

    private var noteField: some View {
        TextField("A note (optional)", text: $note, axis: .vertical)
            .lineLimit(1...4)
            .font(Theme.rounded(15, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .tint(Theme.accent)
            .gtWell()
    }

    private var stars: some View {
        HStack(spacing: 4) {
            ForEach(1...5, id: \.self) { value in
                Button {
                    score = score == value ? 0 : value
                    failed = false
                    Haptics.tick()
                } label: {
                    Image(systemName: value <= score ? "star.fill" : "star")
                        .gtIcon(size: 28, weight: .semibold, relativeTo: .title2, maxScale: 1.3)
                        .foregroundStyle(value <= score ? Theme.accent : Theme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(value) of 5")
                .accessibilityAddTraits(value == score ? .isSelected : [])
            }
        }
    }

    private func send() {
        if submit(score, name, note) {
            score = 0
            name = ""
            note = ""
            failed = false
            Haptics.success()
        } else {
            failed = true
        }
    }
}

/// The ratings a proposal already has, each removable, and a form for one of
/// the lifter's own. They are about the proposal whether or not it has been
/// decided, and `subject` says which one `CoachInbox` files them under: the
/// review screen rates the proposal in front of it, the history rates the
/// record.
struct CoachRatingsSection: View {
    let title: String
    var caption: String?
    var subject: CoachInbox.RatingSubject = .proposal
    let onHandOff: () -> Void

    private var inbox: CoachInbox { .shared }
    private var ratings: [CoachRating] { inbox.ratings(on: subject) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title)
            if let caption {
                Text(caption)
                    .font(Theme.rounded(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !ratings.isEmpty { existing }
            addOne
        }
    }

    private var existing: some View {
        VStack(spacing: 14) {
            ForEach(Array(ratings.enumerated()), id: \.offset) { _, rating in
                CoachRatingRow(rating: rating) { inbox.removeRating(rating) }
            }
        }
        .gtCard(padding: 14)
    }

    private var addOne: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Optional. How the change looks, or how it went once you trained on it.")
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            CoachRatingForm(submitLabel: "Save rating") { score, _, note in
                inbox.addRating(score: score, rater: .user, note: note, on: subject) != nil
            }
            Button { onHandOff() } label: {
                Label("Hand to someone", systemImage: "person.2")
            }
            .buttonStyle(SecondaryButtonStyle())
        }
        .gtCard()
    }
}

/// One rating. Removing is a single tap with no confirmation: a score tapped
/// by mistake is not data, and asking twice would make it feel like one.
struct CoachRatingRow: View {
    let rating: CoachRating
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(rating.raterLabel)
                        .font(Theme.rounded(15, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Label("\(rating.score) of 5", systemImage: "star.fill")
                        .font(Theme.rounded(13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                if let note = rating.note, !note.isEmpty {
                    Text(note)
                        .font(Theme.rounded(15, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(CoachWording.moment(rating.ratedAt))
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 8)
            Button(action: remove) {
                Image(systemName: "xmark.circle.fill")
                    .gtIcon(size: 20, relativeTo: .body)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove this rating")
        }
    }
}

/// The screen for the person the phone was handed to: who they are if they
/// want to say, a score, a note. It files the rating as someone else's, never
/// as the lifter's, and hands control back once it is stored.
struct CoachHandOffPanel: View {
    /// True where the reviewer's verdicts are on the screen behind this and
    /// are being kept from view.
    var hidesReviewer = false
    var subject: CoachInbox.RatingSubject = .proposal
    let finish: () -> Void

    private var inbox: CoachInbox { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Rate this plan change")
                .font(Theme.rounded(20, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text(explanation)
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            CoachRatingForm(asksName: true, submitLabel: "Done") { score, name, note in
                guard inbox.addRating(score: score, rater: .other, raterName: name, note: note, on: subject) != nil else {
                    return false
                }
                finish()
                return true
            }
            Button("Hand the phone back without rating", action: finish)
                .font(Theme.rounded(13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .gtCard()
    }

    private var explanation: String {
        let base = "Your rating is kept under your name and never counts as the lifter's own."
        return hidesReviewer ? base + " What the lifter and the reviewer decided stays hidden until you have rated." : base
    }
}
