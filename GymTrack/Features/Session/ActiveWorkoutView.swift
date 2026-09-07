import SwiftUI
import SwiftData

/// The logging screen. Optimised for use mid-set: the next set is always
/// expanded with large steppers, everything else collapses to a summary row.
struct ActiveWorkoutView: View {
    @Bindable var workout: ActiveWorkout
    let onClose: (WorkoutSession?) -> Void

    @Environment(\.modelContext) private var context
    @State private var elapsed: TimeInterval = 0
    @State private var showingAddExercise = false
    @State private var showingFinishConfirm = false
    @State private var showingDiscardConfirm = false

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                content
                if workout.restTimer.isRunning {
                    RestTimerBar(timer: workout.restTimer)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .gtScreenBackground()
            .navigationTitle(workout.session.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showingDiscardConfirm = true } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 0) {
                        Text(workout.session.title)
                            .font(Theme.rounded(15, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(elapsed.clockString)
                            .font(Theme.number(12, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Finish") { showingFinishConfirm = true }
                        .font(Theme.rounded(15, weight: .bold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .onReceive(ticker) { _ in elapsed = workout.session.duration }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: workout.restTimer.isRunning)
            .sheet(isPresented: $showingAddExercise) {
                ExercisePickerView { exercise in
                    workout.addExercise(exercise)
                    showingAddExercise = false
                }
            }
            .confirmationDialog("Finish this workout?",
                                isPresented: $showingFinishConfirm,
                                titleVisibility: .visible) {
                Button("Finish workout") { finish() }
                Button("Keep going", role: .cancel) {}
            } message: {
                Text(finishMessage)
            }
            .confirmationDialog("Discard this workout?",
                                isPresented: $showingDiscardConfirm,
                                titleVisibility: .visible) {
                Button("Discard", role: .destructive) {
                    workout.discard()
                    onClose(nil)
                }
                Button("Minimise", role: .cancel) { onClose(nil) }
            } message: {
                Text("Discarding deletes every set you've logged in this session. Minimising keeps it running in the background.")
            }
        }
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
            }
            .padding(.horizontal, 12)
            .padding(.bottom, workout.restTimer.isRunning ? 100 : 30)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
    }

    private var progressHeader: some View {
        HStack(spacing: 14) {
            ProgressRing(progress: workout.progress, lineWidth: 7,
                         label: "\(Int(workout.progress * 100))")
                .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(workout.completedCount) of \(workout.totalCount) sets")
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(AppSettings.shared.weight(workout.volumeKg)) moved")
                    .font(Theme.rounded(13, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .gtCard(padding: 14)
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
                        .foregroundStyle(Theme.accent)
                    Text(suggestion)
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.accentDim.opacity(0.5), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }

            VStack(spacing: 8) {
                ForEach(Array(group.sets.enumerated()), id: \.element.id) { index, set in
                    SetRow(
                        set: set,
                        number: index + 1,
                        isExpanded: set.id == activeSetID,
                        previous: index < lastTime.count ? lastTime[index] : nil,
                        isPR: workout.isPR(set),
                        onLog: { workout.complete(set, restSeconds: planItem?.restSeconds) },
                        onUndo: { workout.uncomplete(set) }
                    )
                }
            }

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
        .gtCard(padding: 12, background: group.isComplete ? Theme.surface.opacity(0.55) : Theme.surface)
        .sheet(isPresented: $showingDetail) {
            if let catalog = group.catalog {
                NavigationStack { ExerciseDetailView(exercise: catalog) }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: group.isComplete ? "checkmark.circle.fill" : (group.catalog?.symbol ?? "dumbbell.fill"))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(group.isComplete ? Theme.accent : Theme.textSecondary)
                .frame(width: 32, height: 32)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(group.name)
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
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

    private var lastTimeSummary: String {
        guard let best = lastTime.max(by: { $0.weightKg < $1.weightKg }) else {
            return "First time logging this"
        }
        if best.tracking == .duration { return "Last: \(best.seconds)s" }
        if best.weightKg == 0 { return "Last: \(best.reps) reps × \(lastTime.count)" }
        return "Last: \(AppSettings.shared.weight(best.weightKg)) × \(best.reps)"
    }

    private var suggestion: String? {
        guard let planItem else { return nil }
        return TrainingStats.suggestion(for: planItem, lastSets: lastTime).message
    }
}

// MARK: - Set row

private struct SetRow: View {
    @Bindable var set: SetLog
    let number: Int
    let isExpanded: Bool
    let previous: SetLog?
    let isPR: Bool
    let onLog: () -> Void
    let onUndo: () -> Void

    @State private var showingKeypad = false

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
        HStack(spacing: 10) {
            indexBadge(filled: true)
            Text(valueLabel)
                .font(Theme.number(16))
                .foregroundStyle(isPR ? .black : Theme.textPrimary)
            if isPR {
                HStack(spacing: 3) {
                    Image(systemName: "trophy.fill").font(.system(size: 9))
                    Text("PR").font(Theme.rounded(10, weight: .black))
                }
                .foregroundStyle(.black)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Color.black.opacity(0.15), in: Capsule())
            }
            Spacer()
            Button(action: onUndo) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(isPR ? .black.opacity(0.6) : Theme.textTertiary)
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isPR ? Theme.accent : Theme.accent.opacity(0.13),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
        .background(Theme.surfaceRaised.opacity(0.5), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: Expanded (the set being worked)

    private var expandedRow: some View {
        VStack(spacing: 12) {
            HStack {
                indexBadge(filled: false)
                Text("SET \(number)")
                    .font(Theme.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let previous {
                    Text(previousLabel(previous))
                        .font(Theme.rounded(11, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            HStack(spacing: 14) {
                if set.tracking == .duration {
                    StepperField(title: "Time", value: secondsBinding, step: 5,
                                 format: { String(format: "%.0f", $0) }, unit: "seconds")
                } else {
                    if set.tracking == .weightReps || set.weightKg > 0 {
                        StepperField(title: "Weight", value: weightBinding,
                                     step: AppSettings.shared.weightUnit.step,
                                     format: { $0 == 0 && set.tracking == .bodyweightReps ? "BW" : formatWeight($0) },
                                     unit: AppSettings.shared.weightUnit.short)
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
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.accent.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: Pieces

    private func indexBadge(filled: Bool) -> some View {
        Text("\(number)")
            .font(Theme.number(12, weight: .bold))
            .foregroundStyle(filled ? (isPR ? Color.black : Theme.accent) : Theme.textTertiary)
            .frame(width: 26, height: 26)
            .background(
                Circle().fill(filled
                              ? (isPR ? Color.black.opacity(0.15) : Theme.accent.opacity(0.18))
                              : Color.white.opacity(0.06))
            )
    }

    private var valueLabel: String {
        switch set.tracking {
        case .duration: "\(set.seconds)s"
        case _ where set.weightKg == 0: "\(set.reps) reps"
        default: "\(AppSettings.shared.weight(set.weightKg)) × \(set.reps)"
        }
    }

    private var targetLabel: String {
        if set.tracking == .duration { return "\(set.seconds)s target" }
        let range = set.targetRepsLow == set.targetRepsHigh
            ? "\(set.targetRepsLow)"
            : "\(set.targetRepsLow)–\(set.targetRepsHigh)"
        if set.weightKg == 0 { return "\(range) reps" }
        return "\(AppSettings.shared.weight(set.weightKg)) × \(range)"
    }

    private func previousLabel(_ previous: SetLog) -> String {
        if previous.tracking == .duration { return "was \(previous.seconds)s" }
        if previous.weightKg == 0 { return "was \(previous.reps)" }
        return "was \(AppSettings.shared.weight(previous.weightKg, showUnit: false)) × \(previous.reps)"
    }

    private func formatWeight(_ display: Double) -> String {
        display.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", display)
            : String(format: "%.1f", display)
    }

    // MARK: Bindings (display unit in, kilograms out)

    private var weightBinding: Binding<Double> {
        Binding(
            get: { AppSettings.shared.weightUnit.fromKg(set.weightKg) },
            set: { set.weightKg = AppSettings.shared.weightUnit.toKg(max(0, $0)) }
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

struct RestTimerBar: View {
    @Bindable var timer: RestTimer

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.black.opacity(0.2), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(0.001, 1 - timer.progress))
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 4, lineCap: .round))
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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.3), radius: 16, y: 6)
    }
}
