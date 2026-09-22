import SwiftUI
import SwiftData

/// Edits a single day of a routine: which weekday it lands on, and the
/// exercises with their set/rep/rest prescriptions.
struct DayEditorView: View {
    @Bindable var day: PlanDay
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var openSessions: [WorkoutSession]

    @State private var showingPicker = false
    @State private var editingItem: PlanItem?
    @State private var confirmingDelete = false
    /// Set once the lifter has confirmed; the day goes when this screen does.
    /// Deleting it while the screen is still up would have the title and every
    /// row below it read a model whose row is gone, which SwiftData traps on.
    @State private var deleteOnLeave = false

    /// A session from this day is running, and it is reading this day's
    /// prescriptions for its rests and its suggestions. The day can't go while
    /// something is standing on it.
    private var isInUse: Bool { openSessions.contains { $0.planDayID == day.id } }

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

            // The way back out of "Add day". Until this existed a day, once
            // added, was in the routine for good.
            Section {
                Button(role: .destructive) { confirmingDelete = true } label: {
                    Label("Delete this day", systemImage: "trash")
                        .font(Theme.rounded(15, weight: .semibold))
                        .foregroundStyle(isInUse ? Theme.textTertiary : Theme.negative)
                }
                .disabled(isInUse)
            } footer: {
                if isInUse {
                    Text("A session from this day is running. Finish it, then this day can go.")
                }
            }
            .listRowBackground(Theme.surface)
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
        .confirmationDialog("Delete \(day.name.isEmpty ? "this day" : day.name)?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete day", role: .destructive) {
                deleteOnLeave = true
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Its exercises go with it. Sessions you've already logged from it are kept.")
        }
        .onDisappear {
            if deleteOnLeave { PlanDay.remove(day, in: context) }
            try? context.save()
        }
    }

    private func itemRow(_ item: PlanItem) -> some View {
        HStack(spacing: 12) {
            GlyphTile(symbol: item.catalog?.symbol ?? "dumbbell.fill", size: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.ink)
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

extension PlanDay {
    /// Takes a day out of its routine and closes the gap it leaves, so the days
    /// that remain still run 0, 1, 2 — `order` is what lays the week out, and a
    /// hole in it would have the next day added land beside an existing one.
    static func remove(_ day: PlanDay, in context: ModelContext) {
        let remaining = (day.plan?.orderedDays ?? []).filter { $0.id != day.id }
        context.delete(day)
        for (index, other) in remaining.enumerated() { other.order = index }
    }
}

// MARK: - Item editor

struct PlanItemEditor: View {
    @Bindable var item: PlanItem
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var showingScale = false

    /// What this exercise is loaded in — the same ladder the logger will use.
    private var scale: LoadScale { item.loadScale }

    /// The bottom of the range, taking the top up with it. Raised past the top
    /// on its own it left the plan asking for 15–12, and the progression, which
    /// reads the top as the point to add weight, then offered more load to
    /// someone who hadn't reached the bottom yet.
    private var lowRepsBinding: Binding<Int> {
        Binding(get: { item.targetRepsLow }, set: { low in
            item.targetRepsLow = low
            if item.targetRepsHigh < low { item.targetRepsHigh = low }
        })
    }

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
                        Stepper("Low: \(item.targetRepsLow)", value: lowRepsBinding, in: 1...50)
                        Stepper("High: \(item.targetRepsHigh)", value: $item.targetRepsHigh, in: item.targetRepsLow...60)
                    }
                    .listRowBackground(Theme.surface)

                    Section {
                        HStack {
                            Text(scale.format(item.targetWeightKg))
                                .font(Theme.number(17))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            // Walks the machine's own ladder, so a stack that
                            // only does tens is never left on a half-step.
                            Stepper("",
                                    onIncrement: {
                                        item.targetWeightKg = scale.step(kg: item.targetWeightKg, by: 1)
                                    },
                                    onDecrement: {
                                        item.targetWeightKg = scale.step(kg: item.targetWeightKg, by: -1)
                                    })
                            .labelsHidden()
                        }

                        HStack {
                            Text("Marked in")
                                .font(Theme.rounded(14, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            LoadScaleChip(scale: scale,
                                          isCustom: LoadScaleBook.shared.isCustomised(item.catalogID)) {
                                showingScale = true
                            }
                        }
                    } header: {
                        Text("Starting weight")
                    } footer: {
                        Text("Once you've logged this exercise, the app carries your last working weight forward automatically — in whatever this machine is marked in.")
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
        .gtSheetBackground()
        .sheet(isPresented: $showingScale) {
            if let catalog = item.catalog {
                LoadScaleSheet(exercise: catalog, referenceKg: item.targetWeightKg) { updated in
                    if item.targetWeightKg > 0 {
                        item.targetWeightKg = updated.snap(kg: item.targetWeightKg)
                    }
                }
            }
        }
    }
}
