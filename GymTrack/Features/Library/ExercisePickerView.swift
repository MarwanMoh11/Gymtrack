import SwiftUI

/// Modal search used when adding an exercise to a plan day or a live session.
struct ExercisePickerView: View {
    let onPick: (CatalogExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscle: Muscle?
    @State private var creating: ExerciseEditorView.Subject?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        // Searched once per pass rather than once per reader — the list, the
        // empty overlay and the create row each asked for it on every
        // keystroke, and each asking scored and sorted the whole library.
        let results = Array(ExerciseCatalog.shared.search(query, muscle: muscle).prefix(200))
        return NavigationStack {
            VStack(spacing: 0) {
                muscleFilter
                List {
                    ForEach(results) { exercise in
                        Button {
                            onPick(exercise)
                            Haptics.log()
                        } label: {
                            HStack {
                                ExerciseRow(exercise: exercise)
                                Image(systemName: "plus.circle.fill")
                                    .font(.system(size: 19))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .listRowBackground(Theme.surface)
                        .listRowSeparatorTint(Theme.hairline)
                    }

                    // The gym is the one place you can't go and look something
                    // up — you're standing at the machine. If the library hasn't
                    // got it, building it has to be possible from right here,
                    // and it drops into the workout as though it had been there
                    // all along.
                    if !trimmedQuery.isEmpty {
                        createRow(libraryHasMatches: !results.isEmpty)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .overlay {
                    if results.isEmpty && trimmedQuery.isEmpty {
                        EmptyStateView(icon: "magnifyingglass",
                                       title: "Nothing here",
                                       message: "Try a different muscle, or search for the machine by name.")
                    }
                }
            }
            .gtScreenBackground()
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises and machines")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $creating) { subject in
                ExerciseEditorView(subject: subject) { exercise in
                    onPick(exercise)
                }
            }
        }
        .gtSheetBackground()
    }

    private func createRow(libraryHasMatches: Bool) -> some View {
        Button {
            creating = .new(name: trimmedQuery)
        } label: {
            HStack(spacing: 12) {
                GlyphTile(symbol: "plus", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \u{201C}\(trimmedQuery)\u{201D}")
                        .font(Theme.rounded(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text(libraryHasMatches ? "Not the one you meant?" : "Not in the library yet")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 3)
        }
        .listRowBackground(Theme.surface)
        .listRowSeparatorTint(Theme.hairline)
    }

    private var muscleFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip("All", active: muscle == nil) { muscle = nil }
                ForEach(Muscle.allCases) { option in
                    chip(option.name, active: muscle == option) { muscle = option }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tick()
        } label: {
            Text(text)
                .font(Theme.rounded(13, weight: .semibold))
                .foregroundStyle(active ? .black : Theme.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? Theme.accent : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
