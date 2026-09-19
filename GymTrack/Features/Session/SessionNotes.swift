import SwiftUI
import SwiftData

/// Notes, at the two sizes a workout has: the session, and one exercise inside
/// it.
///
/// Both are the same shape — a few tags and a sentence, each of which works
/// with the other missing — and both are available rather than asked for.
/// Nothing here ever pops up, blocks a set, or has to be dismissed before you
/// can carry on lifting.
///
/// Per-set notes were considered and left out. The place you'd write one is the
/// place you have least attention to spare, and an exercise is a small enough
/// unit to say "left shoulder pinched on set 3" inside.

// MARK: - Writing

extension WorkoutSession {

    /// Takes what was typed about one exercise. The note is created by the
    /// first character and left alone after that; emptying it doesn't delete
    /// the row on the spot, because a keystroke isn't a decision — see
    /// `pruneEmptyNotes`, which is what makes "nothing written" leave nothing
    /// behind.
    func writeNote(_ text: String, about catalogID: String, named name: String, in context: ModelContext) {
        if let existing = note(for: catalogID) {
            existing.text = text
            existing.updatedAt = .now
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let note = ExerciseNote(catalogID: catalogID, exerciseName: name)
        note.text = text
        note.session = self
        context.insert(note)
    }

    /// Adds or removes one tag on one exercise — the same tap does both, so a
    /// mis-tap costs the tap that undoes it and nothing else.
    func toggleNoteTag(_ tag: NoteTag, about catalogID: String, named name: String, in context: ModelContext) {
        if let existing = note(for: catalogID) {
            existing.tags = existing.tags.toggling(tag)
            return
        }
        let note = ExerciseNote(catalogID: catalogID, exerciseName: name)
        note.tags = [tag]
        note.session = self
        context.insert(note)
    }

    /// The same, for the note about the whole session.
    func toggleNoteTag(_ tag: NoteTag) {
        noteTags = noteTags.toggling(tag)
    }

    /// Drops every note that has ended up saying nothing.
    ///
    /// Called when a composer closes and again when the session ends, rather
    /// than on each keystroke: deleting the row the moment the last character
    /// goes would mean creating and destroying a database object per backspace,
    /// and the export and both reading screens already ignore an empty note. By
    /// the time anything can read this session, there are none left.
    func pruneEmptyNotes(in context: ModelContext) {
        for note in exerciseNotes where note.isEmpty { context.delete(note) }
    }

    /// Drops the note about one exercise — for when the exercise itself is
    /// being taken out of the session, which leaves the note about nothing.
    func dropNote(about catalogID: String, in context: ModelContext) {
        guard let note = note(for: catalogID) else { return }
        context.delete(note)
    }
}

private extension Array where Element == NoteTag {
    func toggling(_ tag: NoteTag) -> [NoteTag] {
        contains(tag) ? filter { $0 != tag } : self + [tag]
    }
}

// MARK: - The tags

/// The five words, as chips. Tapping one is the whole interaction — there's no
/// confirming and no closing, and none of them has to be tapped at all.
struct NoteTagPicker: View {
    let selected: [NoteTag]
    let onToggle: (NoteTag) -> Void

    var body: some View {
        FlowRow(spacing: 6) {
            ForEach(NoteTag.allCases) { tag in
                let isOn = selected.contains(tag)
                Button { onToggle(tag) } label: {
                    Text(tag.label)
                        .font(Theme.rounded(12, weight: .bold))
                        .foregroundStyle(isOn ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.textSecondary))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background {
                            Capsule().fill(isOn
                                           ? AnyShapeStyle(tag.tint.gradient)
                                           : AnyShapeStyle(Color.white.opacity(0.07)))
                        }
                        .overlay {
                            Capsule().strokeBorder(isOn ? Color.clear : Color.white.opacity(0.06), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(tag.label)
                .accessibilityHint(tag.detail)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
    }
}

// MARK: - Reading one back

/// A note as it reads afterwards: the tags it was filed under, then the
/// sentence. Draws nothing when there's nothing to show, so a screen full of
/// exercises nobody said anything about looks exactly as it did before.
struct NoteReadout: View {
    let text: String
    let tags: [NoteTag]
    /// Shown above the note where it needs naming — the exercise it's about,
    /// on a screen that lists several.
    var caption: String?

    private var sentence: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        if !sentence.isEmpty || !tags.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                if let caption {
                    Text(caption.uppercased())
                        .font(Theme.microCaps)
                        .tracking(0.9)
                        .foregroundStyle(Theme.textTertiary)
                }
                if !tags.isEmpty {
                    FlowRow(spacing: 5) {
                        ForEach(tags) { tag in
                            Pill(text: tag.label, color: tag.tint)
                        }
                    }
                }
                if !sentence.isEmpty {
                    Text(sentence)
                        .font(Theme.rounded(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(spoken)
        }
    }

    private var spoken: String {
        let words = tags.map(\.detail).joined(separator: ", ")
        return [caption, words.isEmpty ? nil : words, sentence.isEmpty ? nil : sentence]
            .compactMap { $0 }
            .joined(separator: ". ")
    }
}

// MARK: - Writing one

/// The field itself, wherever a note is being written. Tags above, sentence
/// below, and nothing between them that has to be answered.
struct NoteEditor: View {
    @Binding var text: String
    let tags: [NoteTag]
    let onToggle: (NoteTag) -> Void
    var focus: FocusState<Bool>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NoteTagPicker(selected: tags, onToggle: onToggle)

            TextField("Anything worth remembering", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .textInputAutocapitalization(.sentences)
                .focused(focus)
                .gtWell(vertical: 9, horizontal: 11, radius: 12)
                // The well is bigger than the line of text inside it, and a tap
                // that lands in the margin of something that looks like a field
                // should still open it.
                .contentShape(Rectangle())
                .onTapGesture { focus.wrappedValue = true }
        }
    }
}

// MARK: - The session note

/// How the day went, in the lifter's own words — on the summary that opens the
/// moment a session ends, and on the same session in history afterwards.
///
/// Deliberately not in the logger. Mid-session the thing you have to say is
/// always about the exercise in front of you, and that has its own note on its
/// own card; a verdict on the session doesn't exist yet while you're still in
/// it. The summary is the point at which it does, and it's the same moment the
/// effort question uses — standing still, phone in hand, nothing else to do.
/// History keeps it editable because the summary is shown once, and a note you
/// can only write in one four-second window is a note being demanded.
struct SessionNoteCard: View {
    let session: WorkoutSession
    @Environment(\.modelContext) private var context

    @State private var draft = ""
    @FocusState private var writing: Bool

    var body: some View {
        VStack(spacing: 8) {
            SectionHeader("Note", action: writing ? (label: "Done", perform: { writing = false }) : nil)

            NoteEditor(text: $draft,
                       tags: session.noteTags,
                       onToggle: { tag in
                           session.toggleNoteTag(tag)
                           save()
                       },
                       focus: $writing)
                .gtCard(padding: 12)
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: writing)
        .onAppear { draft = session.notes }
        .onChange(of: draft) { _, updated in
            session.notes = updated
            save()
        }
    }

    /// Written as it's typed. A note is worth nothing if it survives only when
    /// you remember to close the screen the right way.
    private func save() {
        try? context.save()
    }
}
