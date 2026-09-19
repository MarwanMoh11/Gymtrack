import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(\.modelContext) private var context

    /// Both of these drive the catalog rather than the list directly. They're
    /// here so the list redraws the moment one changes — `ExerciseCatalog` is a
    /// plain singleton and can't announce anything by itself.
    @Query private var customRecords: [CustomExerciseRecord]
    @Query private var hiddenRecords: [HiddenExerciseRecord]

    @State private var query = ""
    @State private var muscle: Muscle?
    @State private var equipment: String?
    @State private var editing: ExerciseEditorView.Subject?
    @State private var showingHidden = false

    private var results: [CatalogExercise] {
        ExerciseCatalog.shared.search(query, muscle: muscle, equipment: equipment)
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if results.isEmpty {
                    emptyState
                    Spacer()
                } else {
                    List {
                        Section {
                            ForEach(results) { exercise in
                                NavigationLink {
                                    ExerciseDetailView(exercise: exercise)
                                } label: {
                                    ExerciseRow(exercise: exercise)
                                }
                                .listRowBackground(Theme.surface)
                                .listRowSeparatorTint(Theme.hairline)
                                .swipeActions(edge: .trailing) { actions(for: exercise) }
                            }
                            // Typing a name that isn't in the library is the
                            // moment you've discovered it's missing, so the way
                            // to add it belongs right there — not back up in the
                            // toolbar, with the name retyped from memory.
                            if !trimmedQuery.isEmpty {
                                createRow
                            }
                        } header: {
                            Text(results.count == 1 ? "1 exercise" : "\(results.count) exercises")
                                .font(Theme.eyebrow)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .gtScreenBackground()
            .navigationTitle("Library")
            .searchable(text: $query,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search exercises and machines")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            editing = .new(name: trimmedQuery)
                        } label: {
                            Label("New exercise", systemImage: "plus")
                        }
                        if !hiddenRecords.isEmpty {
                            Button {
                                showingHidden = true
                            } label: {
                                Label("Hidden (\(hiddenRecords.count))", systemImage: "eye.slash")
                            }
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(item: $editing) { subject in
                ExerciseEditorView(subject: subject)
            }
            .sheet(isPresented: $showingHidden) {
                HiddenExercisesView()
            }
        }
    }

    // MARK: - Rows

    /// Custom exercises are the user's own, so they can be changed or removed.
    /// Bundled ones can only be put away — the library is shipped data, and
    /// deleting from it would mean an app update quietly bringing it back.
    @ViewBuilder
    private func actions(for exercise: CatalogExercise) -> some View {
        if exercise.isCustom, let record = customRecords.first(where: { $0.id == exercise.id }) {
            Button {
                editing = .existing(record)
            } label: {
                Label("Edit", systemImage: "pencil")
            }
            .tint(Theme.accent)
        } else {
            Button {
                ExerciseVisibility.hide(exercise.id, context: context)
                Haptics.tick()
            } label: {
                Label("Hide", systemImage: "eye.slash")
            }
            .tint(.orange)
        }
    }

    private var createRow: some View {
        Button {
            editing = .new(name: trimmedQuery)
        } label: {
            HStack(spacing: 12) {
                GlyphTile(symbol: "plus", size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Add \u{201C}\(trimmedQuery)\u{201D}")
                        .font(Theme.rounded(15, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    Text("Build it yourself")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 4)
            }
            .padding(.vertical, 3)
        }
        .listRowBackground(Theme.surface)
    }

    private var emptyState: some View {
        EmptyStateView(
            icon: trimmedQuery.isEmpty ? "magnifyingglass" : "plus.circle",
            title: "Nothing matches",
            message: trimmedQuery.isEmpty
                ? "Try a different search, or clear the filters."
                : "No exercise here is called \u{201C}\(trimmedQuery)\u{201D}. If that's what your gym calls it, add it.",
            actionTitle: trimmedQuery.isEmpty ? "Clear filters" : "Add \u{201C}\(trimmedQuery)\u{201D}"
        ) {
            if trimmedQuery.isEmpty {
                query = ""; muscle = nil; equipment = nil
            } else {
                editing = .new(name: trimmedQuery)
            }
        }
    }

    // MARK: - Filters

    private var filterBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                Menu {
                    Button("All muscles") { muscle = nil }
                    ForEach(Muscle.Region.allCases) { region in
                        Section(region.rawValue) {
                            ForEach(Muscle.allCases.filter { $0.region == region }) { option in
                                Button(option.name) { muscle = option }
                            }
                        }
                    }
                } label: {
                    filterChip(muscle?.name ?? "Muscle", active: muscle != nil)
                }

                Menu {
                    Button("All equipment") { equipment = nil }
                    ForEach(ExerciseCatalog.shared.equipmentOptions, id: \.self) { option in
                        Button(option) { equipment = option }
                    }
                } label: {
                    filterChip(equipment ?? "Equipment", active: equipment != nil)
                }

                if muscle != nil || equipment != nil {
                    Button {
                        muscle = nil; equipment = nil
                        Haptics.tick()
                    } label: {
                        Label("Clear", systemImage: "xmark")
                            .font(Theme.rounded(12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .padding(.horizontal, 11).padding(.vertical, 8)
                            .background(Theme.panel, in: Capsule())
                            .overlay { Capsule().strokeBorder(Theme.edge, lineWidth: 1) }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func filterChip(_ text: String, active: Bool) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(Theme.rounded(13, weight: .semibold))
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(active ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.textSecondary))
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background {
            Capsule().fill(active ? AnyShapeStyle(SessionPhase.working.gradient) : AnyShapeStyle(Theme.panel))
                .shadow(color: active ? SessionPhase.working.glow : .clear, radius: 7, y: 2)
        }
        .overlay {
            Capsule().strokeBorder(active ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.edge), lineWidth: 1)
        }
    }
}

// MARK: - Row

struct ExerciseRow: View {
    let exercise: CatalogExercise

    var body: some View {
        HStack(spacing: 12) {
            GlyphTile(symbol: exercise.symbol, size: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(exercise.muscleSummary)
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if exercise.isCustom {
                Pill(text: "Custom", color: Theme.accent)
            }
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Hidden exercises

/// The exercises put away, and the way back. Trimming the library is only safe
/// to do freely if undoing it is this easy.
struct HiddenExercisesView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var hiddenRecords: [HiddenExerciseRecord]

    private var exercises: [CatalogExercise] {
        ExerciseCatalog.shared.hiddenExercises
    }

    var body: some View {
        NavigationStack {
            Group {
                if exercises.isEmpty {
                    VStack {
                        EmptyStateView(icon: "eye",
                                       title: "Nothing hidden",
                                       message: "Swipe an exercise in the library to put it away. It stays out of search until you bring it back.")
                        Spacer()
                    }
                } else {
                    List {
                        Section {
                            ForEach(exercises) { exercise in
                                HStack(spacing: 12) {
                                    ExerciseRow(exercise: exercise)
                                    Button {
                                        ExerciseVisibility.show(exercise.id, context: context)
                                        Haptics.tick()
                                    } label: {
                                        Text("Restore")
                                            .font(Theme.rounded(12, weight: .bold))
                                            .foregroundStyle(Theme.accent)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .listRowBackground(Theme.surface)
                                .listRowSeparatorTint(Theme.hairline)
                            }
                        } footer: {
                            Text("Hidden exercises stay out of search and browsing. Anything already in a plan or your history keeps its name and its numbers.")
                                .font(Theme.rounded(12, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .gtScreenBackground()
            .navigationTitle("Hidden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                if !exercises.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Restore all") {
                            ExerciseVisibility.showAll(context: context)
                            Haptics.success()
                        }
                    }
                }
            }
        }
        .presentationBackground(Theme.background)
    }
}
