import SwiftUI
import SwiftData
import Combine

/// The logging screen. Optimised for use mid-set: the next set is always
/// expanded with large steppers, everything else collapses to a summary row.
///
/// Presented as a sheet the user owns — pull the grab handle down (or tap
/// *Minimise*) and the session keeps running behind the app, in the dock bar
/// and on the Lock Screen. Discarding is a separate, deliberate act at the
/// bottom of the screen; it is no longer the price of getting out of here.
struct ActiveWorkoutView: View {
    @Bindable var workout: ActiveWorkout
    let onMinimise: () -> Void
    let onClose: (WorkoutSession?) -> Void

    @Environment(\.modelContext) private var context
    /// The watch's live numbers, when one is recording alongside the phone.
    @State private var watch = WatchBridge.shared
    @State private var elapsed: TimeInterval = 0
    @State private var showingAddExercise = false
    @State private var showingFinishConfirm = false
    @State private var showingDiscardConfirm = false
    @State private var dragOffset: CGFloat = 0

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                header
                content
            }

            if workout.restTimer.isRunning {
                RestTimerBar(timer: workout.restTimer,
                             subject: workout.ratingSubject,
                             onRate: { feel in
                                 if let set = workout.ratingSubject { workout.rate(set, feel: feel) }
                             },
                             onClear: {
                                 if let set = workout.ratingSubject { workout.clearRating(set) }
                             })
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .gtSessionTint(workout.phase)
        .background(
            RoundedRectangle(cornerRadius: dragOffset > 0 ? 38 : 0, style: .continuous)
                .fill(Theme.background)
                .ignoresSafeArea()
        )
        .offset(y: dragOffset)
        .onAppear { elapsed = workout.session.duration }
        .onReceive(ticker) { _ in elapsed = workout.session.duration }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: workout.restTimer.isRunning)
        .sheet(isPresented: $showingAddExercise) {
            ExercisePickerView { exercise in
                workout.addExercise(exercise)
                showingAddExercise = false
            }
        }
        .alert("Finish this workout?", isPresented: $showingFinishConfirm) {
            Button("Keep going", role: .cancel) {}
            Button("Finish workout") { finish() }
        } message: {
            Text(finishMessage)
        }
        .alert("Discard this workout?", isPresented: $showingDiscardConfirm) {
            Button("Keep the workout", role: .cancel) {}
            Button(discardActionTitle, role: .destructive) {
                workout.discard()
                onClose(nil)
            }
        } message: {
            Text("This can't be undone. To step away without losing anything, minimise it instead.")
        }
    }

    // MARK: - Header

    /// Grab handle, the session clock, and the two ways out — leaving (which
    /// keeps everything) on the left, finishing on the right.
    private var header: some View {
        VStack(spacing: 9) {
            grabHandle

            HStack(spacing: 8) {
                Button(action: minimise) {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .black))
                        Text("Minimise")
                            .font(Theme.rounded(12, weight: .bold))
                    }
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .background(Theme.panel, in: Capsule())
                    .overlay { Capsule().strokeBorder(Theme.edge, lineWidth: 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Minimise workout")
                .accessibilityHint("Keeps the session running in the background")

                Spacer(minLength: 4)

                Text(elapsed.clockString)
                    .font(Theme.number(20))
                    .foregroundStyle(workout.phase.tint)
                    .shadow(color: workout.phase.glow, radius: 8)
                    .accessibilityLabel("Elapsed \(elapsed.durationString)")

                Spacer(minLength: 4)

                // Green once everything is logged: the screen stops asking for
                // sets and starts asking to be closed.
                Button { showingFinishConfirm = true } label: {
                    Text("Finish")
                        .font(Theme.rounded(13, weight: .bold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(finishTint.gradient, in: Capsule())
                        .shadow(color: finishTint.glow, radius: 8, y: 2)
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 6) {
                Text("\(workout.session.title) · \(workout.completedCount) of \(workout.totalCount) sets")
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)

                if let heartRate = watch.liveMetrics?.currentHeartRate {
                    LiveHeartRatePill(bpm: heartRate)
                }
            }

            headerProgressLine
        }
        .padding(.horizontal, 14)
        .padding(.top, 6)
        .contentShape(Rectangle())
        .gesture(minimiseDrag)
    }

    private var grabHandle: some View {
        Capsule()
            .fill(Theme.textTertiary.opacity(dragOffset > 0 ? 0.8 : 0.45))
            .frame(width: 40, height: 5)
            .padding(.vertical, 4)
    }

    /// One tick per set, the same bar the Lock Screen card draws — so the thing
    /// you glance at on your phone and the thing you glance at on your wrist
    /// are measuring in the same units.
    private var headerProgressLine: some View {
        PhaseProgressBar(completed: workout.completedCount,
                         total: workout.totalCount,
                         phase: workout.phase,
                         height: 4,
                         maxTicks: 24)
            .animation(.spring(response: 0.45, dampingFraction: 0.9), value: workout.completedCount)
            .padding(.bottom, 8)
    }

    /// The finish button leads with green the moment there's nothing left to
    /// log, whether or not a rest happens to be running.
    private var finishTint: SessionPhase {
        workout.totalCount > 0 && workout.completedCount >= workout.totalCount ? .done : .working
    }

    /// Pull the header down to put the session away — the same gesture people
    /// already use on every other sheet in iOS.
    private var minimiseDrag: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                dragOffset = max(0, value.translation.height * (value.translation.height > 0 ? 1 : 0.2))
            }
            .onEnded { value in
                let shouldMinimise = value.translation.height > 110
                    || value.predictedEndTranslation.height > 300
                if shouldMinimise {
                    minimise()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { dragOffset = 0 }
                }
            }
    }

    private var discardActionTitle: String {
        let logged = workout.completedCount
        guard logged > 0 else { return "Discard" }
        return "Delete \(logged) logged set\(logged == 1 ? "" : "s")"
    }

    private var finishMessage: String {
        let remaining = workout.totalCount - workout.completedCount
        return remaining > 0
            ? "\(remaining) set\(remaining == 1 ? "" : "s") not logged — they'll be dropped from the record."
            : "Every set logged. Nice work."
    }

    // MARK: - Body

    private var content: some View {
        ScrollView {
            VStack(spacing: 14) {
                progressHeader

                ForEach(workout.groups) { group in
                    ExerciseLogCard(workout: workout, group: group)
                }

                Button {
                    showingAddExercise = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 4)

                discardFooter
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)
            .padding(.bottom, workout.restTimer.isRunning ? 100 : 30)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var progressHeader: some View {
        HStack(spacing: 14) {
            ProgressRing(progress: workout.progress, lineWidth: 7, phase: workout.phase,
                         label: "\(Int(workout.progress * 100))")
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(workout.completedCount) of \(workout.totalCount) sets")
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(AppSettings.shared.weight(workout.volumeKg)) moved")
                    .font(Theme.rounded(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .gtCard(padding: 14, phase: workout.phase)
    }

    /// Deliberately at the very bottom, past everything else. Leaving the
    /// screen shouldn't cost you the session — only this should.
    private var discardFooter: some View {
        VStack(spacing: 6) {
            Button(role: .destructive) {
                showingDiscardConfirm = true
            } label: {
                Label("Discard this workout", systemImage: "trash")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.negative)
            }
            .buttonStyle(.plain)

            Text("Minimising keeps everything and lets the session run in the background. Discarding deletes it.")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
        }
        .padding(.top, 22)
    }

    // MARK: - Actions

    private func minimise() {
        Haptics.tick()
        onMinimise()
    }

    private func finish() {
        let session = workout.session
        workout.finish()
        onClose(session)
    }
}

// MARK: - Exercise card

private struct ExerciseLogCard: View {
    @Bindable var workout: ActiveWorkout
    let group: SessionExerciseGroup

    @State private var showingDetail = false

    private var lastTime: [SetLog] { workout.lastPerformance(for: group.catalogID) }
    private var planItem: PlanItem? { workout.planItem(for: group.catalogID) }

    /// The first set the user hasn't logged — expanded for immediate input.
    private var activeSetID: UUID? {
        group.sets.first { !$0.isCompleted }?.id
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let suggestion, !group.isComplete, !lastTime.isEmpty {
                HStack(alignment: .top, spacing: 7) {
                    Image(systemName: "arrow.up.forward.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent.wash)
                    Text(suggestion)
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.04)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 1)
                }
            }

            VStack(spacing: 8) {
                ForEach(group.sets) { set in
                    SetRow(
                        set: set,
                        label: group.label(for: set),
                        isExpanded: set.id == activeSetID,
                        previous: previousSet(for: set),
                        isPR: workout.isPR(set),
                        onLog: { workout.complete(set, restSeconds: planItem?.restSeconds) },
                        onUndo: { workout.uncomplete(set) },
                        isLastLogged: workout.lastLoggedSetID == set.id,
                        // The rest bar is already holding the question up at
                        // thumb height; two copies of it would be one too many.
                        asksInline: !workout.restTimer.isRunning,
                        onRate: { workout.rate(set, feel: $0) },
                        onClearRating: { workout.clearRating(set) }
                    )

                    if let nudge = workout.pendingNudge, nudge.setID == set.id {
                        LoadNudgeRow(nudge: nudge,
                                     onTake: { workout.apply(nudge) },
                                     onDismiss: { workout.dismissNudge() })
                    } else if let taken = workout.takenNudge, taken.nudge.setID == set.id {
                        NudgeTakenRow(taken: taken, onUndo: { workout.undoTakenNudge() })
                    }
                }
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: workout.pendingNudge)
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: workout.takenNudge)

            HStack(spacing: 8) {
                Button { workout.addSet(to: group) } label: {
                    Label("Add set", systemImage: "plus")
                        .font(Theme.rounded(12, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.accent)

                if group.sets.count > 1 {
                    Button { workout.removeLastSet(from: group) } label: {
                        Label("Remove", systemImage: "minus")
                            .font(Theme.rounded(12, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
            }
            .padding(.top, 2)
        }
        .gtCard(padding: 12, dimmed: group.isComplete)
        .sheet(isPresented: $showingDetail) {
            if let catalog = group.catalog {
                NavigationStack { ExerciseDetailView(exercise: catalog) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            GlyphTile(symbol: group.isComplete ? "checkmark" : (group.catalog?.symbol ?? "dumbbell.fill"),
                      tint: group.isComplete ? Theme.positive : Theme.textSecondary,
                      size: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text(lastTimeSummary)
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            Text("\(group.completedCount)/\(group.sets.count)")
                .font(Theme.number(13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            Button { showingDetail = true } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
    }

    /// Last session's matching set, paired by position within the exercise.
    private func previousSet(for set: SetLog) -> SetLog? {
        let position = group.position(of: set)
        guard position < lastTime.count else { return nil }
        return lastTime[position]
    }

    private var lastTimeSummary: String {
        guard let best = lastTime.max(by: { $0.weightKg < $1.weightKg }) else {
            return "First time logging this"
        }
        if best.tracking == .duration { return "Last: \(best.seconds)s" }
        if best.weightKg == 0 { return "Last: \(best.reps) reps × \(lastTime.count)" }
        return "Last: \(best.weightLabel) × \(best.reps)"
    }

    private var suggestion: String? {
        guard let planItem else { return nil }
        return TrainingStats.suggestion(for: planItem, lastSets: lastTime).message
    }
}

// MARK: - Set row

private struct SetRow: View {
    @Bindable var set: SetLog
    /// "1", "2", "3" — its position in the exercise.
    let label: String
    let isExpanded: Bool
    let previous: SetLog?
    let isPR: Bool
    let onLog: () -> Void
    let onUndo: () -> Void
    /// Whether this is the set that was logged most recently — the only one
    /// that volunteers the effort question.
    let isLastLogged: Bool
    /// False while the rest bar is up and asking the question itself.
    let asksInline: Bool
    let onRate: (SetFeel) -> Void
    let onClearRating: () -> Void

    @State private var showingKeypad = false
    @State private var showingScale = false
    /// Set by tapping an answer already given, to change it.
    @State private var editingEffort = false

    /// How the machine in front of you is marked. Read through the book rather
    /// than the app-wide unit, so a stack stamped in pounds stays in pounds.
    private var scale: LoadScale { self.set.loadScale }

    var body: some View {
        if set.isCompleted {
            completedRow
        } else if isExpanded {
            expandedRow
        } else {
            pendingRow
        }
    }

    // MARK: Completed

    private var completedRow: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                indexBadge(filled: true)
                Text(valueLabel)
                    .font(Theme.number(16))
                    .foregroundStyle(isPR ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.ink))
                if isPR {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill").font(.system(size: 9))
                        Text("PR").font(Theme.rounded(10, weight: .black))
                    }
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Color.black.opacity(0.15), in: Capsule())
                }
                if let gain { gainBadge(gain) }
                Spacer()
                if let feel = set.feel, !showsEffortStrip {
                    effortBadge(feel)
                } else if showsRateAffordance {
                    rateAffordance
                }
                Button(action: onUndo) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(isPR ? .black.opacity(0.6) : Theme.textTertiary)
                        .frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
            }

            if showsEffortStrip {
                EffortPicker(current: set.feel,
                             onDark: isPR,
                             onPick: { feel in
                                 onRate(feel)
                                 editingEffort = false
                             },
                             onClear: {
                                 onClearRating()
                                 editingEffort = false
                             })
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showsEffortStrip)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            // A PR is filled with the gradient and glows; an ordinary logged set
            // is the same colour held back to a tint, so a record still stands
            // out in a column of eight green rows.
            let phase = SessionPhase.working
            shape.fill(isPR
                       ? AnyShapeStyle(phase.gradient)
                       : AnyShapeStyle(LinearGradient(colors: [phase.trail.opacity(0.16),
                                                               phase.trail.opacity(0.04)],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing)))
                .overlay { shape.strokeBorder(phase.trail.opacity(isPR ? 0 : 0.22), lineWidth: 1) }
                .shadow(color: isPR ? phase.glow : .clear, radius: 10, y: 3)
        }
    }

    // MARK: Effort

    /// Open on the set just logged — but only when the rest bar isn't already
    /// holding the question up at thumb height — and on any set you go back to.
    ///
    /// The old strip existed *only* on the set logged last, so logging the next
    /// set took the question away with it and the one that stayed on screen was
    /// the final set of the session. An unanswered set now keeps a way back in.
    private var showsEffortStrip: Bool {
        guard AppSettings.shared.trackRPE, set.isCompleted else { return false }
        return editingEffort || (isLastLogged && set.rpe == nil && asksInline)
    }

    /// The quiet way back to a question that was never answered.
    private var showsRateAffordance: Bool {
        AppSettings.shared.trackRPE && set.isCompleted && set.rpe == nil && !showsEffortStrip
    }

    private var rateAffordance: some View {
        Button { editingEffort = true } label: {
            Text("Rate")
                .font(Theme.rounded(10, weight: .bold))
                .foregroundStyle(isPR ? .black.opacity(0.55) : Theme.textTertiary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay {
                    Capsule().strokeBorder(isPR ? AnyShapeStyle(Color.black.opacity(0.22))
                                                : AnyShapeStyle(Theme.edge), lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rate how set \(label) felt")
    }

    /// The answer, once given — the word, not a number to decode. Tapping it
    /// asks again.
    private func effortBadge(_ feel: SetFeel) -> some View {
        Button { editingEffort = true } label: {
            Text(feel.label)
                .font(Theme.rounded(10, weight: .bold))
                .foregroundStyle(isPR ? .black.opacity(0.7) : feel.tint)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background {
                    Capsule().fill(isPR
                                   ? AnyShapeStyle(Color.black.opacity(0.15))
                                   : AnyShapeStyle(feel.tint.opacity(0.16)))
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Felt \(feel.label). \(feel.spokenDetail)")
        .accessibilityHint("Change it")
    }

    // MARK: Beating last time

    /// What this set did that the same set didn't last session. Weight first —
    /// it's the number being chased — and reps only when the load is unchanged,
    /// because "+5 kg, −2 reps" is a comparison rather than a result.
    private var gain: (text: String, up: Bool)? {
        guard let previous, set.isCompleted else { return nil }
        if set.tracking == .duration {
            let delta = set.seconds - previous.seconds
            guard delta != 0 else { return nil }
            return ("\(delta > 0 ? "+" : "−")\(abs(delta))s", delta > 0)
        }
        if set.weightKg != previous.weightKg {
            let delta = set.weightKg - previous.weightKg
            return ("\(delta > 0 ? "+" : "−")\(scale.format(abs(delta), showUnit: false))", delta > 0)
        }
        let delta = set.reps - previous.reps
        guard delta != 0 else { return nil }
        return ("\(delta > 0 ? "+" : "−")\(abs(delta)) rep\(abs(delta) == 1 ? "" : "s")", delta > 0)
    }

    private func gainBadge(_ gain: (text: String, up: Bool)) -> some View {
        let tint: Color = gain.up ? Theme.positive : Theme.textTertiary
        return HStack(spacing: 2) {
            Image(systemName: gain.up ? "arrow.up" : "arrow.down")
                .font(.system(size: 7, weight: .black))
            Text(gain.text)
                .font(Theme.number(10, weight: .bold))
        }
        .foregroundStyle(isPR ? AnyShapeStyle(Color.black.opacity(0.65)) : AnyShapeStyle(tint))
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background {
            Capsule().fill(isPR
                           ? AnyShapeStyle(Color.black.opacity(0.12))
                           : AnyShapeStyle(tint.opacity(0.14)))
        }
        .accessibilityLabel("\(gain.up ? "Up" : "Down") \(gain.text) on last time")
    }

    // MARK: Pending (collapsed)

    private var pendingRow: some View {
        HStack(spacing: 10) {
            indexBadge(filled: false)
            Text(targetLabel)
                .font(Theme.rounded(14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            if let previous {
                Text(previousLabel(previous))
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 12)
        .background(Theme.well, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.04), lineWidth: 1)
        }
    }

    // MARK: Expanded (the set being worked)

    private var expandedRow: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                indexBadge(filled: false)
                Text("SET \(label)")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent.wash)
                    .layoutPriority(1)
                Spacer(minLength: 0)
                if let previous {
                    Text(previousLabel(previous))
                        .font(Theme.rounded(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 14) {
                if set.tracking == .duration {
                    StepperField(title: "Time", value: secondsBinding, step: 5,
                                 format: { String(format: "%.0f", $0) }, unit: "seconds")
                } else {
                    if set.tracking == .weightReps || set.weightKg > 0 {
                        StepperField(title: "Weight", value: weightBinding,
                                     scale: scale,
                                     format: { $0 == 0 && set.tracking == .bodyweightReps ? "BW" : scale.text($0) },
                                     unitAction: { showingScale = true },
                                     unitIsCustom: LoadScaleBook.shared.isCustomised(set.catalogID))
                    }
                    StepperField(title: "Reps", value: repsBinding, step: 1,
                                 format: { String(format: "%.0f", $0) }, unit: "reps")
                }
            }
            .frame(maxWidth: .infinity)

            Button(action: onLog) {
                Label("Log set", systemImage: "checkmark")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(14)
        // The set you're standing in is the only lit object on the screen: a
        // tinted ground, a gradient edge and a glow under it, so it's findable
        // from arm's length with a bar in your hands.
        .background {
            ZStack {
                Theme.panel
                LinearGradient(colors: [Theme.accent.opacity(0.13), Theme.accent.opacity(0.02)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.edge(.working), lineWidth: 1.5)
        )
        .shadow(color: Theme.accent.opacity(0.14), radius: 12, y: 4)
        .sheet(isPresented: $showingScale) {
            if let catalog = set.catalog {
                LoadScaleSheet(exercise: catalog, referenceKg: set.weightKg) { updated in
                    // Everything still to come on this exercise moves onto the
                    // ladder it was just told about, not only the set in front
                    // of you — the rest would otherwise sit a pin off and
                    // quietly disagree with what the sheet just promised.
                    let pending = (set.session?.sets ?? []).filter {
                        $0.catalogID == set.catalogID && !$0.isCompleted && $0.weightKg > 0
                    }
                    for pendingSet in pending {
                        pendingSet.weightKg = updated.snap(kg: pendingSet.weightKg)
                    }
                }
            }
        }
    }

    // MARK: Pieces

    private func indexBadge(filled: Bool) -> some View {
        Text(label)
            .font(Theme.number(12, weight: .bold))
            .foregroundStyle(filled ? (isPR ? Color.black : Theme.accent) : Theme.textTertiary)
            .frame(width: 26, height: 26)
            .background {
                Circle().fill(filled
                              ? (isPR ? AnyShapeStyle(Color.black.opacity(0.15))
                                      : AnyShapeStyle(LinearGradient(colors: [Theme.accent.opacity(0.26),
                                                                              Theme.accent.opacity(0.1)],
                                                                     startPoint: .top, endPoint: .bottom)))
                              : AnyShapeStyle(Color.white.opacity(0.06)))
            }
    }

    private var valueLabel: String {
        switch set.tracking {
        case .duration: "\(set.seconds)s"
        case _ where set.weightKg == 0: "\(set.reps) reps"
        default: "\(scale.format(set.weightKg)) × \(set.reps)"
        }
    }

    private var targetLabel: String {
        if set.tracking == .duration { return "\(set.seconds)s target" }
        let range: String
        if set.targetRepsHigh <= 0 {
            range = "\(set.reps)"
        } else if set.targetRepsLow == set.targetRepsHigh {
            range = "\(set.targetRepsLow)"
        } else {
            range = "\(set.targetRepsLow)–\(set.targetRepsHigh)"
        }
        if set.weightKg == 0 { return "\(range) reps" }
        return "\(scale.format(set.weightKg)) × \(range)"
    }

    private func previousLabel(_ previous: SetLog) -> String {
        if previous.tracking == .duration { return "was \(previous.seconds)s" }
        if previous.weightKg == 0 { return "was \(previous.reps)" }
        return "was \(scale.format(previous.weightKg, showUnit: false)) × \(previous.reps)"
    }

    // MARK: Bindings (display unit in, kilograms out)

    private var weightBinding: Binding<Double> {
        Binding(
            get: { scale.display(set.weightKg) },
            set: { set.weightKg = scale.kilograms(max(0, $0)) }
        )
    }

    private var repsBinding: Binding<Double> {
        Binding(get: { Double(set.reps) }, set: { set.reps = max(0, Int($0)) })
    }

    private var secondsBinding: Binding<Double> {
        Binding(get: { Double(set.seconds) }, set: { set.seconds = max(0, Int($0)) })
    }
}

// MARK: - Rest timer bar

/// The bar that floats over the logger while you wait — and, while a set is
/// still unrated, the place the effort question is asked.
///
/// Deliberately here rather than up on the row you just logged: during a rest
/// you are standing still, holding the phone, with nothing to do. Your thumb is
/// already at the bottom of the screen. Asking anywhere else is asking at the
/// wrong moment.
struct RestTimerBar: View {
    @Bindable var timer: RestTimer
    /// The set the question is about, answered or not.
    let subject: SetLog?
    let onRate: (SetFeel) -> Void
    let onClear: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            timerRow
            if let subject {
                Divider().overlay(Color.black.opacity(0.14))
                if let feel = subject.feel {
                    answeredRow(feel)
                } else {
                    effortRow
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // Amber, not lime: the bar that floats over the logger while you wait
        // is the same colour the rest is on the Lock Screen and on the wrist.
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            ZStack {
                SessionPhase.resting.gradient
                LinearGradient(colors: [Color.white.opacity(0.22), .clear],
                               startPoint: .top, endPoint: .center)
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white.opacity(0.18), lineWidth: 1) }
        }
        .shadow(color: SessionPhase.resting.glow, radius: 18, y: 7)
        .animation(.spring(response: 0.34, dampingFraction: 0.86), value: subject?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: subject?.rpe)
    }

    private var timerRow: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.black.opacity(0.18), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.001, 1 - timer.progress))
                    .stroke(Color.black.opacity(0.85), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 0) {
                Text("RESTING")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(.black.opacity(0.55))
                Text(timer.remaining.clockString)
                    .font(Theme.number(22))
                    .foregroundStyle(.black)
            }

            Spacer()

            Button("+30s") { timer.add(seconds: 30) }
                .font(Theme.rounded(13, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color.black.opacity(0.13), in: Capsule())

            Button {
                timer.stop()
                Haptics.tick()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(Color.black.opacity(0.13), in: Circle())
            }
            .buttonStyle(.plain)
        }
    }

    /// Answering never stops the clock and never blocks the next set — the
    /// question is an offer, and ignoring it leaves the app exactly as it was.
    private var effortRow: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("HOW DID THAT SET FEEL?")
                .font(Theme.microCaps)
                .tracking(0.9)
                .foregroundStyle(.black.opacity(0.62))
            EffortPicker(current: nil, onDark: true, onPick: onRate)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    /// What you answered, and an unmissable way to take it back. A mis-tap on
    /// one of four buttons is a normal thing to do with a phone in one hand,
    /// and undoing it has to be as plain as making it — not a second tap on the
    /// same button that happens to toggle.
    private func answeredRow(_ feel: SetFeel) -> some View {
        HStack(spacing: 8) {
            Text("FELT")
                .font(Theme.microCaps)
                .tracking(0.9)
                .foregroundStyle(.black.opacity(0.62))

            Text(feel.label)
                .font(Theme.rounded(13, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(feel.tint.gradient))

            Text(feel.detail)
                .font(Theme.rounded(11, weight: .semibold))
                .foregroundStyle(.black.opacity(0.6))
                .lineLimit(1)

            Spacer(minLength: 2)

            Button(action: onClear) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .black))
                    Text("Undo")
                        .font(Theme.rounded(12, weight: .bold))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 11).padding(.vertical, 6)
                .background(Color.black.opacity(0.13), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo — clear how that set felt")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .transition(.opacity)
    }
}

// MARK: - The effort question

/// The four answers, in the two places they're asked: on the rest bar while
/// you're standing there, and inline on a set you've come back to.
///
/// Words, not the 6–10 numbers this replaced. The number meant nothing without
/// the scale already in your head; "Hard · 1 left" carries its own definition,
/// and what gets stored underneath is still the number the progression reads.
struct EffortPicker: View {
    let current: SetFeel?
    /// True on the amber rest bar and on a PR row, where the ground is light
    /// and everything on it has to be black.
    let onDark: Bool
    let onPick: (SetFeel) -> Void
    /// Shown alongside the answers once one of them is chosen, so a mis-tap has
    /// a way out that doesn't depend on knowing the buttons toggle.
    var onClear: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SetFeel.allCases) { feel in
                let isChosen = current == feel
                Button { onPick(feel) } label: {
                    VStack(spacing: 1) {
                        Text(feel.label)
                            .font(Theme.rounded(13, weight: .bold))
                        Text(feel.detail)
                            .font(Theme.rounded(9, weight: .semibold))
                            .opacity(0.7)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .foregroundStyle(foreground(chosen: isChosen))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 7)
                    .background {
                        Capsule().fill(background(feel, chosen: isChosen))
                    }
                    .overlay {
                        Capsule().strokeBorder(border(chosen: isChosen), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feel.label)
                .accessibilityHint(feel.spokenDetail)
                .accessibilityAddTraits(isChosen ? [.isSelected] : [])
            }

            if current != nil, let onClear {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(onDark ? AnyShapeStyle(Color.black.opacity(0.7))
                                                : AnyShapeStyle(Theme.textTertiary))
                        .frame(width: 30, height: 32)
                        .background {
                            Capsule().fill(onDark ? AnyShapeStyle(Color.black.opacity(0.13))
                                                  : AnyShapeStyle(Color.white.opacity(0.07)))
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear how this set felt")
            }
        }
    }

    private func foreground(chosen: Bool) -> AnyShapeStyle {
        if chosen { return AnyShapeStyle(onDark ? Color.white : Color.black) }
        return AnyShapeStyle(onDark ? Color.black.opacity(0.75) : Theme.textSecondary)
    }

    private func background(_ feel: SetFeel, chosen: Bool) -> AnyShapeStyle {
        if chosen { return AnyShapeStyle(feel.tint.gradient) }
        return AnyShapeStyle(onDark ? Color.black.opacity(0.13) : Color.white.opacity(0.07))
    }

    private func border(chosen: Bool) -> AnyShapeStyle {
        chosen ? AnyShapeStyle(Color.clear)
               : AnyShapeStyle(onDark ? Color.black.opacity(0.1) : Color.white.opacity(0.06))
    }
}

// MARK: - What the answer just did

/// The offer a rating produces: the sets still to come, moved a rung. Shown
/// under the set that produced it, taken with one tap and ignored with none.
///
/// This is the part the old question never had. An effort score that only
/// surfaces in next week's suggestion reads, mid-workout, as a quiz with no
/// consequence — which is exactly why it stopped being answered.
private struct LoadNudgeRow: View {
    let nudge: ActiveWorkout.LoadNudge
    let onTake: () -> Void
    let onDismiss: () -> Void

    private var scale: LoadScale { LoadScaleBook.shared.scale(for: nudge.catalogID) }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: nudge.isBackOff ? "arrow.down.right.circle.fill" : "arrow.up.forward.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: 1) {
                Text(headline)
                    .font(Theme.rounded(12, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text(detail)
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 4)

            Button(action: onTake) {
                Text("Take it")
                    .font(Theme.rounded(12, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 11).padding(.vertical, 7)
                    .background(tint.gradient, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Keep the weight as it is")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(LinearGradient(colors: [tint.opacity(0.18), tint.opacity(0.05)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { shape.strokeBorder(tint.opacity(0.28), lineWidth: 1) }
        }
        .transition(.scale(scale: 0.96).combined(with: .opacity))
    }

    private var tint: Color { nudge.isBackOff ? Theme.warning : Theme.positive }

    private var headline: String {
        nudge.isBackOff
            ? "That was everything you had"
            : "Felt easy — there's a rung above this"
    }

    private var detail: String {
        let sets = "\(nudge.setCount) set\(nudge.setCount == 1 ? "" : "s") to go"
        return "\(scale.format(nudge.fromKg)) → \(scale.format(nudge.toKg)) · \(sets)"
    }
}

/// The offer after it's been taken — and the way back out of it.
///
/// Taking it rewrote the weight on several sets at once, which is exactly the
/// kind of thing you don't want to have done by accident with a bar in your
/// hands. Undo puts every one of those weights back to the number it held
/// before the tap and stands the offer back up, so the screen reads as though
/// the button was never pressed.
private struct NudgeTakenRow: View {
    let taken: ActiveWorkout.TakenNudge
    let onUndo: () -> Void

    private var scale: LoadScale { LoadScaleBook.shared.scale(for: taken.nudge.catalogID) }

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(Theme.positive)

            VStack(alignment: .leading, spacing: 1) {
                Text("Moved to \(scale.format(taken.nudge.toKg))")
                    .font(Theme.rounded(12, weight: .bold))
                    .foregroundStyle(Theme.ink)
                Text("\(taken.previousKg.count) set\(taken.previousKg.count == 1 ? "" : "s") changed from \(scale.format(taken.nudge.fromKg))")
                    .font(Theme.rounded(11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: 4)

            Button(action: onUndo) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 10, weight: .black))
                    Text("Undo")
                        .font(Theme.rounded(12, weight: .bold))
                }
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(Theme.panel, in: Capsule())
                .overlay { Capsule().strokeBorder(Theme.edge, lineWidth: 1) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Undo — put the weight back to \(scale.format(taken.nudge.fromKg))")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background {
            let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
            shape.fill(Theme.well)
                .overlay { shape.strokeBorder(Theme.edge, lineWidth: 1) }
        }
        .transition(.opacity)
    }
}

// MARK: - Live heart rate

/// The watch's current reading, shown in the logger while it's recording. It
/// beats rather than animating a number, so it reads at a glance from arm's
/// length without pulling focus from the set.
struct LiveHeartRatePill: View {
    let bpm: Double
    @State private var isBeating = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "heart.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.negative)
                .scaleEffect(isBeating ? 1.18 : 1)
                .animation(.easeInOut(duration: 0.5).repeatForever(autoreverses: true), value: isBeating)
            Text("\(Int(bpm.rounded()))")
                .font(Theme.number(11, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.negative.opacity(0.13)))
        .overlay { Capsule().strokeBorder(Theme.negative.opacity(0.2), lineWidth: 1) }
        .onAppear { isBeating = true }
        .accessibilityLabel("Heart rate \(Int(bpm.rounded())) beats per minute")
    }
}
