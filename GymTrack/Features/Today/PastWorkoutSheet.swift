import SwiftUI
import SwiftData

/// Records a workout the app wasn't there for: a flat phone, a phone left at
/// home, or a build whose signing had run out.
///
/// The day's rows open with the numbers the logger would have offered on that
/// date, and nothing reaches the store until Save, and then only the sets that
/// were ticked. A row left as it opened is the app's guess, not something
/// lifted. The session is marked as logged afterwards, so its date counts for
/// the week, the streak and the rotation, and nothing reads a time off it. See
/// `WorkoutSession.isLoggedAfterwards`.
struct PastWorkoutSheet: View {
    let plan: Plan
    /// Finished sessions, as Today holds them.
    let history: [WorkoutSession]

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var dayID: UUID?
    @State private var exercises: [DraftExercise] = []
    @State private var editing: UUID?

    init(plan: Plan, history: [WorkoutSession]) {
        self.plan = plan
        self.history = history
        _date = State(initialValue: Calendar.current.date(byAdding: .day, value: -1, to: .now) ?? .now)
    }

    private var trainingDays: [PlanDay] {
        plan.orderedDays.filter { !$0.isRest && !$0.items.isEmpty }
    }

    private var selectedDay: PlanDay? { trainingDays.first { $0.id == dayID } }

    /// What the progression knew on the chosen day. A session trained since
    /// would otherwise lift the opening numbers past what was on offer then.
    private var earlier: [WorkoutSession] {
        let start = Calendar.current.startOfDay(for: date)
        return history.filter { $0.startedAt < start }
    }

    /// The day the plan would have offered on the chosen date.
    private var plannedDay: PlanDay? {
        plan.nextDay(on: date, after: earlier) ?? trainingDays.first
    }

    private var tickedCount: Int {
        exercises.reduce(0) { $0 + $1.rows.filter(\.isDone).count }
    }

    private var saveTitle: String {
        switch tickedCount {
        case 0: "Tick the sets you did"
        case 1: "Save 1 set"
        default: "Save \(tickedCount) sets"
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    whenCard
                    ForEach($exercises) { $exercise in
                        DraftExerciseCard(exercise: $exercise, editing: $editing)
                    }
                    Text("Only ticked sets are saved. A workout logged afterwards has no times or heart rate.")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button(saveTitle) { save() }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: tickedCount > 0))
                    .disabled(tickedCount == 0)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.background)
            }
            .gtScreenBackground()
            .navigationTitle("Log a past workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .onAppear {
                if dayID == nil { dayID = plannedDay?.id }
            }
            .onChange(of: dayID) { _, _ in rebuild() }
            .onChange(of: date) { _, _ in
                // Once a set is ticked the numbers are the lifter's, and a
                // second look at the calendar mustn't wipe them.
                guard tickedCount == 0 else { return }
                if let planned = plannedDay?.id, planned != dayID {
                    dayID = planned
                } else {
                    rebuild()
                }
            }
        }
        .gtSheetBackground()
    }

    private var whenCard: some View {
        VStack(spacing: 12) {
            DatePicker("Day", selection: $date, in: ...Date.now, displayedComponents: .date)
                .datePickerStyle(.compact)
                .tint(Theme.accent)
            Divider().overlay(Theme.edge)
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Workout")
                    .fixedSize()
                Spacer(minLength: 0)
                // A Menu rather than a menu-style Picker: the Picker draws its
                // label on one line, and a long day name was cut to an
                // ellipsis with no way to read which day was picked.
                Menu {
                    Picker("Workout", selection: $dayID) {
                        ForEach(trainingDays) { day in
                            Text(day.name).tag(Optional(day.id))
                        }
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(selectedDay?.name ?? "Choose")
                            .multilineTextAlignment(.trailing)
                            .fixedSize(horizontal: false, vertical: true)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
        }
        .font(Theme.rounded(15, weight: .semibold))
        .foregroundStyle(Theme.textPrimary)
        .gtCard(padding: 14)
    }

    private func rebuild() {
        editing = nil
        guard let day = selectedDay else {
            exercises = []
            return
        }
        var drafts: [DraftExercise] = []
        for row in SessionFactory.openingRows(for: day, history: earlier) {
            let draft = DraftRow(weightKg: row.weightKg, reps: row.reps, seconds: row.seconds)
            if let last = drafts.indices.last, drafts[last].index == row.exerciseIndex {
                drafts[last].rows.append(draft)
            } else {
                drafts.append(DraftExercise(item: row.item, index: row.exerciseIndex, rows: [draft]))
            }
        }
        exercises = drafts
    }

    private func save() {
        guard let day = selectedDay, tickedCount > 0 else { return }
        // Noon, so the date survives a daylight-saving shift or a trip across
        // a time zone either way; the hour itself means nothing. Never later
        // than now, or a session logged this morning would sort after one
        // trained this afternoon and hold the rotation back a day.
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        let anchor = min(noon, .now)
        let session = WorkoutSession(title: day.name, planDayID: day.id, planName: plan.name, startedAt: anchor)
        session.endedAt = anchor
        session.isLoggedAfterwards = true
        session.recordPlan(of: day)
        context.insert(session)

        for exercise in exercises {
            for (setIndex, row) in exercise.rows.filter(\.isDone).enumerated() {
                let set = SetLog(
                    catalogID: exercise.item.catalogID,
                    exerciseName: exercise.item.name,
                    exerciseOrder: exercise.index,
                    setIndex: setIndex,
                    weightKg: row.weightKg,
                    reps: row.reps,
                    seconds: row.seconds,
                    targetRepsLow: exercise.item.targetRepsLow,
                    targetRepsHigh: exercise.item.targetRepsHigh,
                    tracking: exercise.item.tracking
                )
                // Done, and never timed: `completedAt` stays empty rather than
                // holding the moment Save was tapped, which a reader would
                // take for when the set ended and measure rests from.
                set.isCompleted = true
                set.session = session
                context.insert(set)
            }
        }
        session.normalizeExerciseSlots()
        try? context.save()
        Haptics.success()
        dismiss()
    }
}

extension WorkoutSession {
    /// How long the session took, for a one-line summary. A session logged
    /// afterwards says so instead: its zero-length window is a placeholder,
    /// and "0s" would read as a workout that took no time.
    var lengthText: String {
        isLoggedAfterwards ? "logged afterwards" : duration.durationString
    }
}

// MARK: - Draft

/// One row on the sheet, held outside the store until Save.
private struct DraftRow: Identifiable {
    let id = UUID()
    var weightKg: Double
    var reps: Int
    var seconds: Int
    var isDone = false
}

/// One slot of the day and its rows.
private struct DraftExercise: Identifiable {
    let item: PlanItem
    /// The slot's place in the day, which becomes the sets' `exerciseOrder`.
    let index: Int
    var rows: [DraftRow]

    var id: Int { index }
}

private struct DraftExerciseCard: View {
    @Binding var exercise: DraftExercise
    @Binding var editing: UUID?

    private var scale: LoadScale { exercise.item.loadScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(exercise.item.name)
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button("Add set") { addSet() }
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            ForEach($exercise.rows) { $row in
                DraftRowView(row: $row,
                             number: number(of: row),
                             tracking: exercise.item.tracking,
                             scale: scale,
                             editing: $editing)
            }
        }
        .gtCard(padding: 12)
    }

    private func number(of row: DraftRow) -> Int {
        (exercise.rows.firstIndex { $0.id == row.id } ?? 0) + 1
    }

    /// A set the plan didn't prescribe. It starts from the row above and
    /// counts as done, since adding it is the record; unticking still keeps it
    /// out of the store.
    private func addSet() {
        guard let last = exercise.rows.last else { return }
        let added = DraftRow(weightKg: last.weightKg, reps: last.reps, seconds: last.seconds, isDone: true)
        exercise.rows.append(added)
        editing = added.id
        Haptics.tick()
    }
}

