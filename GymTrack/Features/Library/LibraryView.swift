import SwiftUI
import SwiftData

struct LibraryView: View {
    @State private var query = ""
    @State private var muscle: Muscle?
    @State private var equipment: String?
    @State private var showingCreate = false

    private var results: [CatalogExercise] {
        ExerciseCatalog.shared.search(query, muscle: muscle, equipment: equipment)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                if results.isEmpty {
                    EmptyStateView(icon: "magnifyingglass",
                                   title: "Nothing matches",
                                   message: "Try a different search, or clear the filters.",
                                   actionTitle: "Clear filters") {
                        query = ""; muscle = nil; equipment = nil
                    }
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
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search 400+ exercises")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingCreate = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingCreate) { CreateExerciseView() }
        }
    }

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
                            .background(Theme.surface, in: Capsule())
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
        .foregroundStyle(active ? .black : Theme.textSecondary)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(active ? Theme.accent : Theme.surface, in: Capsule())
    }
}

// MARK: - Row

struct ExerciseRow: View {
    let exercise: CatalogExercise

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: exercise.symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 36, height: 36)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name)
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
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

// MARK: - Create custom exercise

struct CreateExerciseView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var muscles: Set<Muscle> = []
    @State private var equipment: Set<String> = []
    @State private var tracking: TrackingMode = .weightReps

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !muscles.isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("e.g. Cable Y-Raise", text: $name)
                        .autocorrectionDisabled()
                }
                .listRowBackground(Theme.surface)

                Section("How is it measured?") {
                    Picker("Tracking", selection: $tracking) {
                        ForEach(TrackingMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .listRowBackground(Theme.surface)

                Section("Muscles worked") {
                    ForEach(Muscle.allCases) { option in
                        Button {
                            if muscles.contains(option) { muscles.remove(option) } else { muscles.insert(option) }
                            Haptics.tick()
                        } label: {
                            HStack {
                                Text(option.name).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if muscles.contains(option) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)

                Section("Equipment") {
                    ForEach(["Barbell", "Dumbbell", "Machine", "Cable", "Kettlebell", "Band", "Bench", "Plate"], id: \.self) { option in
                        Button {
                            if equipment.contains(option) { equipment.remove(option) } else { equipment.insert(option) }
                            Haptics.tick()
                        } label: {
                            HStack {
                                Text(option).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                if equipment.contains(option) {
                                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .gtScreenBackground()
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .font(Theme.rounded(15, weight: .bold))
                        .disabled(!canSave)
                }
            }
        }
        .presentationBackground(Theme.background)
    }

    private func save() {
        let record = CustomExerciseRecord(
            name: name.trimmingCharacters(in: .whitespaces),
            muscles: Array(muscles),
            equipment: Array(equipment),
            tracking: tracking
        )
        context.insert(record)
        try? context.save()
        // Make it resolvable immediately, before the @Query update lands.
        ExerciseCatalog.shared.setCustom(
            ((try? context.fetch(FetchDescriptor<CustomExerciseRecord>())) ?? []).map(\.asCatalogExercise)
        )
        Haptics.success()
        dismiss()
    }
}
