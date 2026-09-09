import SwiftUI
import SwiftData

/// Edits a single day of a routine: which weekday it lands on, and the
/// exercises with their set/rep/rest prescriptions.
struct DayEditorView: View {
    @Bindable var day: PlanDay
    @Environment(\.modelContext) private var context

    @State private var showingPicker = false
    @State private var editingItem: PlanItem?

    var body: some View {
        List {
            Section {
                TextField("Day name", text: $day.name)
                    .font(Theme.rounded(16, weight: .semibold))

                Picker("Scheduled on", selection: weekdayBinding) {
                    Text("Not scheduled").tag(0)
                    ForEach(1...7, id: \.self) { index in
                        Text(Calendar.current.weekdaySymbols[index - 1]).tag(index)
                    }
                }

                Toggle("Rest day", isOn: $day.isRest)
                    .tint(Theme.accent)
            }
            .listRowBackground(Theme.surface)

            if !day.isRest {
                Section {
                    ForEach(day.orderedItems) { item in
                        Button { editingItem = item } label: { itemRow(item) }
                    }
                    .onDelete(perform: delete)
                    .onMove(perform: move)

                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add exercise", systemImage: "plus.circle.fill")
                            .font(Theme.rounded(15, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                } header: {
                    Text("\(day.items.count) exercises · \(day.totalSets) sets")
                        .font(Theme.eyebrow)
                        .foregroundStyle(Theme.textTertiary)
                }
                .listRowBackground(Theme.surface)

                if !day.targetedMuscles.isEmpty {
                    Section("Muscles hit") {
                        FlowRow(spacing: 6) {
                            ForEach(day.targetedMuscles, id: \.self) { muscle in
                                Pill(text: muscle.name, color: Theme.accent)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .gtScreenBackground()
        .navigationTitle(day.name.isEmpty ? "Day" : day.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $showingPicker) {
            ExercisePickerView { exercise in
                add(exercise)
            }
        }
        .sheet(item: $editingItem) { item in
            PlanItemEditor(item: item)
        }
        .onDisappear { try? context.save() }
    }

    private func itemRow(_ item: PlanItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.catalog?.symbol ?? "dumbbell.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(prescription(item))
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer(minLength: 0)
            DisclosureChevron()
        }
    }

    private func prescription(_ item: PlanItem) -> String {
        let core = item.tracking == .duration
            ? "\(item.targetSets) × \(item.targetSeconds)s"
            : "\(item.targetSets) × \(item.repRangeLabel)"
        let rest = item.restSeconds == nil
            ? "\(item.resolvedRestSeconds)s rest (default)"
            : "\(item.resolvedRestSeconds)s rest"
        return "\(core) · \(rest)"
    }

    // MARK: - Mutations

    private var weekdayBinding: Binding<Int> {
        Binding(get: { day.weekday ?? 0 }, set: { day.weekday = $0 == 0 ? nil : $0 })
    }

    private func add(_ exercise: CatalogExercise) {
        let item = PlanItem(
            catalogID: exercise.id,
            name: exercise.name,
            order: day.items.count,
            targetSets: 3,
            targetRepsLow: exercise.tracking == .duration ? 0 : 8,
            targetRepsHigh: exercise.tracking == .duration ? 0 : 12
        )
        item.day = day
        context.insert(item)
        try? context.save()
    }

    private func delete(at offsets: IndexSet) {
        let ordered = day.orderedItems
        for index in offsets { context.delete(ordered[index]) }
        reindex()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var ordered = day.orderedItems
        ordered.move(fromOffsets: source, toOffset: destination)
        for (index, item) in ordered.enumerated() { item.order = index }
        try? context.save()
    }

    private func reindex() {
        for (index, item) in day.orderedItems.enumerated() { item.order = index }
        try? context.save()
    }
}

// MARK: - Item editor

struct PlanItemEditor: View {
    @Bindable var item: PlanItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    var body: some View {
        NavigationStack {
            Form {
                Section("Sets") {
                    Stepper("\(item.targetSets) sets", value: $item.targetSets, in: 1...12)
                        .font(Theme.rounded(15, weight: .semibold))
                }
                .listRowBackground(Theme.surface)

                if item.tracking == .duration {
                    Section("Time per set") {
                        Stepper("\(item.targetSeconds) seconds", value: $item.targetSeconds, in: 5...600, step: 5)
                            .font(Theme.rounded(15, weight: .semibold))
                    }
                    .listRowBackground(Theme.surface)
                } else {
                    Section("Rep range") {
                        Stepper("Low: \(item.targetRepsLow)", value: $item.targetRepsLow, in: 1...50)
                        Stepper("High: \(item.targetRepsHigh)", value: $item.targetRepsHigh, in: item.targetRepsLow...60)
                    }
                    .listRowBackground(Theme.surface)

                    Section("Starting weight") {
                        HStack {
                            Text(AppSettings.shared.weight(item.targetWeightKg))
                                .font(Theme.number(17))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Stepper("", value: weightBinding, in: 0...500, step: AppSettings.shared.weightUnit.step)
                                .labelsHidden()
                        }
                        Text("Once you've logged this exercise, the app carries your last working weight forward automatically.")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Picker("Rest", selection: $item.restSeconds) {
                        Text("Default (\(AppSettings.shared.defaultRestSeconds)s)")
                            .tag(Int?.none)
                        ForEach([45, 60, 75, 90, 120, 150, 180, 210, 240], id: \.self) { seconds in
                            Text(seconds >= 60 ? "\(seconds / 60)m \(seconds % 60 == 0 ? "" : "\(seconds % 60)s")" : "\(seconds)s")
                                .tag(Int?.some(seconds))
                        }
                    }
                    .pickerStyle(.wheel)
                    .frame(height: 110)
                } header: {
                    Text("Rest between sets")
                } footer: {
                    Text("Leave this on Default and the exercise follows the rest length in Settings.")
                }
                .listRowBackground(Theme.surface)

                Section("Notes") {
                    TextField("Cues, machine settings, seat height…", text: $item.notes, axis: .vertical)
                        .lineLimit(2...5)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .gtScreenBackground()
            .navigationTitle(item.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        try? context.save()
                        dismiss()
                    }
                    .font(Theme.rounded(15, weight: .bold))
                }
            }
        }
        .presentationBackground(Theme.background)
    }

    private var weightBinding: Binding<Double> {
        Binding(
            get: { AppSettings.shared.weightUnit.fromKg(item.targetWeightKg) },
            set: { item.targetWeightKg = AppSettings.shared.weightUnit.toKg(max(0, $0)) }
        )
    }
}