private struct DraftRowView: View {
    @Binding var row: DraftRow
    let number: Int
    let tracking: TrackingMode
    let scale: LoadScale
    @Binding var editing: UUID?

    private var isEditing: Bool { editing == row.id }

    private var numbersStyle: AnyShapeStyle {
        row.isDone ? AnyShapeStyle(Theme.ink) : AnyShapeStyle(Theme.textSecondary)
    }

    private var tickStyle: AnyShapeStyle {
        row.isDone ? AnyShapeStyle(SessionPhase.done.tint) : AnyShapeStyle(Theme.textTertiary)
    }

    private var label: String {
        if tracking == .duration { return "\(row.seconds)s" }
        if row.weightKg == 0 { return row.reps == 1 ? "1 rep" : "\(row.reps) reps" }
        let load = tracking == .bodyweightReps ? "+\(scale.format(row.weightKg))" : scale.format(row.weightKg)
        return "\(load) × \(row.reps)"
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Text("Set \(number)")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                Spacer()
                Button {
                    withAnimation(.snappy) { editing = isEditing ? nil : row.id }
                } label: {
                    Text(label)
                        .font(Theme.number(15, weight: .semibold))
                        .foregroundStyle(numbersStyle)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Theme.panel, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Changes the numbers")
                Button {
                    row.isDone.toggle()
                    Haptics.tick()
                } label: {
                    Image(systemName: row.isDone ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(tickStyle)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.isDone ? "Set \(number), done" : "Set \(number), not done")
                .accessibilityHint(row.isDone ? "Leaves it out" : "Marks it done")
            }
            if isEditing { steppers }
        }
    }

    private var steppers: some View {
        HStack(spacing: 14) {
            if tracking == .duration {
                StepperField(title: "Time", value: secondsBinding, step: 5,
                             format: { String(format: "%.0f", $0) }, unit: "seconds")
            } else {
                StepperField(title: tracking == .bodyweightReps ? "Added weight" : "Weight",
                             value: weightBinding,
                             scale: scale,
                             format: { $0 == 0 && tracking == .bodyweightReps ? "BW" : scale.text($0) })
                StepperField(title: "Reps", value: repsBinding, step: 1,
                             format: { String(format: "%.0f", $0) }, unit: "reps",
                             maximum: Double(StepperEntry.maximumReps))
            }
        }
        .frame(maxWidth: .infinity)
    }

    // Changing a number ticks the set: dialling in what you lifted is saying
    // you lifted it, and a second tap to confirm would only be friction.

    private var weightBinding: Binding<Double> {
        Binding(get: { scale.display(row.weightKg) }, set: { typed in
            guard StepperEntry.accepts(typed, maximum: scale.displayCeiling,
                                       current: scale.display(row.weightKg)) else { return }
            row.weightKg = scale.kilograms(typed)
            row.isDone = true
        })
    }

    private var repsBinding: Binding<Double> {
        Binding(get: { Double(row.reps) }, set: { typed in
            guard let reps = StepperEntry.count(typed, maximum: StepperEntry.maximumReps,
                                                current: row.reps) else { return }
            row.reps = reps
            row.isDone = true
        })
    }

    private var secondsBinding: Binding<Double> {
        Binding(get: { Double(row.seconds) }, set: { typed in
            guard let seconds = StepperEntry.count(typed, maximum: StepperEntry.maximumSeconds,
                                                   current: row.seconds) else { return }
            row.seconds = seconds
            row.isDone = true
        })
    }
}
