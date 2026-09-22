import SwiftUI
import SwiftData

/// Building an exercise the library doesn't have, or correcting one you built.
///
/// The gym decides what the machines are called, not the app: the bundled
/// library can't know that yours says "Iso Row" on the frame, or that the plate
/// tower in the corner has no name at all. Anything you can name, you can log —
/// and once named, it behaves like any other exercise, with the same history,
/// the same charts and the same progression.
struct ExerciseEditorView: View {

    /// What the sheet was opened on. `new` carries whatever was in the search
    /// box, so discovering something is missing and adding it is one tap and no
    /// retyping.
    enum Subject: Identifiable {
        case new(name: String)
        case existing(CustomExerciseRecord)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let record): record.id
            }
        }
    }

    let subject: Subject
    /// Handed the saved exercise. The picker uses it to drop a just-built
    /// exercise straight into the workout — having named the thing you're
    /// standing in front of, being returned to an empty search box and made to
    /// find it again would be absurd.
    var onSave: ((CatalogExercise) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    /// In the order they were picked, because the order is data: the first
    /// muscle is the one the exercise is credited to in full on the heat map
    /// and in the weekly split, and the second gets half. Kept in a set, they
    /// were saved in whatever order the hash gave that day, so a hip thrust
    /// could go in as a hamstring exercise with the glutes behind it.
    @State private var muscles: [Muscle] = []
    /// Picked order too, so the label under the name doesn't reshuffle itself
    /// every time the exercise is saved.
    @State private var equipment: [String] = []
    @State private var tracking: TrackingMode = .weightReps
    @State private var confirmingDelete = false
    /// Counted when Delete is tapped and not before. The alert's message is
    /// built on every pass of the body, so reading the counts from there
    /// fetched every plan slot and every logged set in the store on each
    /// keystroke in the name field.
    @State private var usage = Usage(plans: 0, sets: 0)
    @State private var didLoad = false
    @State private var hasSets = false
    @State private var operationError: String?

    private var record: CustomExerciseRecord? {
        if case .existing(let record) = subject { return record }
        return nil
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// An exercise that already goes by this name — bundled or custom. Worth
    /// saying out loud: the reason someone is here is usually that search
    /// didn't find it, and a near-miss spelling is a common reason why.
    private var clash: CatalogExercise? {
        ExerciseCatalog.shared.existing(named: trimmedName, excluding: record?.id)
    }

    private var canSave: Bool { !trimmedName.isEmpty && !muscles.isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Iso-Lateral Row", text: $name)
                        .autocorrectionDisabled()
                } header: {
                    Text("Name")
                } footer: {
                    if let clash {
                        Label("\(clash.name) is already in your library.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(.orange)
                    } else {
                        Text("Call it whatever the gym calls it — that's what you'll search for.")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("Tracking", selection: $tracking) {
                        ForEach(TrackingMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .disabled(hasSets)
                } header: {
                    Text("How is it measured?")
                } footer: {
                    if hasSets {
                        Text("Tracking stays fixed once this exercise has sets. Create a new exercise to measure it a different way; the old numbers keep their meaning.")
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach(Muscle.Region.allCases) { region in
                        ForEach(Muscle.allCases.filter { $0.region == region }) { option in
                            toggleRow(option.name, isOn: muscles.contains(option),
                                      note: muscles.first == option ? "Main" : nil) {
                                toggle(option, in: &muscles)
                            }
                        }
                    }
                } header: {
                    Text("Muscles worked")
                } footer: {
                    Text("Drives the heatmap and the weekly volume split. Pick the ones it really trains, the main one first.")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                Section {
                    ForEach(Self.equipmentOptions, id: \.self) { option in
                        toggleRow(option, isOn: equipment.contains(option)) {
                            toggle(option, in: &equipment)
                        }
                    }
                } header: {
                    Text("Equipment")
                } footer: {
                    Text("Sets the starting weight steps — a pin stack moves in bigger jumps than a barbell. You can correct it per exercise later.")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                if record != nil {
                    Section {
                        Button(role: .destructive) {
                            usage = countUsage()
                            confirmingDelete = true
                        } label: {
                            Label("Delete exercise", systemImage: "trash")
                                .foregroundStyle(Theme.negative)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .gtScreenBackground()
            .navigationTitle(record == nil ? "New exercise" : "Edit exercise")
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
            .alert("Delete this exercise?", isPresented: $confirmingDelete) {
                Button("Keep it", role: .cancel) {}
                Button("Delete", role: .destructive) { delete() }
            } message: {
                Text(deleteMessage)
            }
            .alert("Couldn't update exercise", isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )) {
                Button("OK") { operationError = nil }
            } message: {
                Text(operationError ?? "Please try again.")
            }
            .task {
                // Once only: re-running on every redraw would fight the fields
                // while they're being typed into.
                guard !didLoad else { return }
                didLoad = true
                load()
            }
        }
        .gtSheetBackground()
    }

    private static let equipmentOptions = [
        "Barbell", "Dumbbell", "Machine", "Cable", "Kettlebell", "Band", "Bench", "Plate",
    ]

    private func toggle<Value: Equatable>(_ value: Value, in list: inout [Value]) {
        if let index = list.firstIndex(of: value) {
            list.remove(at: index)
        } else {
            list.append(value)
        }
    }

    private func toggleRow(_ title: String, isOn: Bool, note: String? = nil,
                           toggle: @escaping () -> Void) -> some View {
        Button {
            toggle()
            Haptics.tick()
        } label: {
            HStack {
                Text(title).foregroundStyle(Theme.textPrimary)
                Spacer()
                if let note {
                    Text(note)
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
                if isOn {
                    Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                }
            }
        }
    }

    // MARK: - Loading and saving

    private func load() {
        switch subject {
        case .new(let seed):
            name = seed
        case .existing(let record):
            name = record.name
            var seen = Set<Muscle>()
            muscles = record.muscles.filter { seen.insert($0).inserted }
            equipment = record.equipment
            tracking = record.tracking
            let id = record.id
            // A failed count locks the choice instead of risking a change to
            // what old sets mean. Save checks again before writing.
            hasSets = ((try? context.fetchCount(FetchDescriptor<SetLog>(
                predicate: #Predicate { $0.catalogID == id }))) ?? 1) > 0
        }
    }

    private func save() {
        let saved: CustomExerciseRecord
        do {
            if let record {
                if record.tracking != tracking {
                    let id = record.id
                    let count = try context.fetchCount(FetchDescriptor<SetLog>(
                        predicate: #Predicate { $0.catalogID == id }))
                    guard count == 0 else {
                        hasSets = true
                        tracking = record.tracking
                        operationError = "This exercise now has sets. Its tracking can't change without changing what those sets mean."
                        return
                    }
                }
                record.apply(name: trimmedName,
                             muscles: muscles,
                             equipment: equipment,
                             tracking: tracking)
                saved = record
            } else {
                saved = CustomExerciseRecord(name: trimmedName,
                                             muscles: muscles,
                                             equipment: equipment,
                                             tracking: tracking)
                context.insert(saved)
            }
            try context.save()
        } catch {
            context.rollback()
            operationError = error.localizedDescription
            return
        }
        context.refreshCustomExercises()
        Haptics.success()
        onSave?(saved.asCatalogExercise)
        dismiss()
    }

    struct Usage {
        var plans: Int
        var sets: Int
    }

    /// What deleting actually costs, counted rather than guessed at. Only
    /// logged sets count: the rows of a workout still running that haven't
    /// been done yet are a plan, not history, and calling them logged would
    /// overstate what the delete touches.
    private func countUsage() -> Usage {
        guard let record else { return Usage(plans: 0, sets: 0) }
        let id = record.id
        let plans = (try? context.fetchCount(FetchDescriptor<PlanItem>(
            predicate: #Predicate { $0.catalogID == id }))) ?? 0
        let sets = (try? context.fetchCount(FetchDescriptor<SetLog>(
            predicate: #Predicate { $0.catalogID == id && $0.isCompleted }))) ?? 0
        return Usage(plans: plans, sets: sets)
    }

    private var deleteMessage: String {
        let plans = usage.plans, sets = usage.sets
        guard plans > 0 || sets > 0 else {
            return "It isn't used anywhere, so nothing else changes."
        }
        var parts: [String] = []
        if plans > 0 { parts.append("\(plans) plan slot\(plans == 1 ? "" : "s")") }
        if sets > 0 { parts.append("\(sets) logged set\(sets == 1 ? "" : "s")") }
        return "\(parts.joined(separator: " and ")) still name this exercise. They keep the name and the numbers, but it stops being something you can add to a workout. Hiding it instead leaves it whole."
    }

    private func delete() {
        guard let record else { return }
        do {
            let id = record.id
            let sets = try context.fetch(FetchDescriptor<SetLog>(
                predicate: #Predicate { $0.catalogID == id }))
            // Rows from older app versions have no snapshot. Give them the
            // current measurement before their catalog entry disappears.
            for set in sets where set.trackingRaw == nil {
                set.trackingRaw = record.tracking.rawValue
            }
            let items = try context.fetch(FetchDescriptor<PlanItem>(
                predicate: #Predicate { $0.catalogID == id }))
            for item in items where item.trackingRaw == nil {
                item.trackingRaw = record.tracking.rawValue
            }
            context.delete(record)
            try context.save()
        } catch {
            context.rollback()
            operationError = error.localizedDescription
            return
        }
        context.refreshCustomExercises()
        Haptics.warn()
        dismiss()
    }
}

extension ModelContext {
    /// Re-reads the user's own exercises into the shared catalog, so one that
    /// was just saved resolves immediately rather than on the next `@Query`
    /// refresh — the picker may be asking about it on this very frame.
    func refreshCustomExercises() {
        ExerciseCatalog.shared.setCustom(
            ((try? fetch(FetchDescriptor<CustomExerciseRecord>())) ?? []).map(\.asCatalogExercise)
        )
    }
}
