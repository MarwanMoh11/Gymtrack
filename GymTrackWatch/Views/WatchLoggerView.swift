import SwiftUI

/// Logging from the wrist.
///
/// One set at a time — the one you're about to do — with the weight and reps
/// on the Digital Crown. Tap a number to hand the crown to it; the accent ring
/// says which one you're turning. That's the whole interaction, because it has
/// to work with one hand, chalked up, between sets.
///
/// The crown is attached to exactly one view and stays there. watchOS will not
/// reliably move focus between two crown targets on a tap — it is handed out
/// by the focus system, not by us — so the *selection* is plain state, and the
/// crown reads and writes whichever number that selection points at.
struct WatchLoggerView: View {

    let session: WatchSessionSnapshot
    var connector: WatchConnector
    var rest: WatchRestTimer

    @State private var weightDisplay: Double = 0
    @State private var repsValue: Double = 0
    @State private var secondsValue: Double = 0
    /// The number the crown is currently turning, and its live value.
    @State private var editing: Field = .weight
    @State private var crownValue: Double = 0
    @State private var showingExercises = false
    @FocusState private var isCrownFocused: Bool

    private enum Field: Hashable { case weight, reps, seconds }

    private var exercise: WatchExerciseSnapshot? { session.currentExercise }
    private var set: WatchSetSnapshot? { session.currentSet }
    private var unit: WeightUnit { session.unit }

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                header
                if rest.isRunning { restStrip }
                if let set, let exercise {
                    values(for: set, exercise: exercise)
                    stepperRow
                    logButton(set: set, exercise: exercise)
                } else {
                    allDone
                }
                undoButton
            }
            .padding(.horizontal, 2)
        }
        // The crown has to be attached the moment the screen appears — asking
        // the lifter to tap a number before they can turn anything would be a
        // tap too many.
        .defaultFocus($isCrownFocused, true)
        .navigationTitle(session.title)
        .sheet(isPresented: $showingExercises) {
            WatchExerciseListView(session: session, connector: connector)
        }
        .onAppear { load(set) }
        .onChange(of: set?.id) { _, _ in load(set) }
        // Claimed a beat after the view lands: focus set during the first
        // update pass is swallowed.
        .task {
            try? await Task.sleep(for: .milliseconds(350))
            isCrownFocused = true
        }
    }

    // MARK: - Header

    private var header: some View {
        Button {
            WatchHaptics.tick()
            showingExercises = true
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise?.name ?? "Freestyle")
                    .font(Theme.rounded(15, weight: .heavy))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                    .multilineTextAlignment(.leading)

                HStack(spacing: 5) {
                    Text("Set \(session.currentSetNumber)/\(exercise?.sets.count ?? 0)")
                        .font(Theme.number(11, weight: .bold))
                        .foregroundStyle(Theme.accent)
                    if let last = exercise?.lastTimeLabel {
                        Text("last \(last)")
                            .font(Theme.rounded(11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rest

    private var restStrip: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Theme.hairline, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: rest.progress)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 26, height: 26)

            Text(rest.label)
                .font(Theme.number(17, weight: .bold))
                .foregroundStyle(Theme.textPrimary)

            Spacer(minLength: 0)

            Button {
                rest.stop()
                connector.send(.stopRest)
            } label: {
                Text("Skip")
                    .font(Theme.rounded(12, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .buttonStyle(.bordered)
            .tint(Theme.surfaceRaised)
        }
        .padding(8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - The numbers

    @ViewBuilder
    private func values(for set: WatchSetSnapshot, exercise: WatchExerciseSnapshot) -> some View {
        Group {
            switch exercise.tracking {
            case .duration:
                tile(title: "seconds", value: "\(Int(secondsValue))", field: .seconds)
            case .weightReps, .bodyweightReps:
                HStack(spacing: 6) {
                    if exercise.tracking.logsWeight || set.weightKg > 0 {
                        tile(title: unit.short, value: trimmed(weightDisplay), field: .weight)
                    }
                    tile(title: "reps", value: "\(Int(repsValue))", field: .reps, caption: set.targetLabel)
                }
            }
        }
        // One crown target for the whole row. Which number it turns is
        // `editing`; the range and the step follow it.
        .focusable()
        .focused($isCrownFocused)
        .digitalCrownRotation(
            $crownValue,
            from: crownRange.lowerBound,
            through: crownRange.upperBound,
            by: crownStep,
            sensitivity: .medium,
            isContinuous: false,
            isHapticFeedbackEnabled: true
        )
        .onChange(of: crownValue) { _, turned in
            write(turned)
        }
    }

    /// A number, and whether the crown is on it.
    private func tile(title: String, value: String, field: Field, caption: String? = nil) -> some View {
        let isEditing = editing == field
        return VStack(spacing: 0) {
            Text(value)
                .font(Theme.number(26))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 3) {
                Text(title.uppercased())
                    .font(Theme.eyebrow)
                    .foregroundStyle(isEditing ? Theme.accent : Theme.textTertiary)
                if let caption {
                    Text("· \(caption)")
                        .font(Theme.rounded(10, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isEditing ? Theme.accent : Theme.hairline, lineWidth: isEditing ? 2 : 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { select(field) }
        .accessibilityLabel("\(title) \(value)")
        .accessibilityHint(isEditing ? "The Digital Crown changes this" : "Tap to turn this with the Digital Crown")
    }

    /// One increment either way on whichever number is selected.
    ///
    /// The crown is faster and the reason the screen is laid out this way, but
    /// it is invisible to anyone who has never used one, and awkward with a bar
    /// in the other hand. These are the same increment the crown uses, so the
    /// two agree.
    private var stepperRow: some View {
        HStack(spacing: 6) {
            stepButton(symbol: "minus", delta: -crownStep, verb: "Decrease")
            stepButton(symbol: "plus", delta: crownStep, verb: "Increase")
        }
    }

    private func stepButton(symbol: String, delta: Double, verb: String) -> some View {
        Button {
            step(by: delta)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 26)
        }
        .buttonStyle(.bordered)
        .tint(Theme.surfaceRaised)
        .accessibilityLabel("\(verb) \(editingName)")
    }

    private var editingName: String {
        switch editing {
        case .weight: "weight"
        case .reps: "reps"
        case .seconds: "seconds"
        }
    }

    private func step(by delta: Double) {
        let current = currentValue(of: editing)
        let next = min(max(current + delta, crownRange.lowerBound), crownRange.upperBound)
        guard next != current else { return }
        write(next)
        // Keep the crown where the buttons left off, or its next turn would
        // snap the number back to where it was.
        crownValue = next
        WatchHaptics.tick()
    }

    /// Hands the crown a different number.
    private func select(_ field: Field) {
        guard editing != field else { return }
        editing = field
        crownValue = currentValue(of: field)
        isCrownFocused = true
        WatchHaptics.tick()
    }

    /// What the crown writes back to, and the sane bounds for it.
    private func write(_ turned: Double) {
        switch editing {
        case .weight: weightDisplay = max(0, turned)
        case .reps: repsValue = max(0, turned.rounded())
        case .seconds: secondsValue = max(0, turned.rounded())
        }
    }

    private func currentValue(of field: Field) -> Double {
        switch field {
        case .weight: weightDisplay
        case .reps: repsValue
        case .seconds: secondsValue
        }
    }

    private var crownRange: ClosedRange<Double> {
        switch editing {
        case .weight: 0...(unit == .kg ? 400 : 880)
        case .reps: 0...50
        case .seconds: 5...600
        }
    }

    private var crownStep: Double {
        switch editing {
        case .weight: unit.step
        case .reps: 1
        case .seconds: 5
        }
    }

    // MARK: - Logging

    private func logButton(set: WatchSetSnapshot, exercise: WatchExerciseSnapshot) -> some View {
        Button {
            log(set: set, exercise: exercise)
        } label: {
            Label("Log set", systemImage: "checkmark")
                .font(Theme.rounded(15, weight: .heavy))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.accent)
        .foregroundStyle(.black)
    }

    private func log(set: WatchSetSnapshot, exercise: WatchExerciseSnapshot) {
        WatchHaptics.log()
        connector.logSet(
            set,
            weightKg: unit.toKg(weightDisplay),
            reps: Int(repsValue),
            seconds: Int(secondsValue)
        )
        // Start the rest here rather than waiting for the phone to say so —
        // the phone may be in a locker, and the countdown is the reason the
        // watch is on your wrist.
        if session.restAutoStart, exercise.restSeconds > 0 {
            rest.startLocal(seconds: exercise.restSeconds)
        }
    }

    private var allDone: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 28))
                .foregroundStyle(Theme.accent)
            Text("Every set logged")
                .font(Theme.rounded(15, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Swipe up to finish")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var undoButton: some View {
        if let last = lastCompletedSet {
            Button {
                WatchHaptics.tick()
                connector.undoSet(last)
            } label: {
                Label("Undo last set", systemImage: "arrow.uturn.backward")
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.surfaceRaised)
        }
    }

    /// The most recently logged set — the one an undo should take back.
    private var lastCompletedSet: WatchSetSnapshot? {
        session.exercises
            .flatMap(\.sets)
            .last { $0.isCompleted }
    }

    // MARK: - State

    /// Loads the set that's up into the dials, carrying last time's numbers
    /// when the set has none of its own.
    private func load(_ set: WatchSetSnapshot?) {
        guard let set else { return }
        weightDisplay = unit.snap(unit.fromKg(set.weightKg))
        repsValue = Double(set.reps > 0 ? set.reps : max(set.targetRepsLow, 1))
        secondsValue = Double(set.seconds > 0 ? set.seconds : 45)
        editing = defaultField
        crownValue = currentValue(of: editing)
    }

    /// Which number the crown should be on for this exercise.
    private var defaultField: Field {
        switch exercise?.tracking {
        case .duration: .seconds
        case .bodyweightReps: .reps
        default: .weight
        }
    }

    private func trimmed(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}

// MARK: - Jumping between exercises

/// The session's exercises, so the lifter can work out of order — supersets,
/// or a machine that's taken.
struct WatchExerciseListView: View {
    let session: WatchSessionSnapshot
    var connector: WatchConnector
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            list
        }
    }

    private var list: some View {
        List {
            ForEach(session.exercises) { exercise in
                Button {
                    WatchHaptics.tick()
                    connector.send(.focusExercise(catalogID: exercise.id))
                    dismiss()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: exercise.isComplete ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(exercise.isComplete ? Theme.accent : Theme.textTertiary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exercise.name)
                                .font(Theme.rounded(13, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .lineLimit(2)
                            Text("\(exercise.completedCount)/\(exercise.sets.count) sets")
                                .font(Theme.number(11, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.surface)
                )
            }
        }
        .navigationTitle("Exercises")
    }
}
