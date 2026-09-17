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
    /// What the exercise in front of you is marked in, and what one click of
    /// the crown is worth on it. The leg press being stamped in pounds is as
    /// true on the wrist as it is on the phone.
    private var scale: LoadScale {
        exercise?.resolvedScale(sessionUnit: session.unit) ?? .standard(session.unit)
    }
    /// What the screen is coloured in right now.
    private var phase: SessionPhase { session.phase(resting: rest.isRunning) }

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
        .watchScreenTint(phase)
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
            HStack(spacing: 8) {
                WatchGlyphTile(symbol: phase.glyph, tint: phase.tint, size: 26)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise?.name ?? "Freestyle")
                        .font(Theme.rounded(15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.leading)

                    HStack(spacing: 5) {
                        // Once everything is logged there is no current set to
                        // name, so the line switches to the session's total
                        // rather than pointing at a set that's already done.
                        // A warm-up drops the counter and says what it is. The
                        // wrist is where you most need to know whether the set
                        // you're about to log is one the app will measure you
                        // on, and "Warm-up 2/5" makes you do that arithmetic.
                        Text(phase == .done
                             ? "\(session.completedSets)/\(session.totalSets) sets"
                             : (set?.isWarmup == true
                                ? "Warm-up"
                                : "Set \(session.currentSetNumber)/\(exercise?.sets.count ?? 0)"))
                            .font(Theme.number(11, weight: .bold))
                            .foregroundStyle(set?.isWarmup == true && phase != .done
                                             ? SessionPhase.resting.gradient
                                             : phase.gradient)
                        if let last = exercise?.lastTimeLabel {
                            Text("last \(last)")
                                .font(Theme.rounded(11, weight: .medium))
                                .foregroundStyle(Theme.textTertiary)
                                .lineLimit(1)
                        }
                    }
                    .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Rest

    /// The rest, when there is one. Amber and ringed — the same rest the Lock
    /// Screen is showing, wearing the same colour.
    private var restStrip: some View {
        HStack(spacing: 8) {
            WatchRestRing(progress: rest.progress, phase: .resting, size: 28)

            VStack(alignment: .leading, spacing: 0) {
                Text(rest.label)
                    .font(Theme.number(18, weight: .bold))
                    .foregroundStyle(SessionPhase.resting.tint)
                    .shadow(color: SessionPhase.resting.glow, radius: 5)
                Text("REST")
                    .font(Theme.microCaps)
                    .tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: 0)

            Button {
                rest.stop()
                connector.send(.stopRest)
            } label: {
                Text("Skip")
            }
            .buttonStyle(WatchQuietButtonStyle(tint: Theme.textPrimary, size: 12, compact: true))
            .fixedSize()
        }
        .watchCard(padding: 8, radius: 12, phase: .resting)
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
                        tile(title: scale.unit.short, value: trimmed(weightDisplay), field: .weight)
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
        return WatchValueTile(title: title, value: value, caption: caption,
                              isEditing: isEditing, phase: phase)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onTapGesture { select(field) }
            .accessibilityLabel("\(title) \(value)")
            .accessibilityHint(isEditing ? "The Digital Crown changes this"
                                         : "Tap to turn this with the Digital Crown")
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
                .frame(minHeight: 14)
        }
        .buttonStyle(WatchQuietButtonStyle(tint: Theme.textPrimary))
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
        let stepped = editing == .weight
            ? scale.step(display: current, by: delta > 0 ? 1 : -1)
            : current + delta
        let next = min(max(stepped, crownRange.lowerBound), crownRange.upperBound)
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
        // Onto the ladder: the crown is the only way in here — there is no
        // keypad to reach a weight between two pins — so a turn should always
        // land on something the machine can be set to.
        case .weight: weightDisplay = scale.snap(display: max(0, turned))
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
        case .weight: 0...scale.displayCeiling
        case .reps: 0...50
        case .seconds: 5...600
        }
    }

    private var crownStep: Double {
        switch editing {
        case .weight: scale.increment
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
        }
        // Always lime, even mid-rest: this is the button that ends the rest,
        // so colouring it amber would be the screen arguing with itself.
        .buttonStyle(WatchProminentButtonStyle(phase: .working))
    }

    private func log(set: WatchSetSnapshot, exercise: WatchExerciseSnapshot) {
        WatchHaptics.log()
        connector.logSet(
            set,
            weightKg: scale.kilograms(weightDisplay),
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
        VStack(spacing: 7) {
            WatchGlyphTile(symbol: "checkmark", tint: SessionPhase.done.tint, size: 42)
                .shadow(color: SessionPhase.done.tint.opacity(0.3), radius: 9)
            Text("Every set logged")
                .font(Theme.rounded(15, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("Swipe left to finish")
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
            }
            .buttonStyle(WatchQuietButtonStyle(tint: Theme.textSecondary, weight: .semibold, size: 12))
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
        weightDisplay = scale.display(set.weightKg)
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

    private func trimmed(_ value: Double) -> String { scale.text(value) }
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
                    HStack(spacing: 9) {
                        // The ring carries the count, so a glance down the list
                        // says how far into each exercise you are without
                        // reading a single fraction.
                        WatchRestRing(progress: exercise.progress,
                                      phase: exercise.isComplete ? .done : .working,
                                      size: 22, lineWidth: 3)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(exercise.name)
                                .font(Theme.rounded(13, weight: .bold))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(2)
                            Text("\(exercise.completedCount)/\(exercise.sets.count) sets")
                                .font(Theme.number(11, weight: .semibold))
                                .foregroundStyle(exercise.isComplete
                                                 ? AnyShapeStyle(SessionPhase.done.gradient)
                                                 : AnyShapeStyle(Theme.textSecondary))
                        }
                    }
                }
                .listRowBackground(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [Theme.surfaceRaised, Theme.surface],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.hairline, lineWidth: 1)
                        )
                )
            }
        }
        .navigationTitle("Exercises")
    }
}
