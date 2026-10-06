import SwiftUI

/// Logging from the wrist.
///
/// One set at a time — the one you're about to do — with the weight and reps
/// on the Digital Crown. Tap a number to hand the crown to it; the accent ring
/// says which one you're turning. That's the whole interaction, because it has
/// to work with one hand, chalked up, between sets.
///
/// The screen has two faces and swaps between them, because between sets and
/// during one you are doing different things. Resting, you are standing at a
/// rack you have not loaded yet: the clock and the weight to put on the bar are
/// the whole screen, big enough to read at arm's length without stopping to
/// look. Working, the dials are the screen and the clock is gone.
///
/// The crown is attached to exactly one view and stays there. watchOS will not
/// reliably move focus between two crown targets on a tap — it is handed out
/// by the focus system, not by us — so the *selection* is plain state, and the
/// crown reads and writes whichever number that selection points at.
struct WatchLoggerView: View {

    let session: WatchSessionSnapshot
    var connector: WatchConnector
    var rest: WatchRestTimer
    var focus: WatchRestFocus

    @State private var weightDisplay: Double = 0
    @State private var repsValue: Double = 0
    @State private var secondsValue: Double = 0
    /// The number the crown is currently turning, and its live value.
    @State private var editing: Field?
    @State private var crownValue: Double = 0
    /// The numbers the lifter has dialled themselves on the set that's up.
    /// Cleared when the logger moves to another set — see `adopt`.
    @State private var touched: Set<Field> = []
    /// Held independently of the next set, which advances as soon as logging succeeds.
    @State private var effortSetID: UUID?
    @State private var effortCompletedAt: Date?
    /// When the last set was logged from this screen, for `WatchLoggerRules`'
    /// double-tap window.
    @State private var lastLoggedAt: Date?
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOverEnabled
    @State private var showingExercises = false
    @FocusState private var isCrownFocused: Bool

    private enum Field: Hashable { case weight, reps, seconds }

    /// Anchors the top of the list so a rest starting can bring it back into
    /// view — see the scroll in `body`.
    private static let topID = "logger.top"

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
        logger
            .navigationTitle(session.title)
            .watchScreenTint(phase)
            .sheet(isPresented: $showingExercises) {
                WatchExerciseListView(session: session, connector: connector)
            }
            .onAppear { load(set) }
            .onChange(of: set) { was, now in
                if was?.id == now?.id { adopt(now) } else { load(now) }
            }
            .onChange(of: session.sessionID) { _, _ in dismissEffort() }
            .onChange(of: session.effortEnabled) { _, enabled in
                if enabled != true { dismissEffort() }
            }
            // Initial too: a logger that went with its session while the
            // question was up never said it had gone, and the next session's
            // logger is the one to say so.
            .onChange(of: effortSet != nil, initial: true) { _, waiting in
                focus.questionWaiting = waiting
            }
            .task(id: effortSetID) {
                guard effortSetID != nil, !voiceOverEnabled else { return }
                // Ignoring the question never requires a dismissal. It sits below
                // Log set and takes nothing over, and it folds itself back into
                // the quiet "Rate last set" button after a while, which moves
                // nothing above it. VoiceOver readers keep control of the pace
                // instead of racing a timeout.
                do { try await Task.sleep(for: .seconds(10)) } catch { return }
                dismissEffort()
            }
    }

    private var logger: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    // One or the other, never both. Two headers' worth of
                    // exercise name and set count above a countdown left the
                    // countdown at the bottom of a 41mm screen, which is the
                    // one thing on it nobody should have to scroll to.
                    Group {
                        if rest.isRunning {
                            restCentrepiece
                        } else {
                            header
                        }
                    }
                    .id(Self.topID)

                    if let set, let exercise {
                        values(for: set, exercise: exercise)
                        targetLine(set, exercise: exercise)
                        stepperRow
                        startStrip(for: set)
                        logButton(set: set, exercise: exercise)
                    } else {
                        allDone
                    }
                    effortPrompt
                    undoButton
                }
                .padding(.horizontal, 2)
                .reportsScrolling(to: focus)
            }
            // A rest begins with the lifter's thumb still on *Log set*, which
            // is at the bottom of the list — so the countdown that has just
            // appeared at the top is off screen, and the one screen in this app
            // designed to be read without stopping had to be scrolled to first.
            // Only on the way in: a lifter who has scrolled somewhere during a
            // rest put themselves there. Not while the effort card is waiting
            // for an answer either: it sits below Log set precisely so that
            // nothing moves under the thumb, and scrolling to the countdown
            // took the question off the screen the moment it was asked.
            .onChange(of: rest.isRunning) { _, resting in
                guard WatchLoggerRules.scrollsToTop(whenRestBecomes: resting,
                                                    effortCardWaiting: effortSet != nil) else { return }
                withAnimation(.easeOut(duration: 0.25)) {
                    proxy.scrollTo(Self.topID, anchor: .top)
                }
            }
            // The rest of the rest: once the watch has gone untouched for a
            // while, the countdown comes back. See `WatchRestFocus`.
            .onChange(of: focus.returns) { _, _ in
                bringCountdownBack(proxy)
            }
        }
    }

    /// Scrolls to the countdown for `WatchRestFocus`. The crown is handed back
    /// to the scroll first: left on a number that has just scrolled out of
    /// sight, its next turn would change a weight nobody can see.
    private func bringCountdownBack(_ proxy: ScrollViewProxy) {
        editing = nil
        isCrownFocused = false
        withAnimation(.easeOut(duration: 0.25)) {
            proxy.scrollTo(Self.topID, anchor: .top)
        }
    }

    private var effortSet: WatchSetSnapshot? {
        session.allSets.first {
            guard $0.id == effortSetID, $0.isCompleted,
                  let actual = $0.completedAt, let expected = effortCompletedAt else { return false }
            return abs(actual.timeIntervalSince(expected)) < 0.001
        }
    }

    private var effortExercise: WatchExerciseSnapshot? {
        session.exercises.first { $0.sets.contains { $0.id == effortSetID } }
    }

    private func dismissEffort() {
        effortSetID = nil
        effortCompletedAt = nil
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
                        Text(phase == .done
                             ? "\(session.completedSets)/\(session.totalSets) sets"
                             : "Set \(session.currentSetNumber)/\(exercise?.effortCount ?? 0)")
                            .font(Theme.number(11, weight: .bold))
                            .foregroundStyle(phase.gradient)
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

    /// What the wrist is for.
    ///
    /// A rest is the one moment in a workout with nothing in your hands, and
    /// the two things worth knowing are how long is left and what to put on the
    /// bar. Both are set in type you can read from the rack without stopping,
    /// on the same amber the Lock Screen and the Live Activity wear.
    ///
    /// This used to be a 28-point ring and an 18-point number in a strip above
    /// the dials, which is a caption. You had to stop and look at your wrist to
    /// read it, and then look again to find the weight.
    private var restCentrepiece: some View {
        VStack(spacing: 7) {
            // The one part of this screen that changes every second, in a view
            // of its own so that only it is re-evaluated. Drawn here it took
            // the whole logger with it, four times a second, for every rest.
            if let endsAt = rest.endsAt {
                WatchRestCountdown(endsAt: endsAt, totalSeconds: rest.totalSeconds)
            }

            HStack(spacing: 6) {
                Text("RESTING")
                    .font(Theme.eyebrow)
                    .tracking(1.1)
                    .foregroundStyle(SessionPhase.resting.tint.opacity(0.9))

                Spacer(minLength: 0)

                Button {
                    rest.stop()
                    connector.send(.stopRest)
                } label: {
                    Text("Skip")
                }
                .buttonStyle(WatchQuietButtonStyle(tint: Theme.textPrimary, size: 11, compact: true))
                .fixedSize()
            }

            if let set, let exercise {
                Divider().overlay(Theme.hairline)
                upNext(set: set, exercise: exercise)
            }
        }
        .watchCard(padding: 9, phase: .resting)
    }

    /// The load to walk up to, and the exercise it belongs to.
    ///
    /// Tapping it opens the exercise list, which is the same thing tapping the
    /// header does when there is no rest running — during a rest the header is
    /// not on screen, and losing the only way to work out of order because you
    /// happened to be between sets would be a strange thing for the app to do.
    private func upNext(set: WatchSetSnapshot, exercise: WatchExerciseSnapshot) -> some View {
        Button {
            WatchHaptics.tick()
            showingExercises = true
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text("UP NEXT")
                    .font(Theme.microCaps)
                    .tracking(0.9)
                    .foregroundStyle(Theme.textTertiary)

                Text(upNextLoad(set: set, exercise: exercise))
                    .font(Theme.number(23, weight: .heavy))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)

                Text("\(exercise.name) · Set \(session.currentSetNumber)/\(exercise.effortCount)")
                    .font(Theme.rounded(11, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the session's exercises")
    }

    /// "80 kg × 8–10" — the one line that saves a trip back to the phone.
    ///
    /// The weight is whatever the dials currently hold, because a weight the
    /// lifter has just dialled up is the weight they are about to load. The
    /// reps are the *target* rather than the dialled number: what goes in the
    /// rep field is what you did, and that is not known yet.
    private func upNextLoad(set: WatchSetSnapshot, exercise: WatchExerciseSnapshot) -> String {
        if exercise.tracking == .duration { return "\(Int(secondsValue))s" }
        let reps = set.hasRepTarget ? set.targetLabel : "\(Int(repsValue))"
        guard exercise.tracking.logsWeight || set.weightKg > 0 else { return "\(reps) reps" }
        return "\(scale.text(weightDisplay)) \(scale.unit.short) × \(reps)"
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
                    if exercise.tracking.logsWeight || exercise.tracking == .bodyweightReps {
                        tile(title: scale.unit.short, value: trimmed(weightDisplay), field: .weight)
                    }
                    tile(title: "reps", value: "\(Int(repsValue))", field: .reps)
                }
            }
        }
        // One crown target for the whole row. Which number it turns is
        // `editing`; the range and the step follow it.
        //
        // Focusable only once a number has been tapped. While nothing is
        // selected the crown is left to the ScrollView, so it scrolls the
        // screen the way it does everywhere else on the watch.
        .focusable(editing != nil)
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
            // Dialling scrolls nothing, but it is the lifter at the watch.
            focus.touch(at: .now)
            write(turned)
        }
        // Claimed after the pass that made the row focusable, not inside
        // `select` — a focus request made on the tap itself lands a pass too
        // early and is dropped.
        .task(id: editing) { isCrownFocused = editing != nil }
    }

    /// What the exercise asks for, on a line of its own.
    ///
    /// It used to be the caption inside the reps tile, sharing one line with
    /// the word REPS at ten points and shrinking from there — so on any range
    /// wider than a single digit, on the small watch, the thing the lifter
    /// needed was the thing that got scaled away. Nothing else competes for
    /// this line, so nothing shrinks.
    @ViewBuilder
    private func targetLine(_ set: WatchSetSnapshot, exercise: WatchExerciseSnapshot) -> some View {
        if exercise.tracking.logsReps, set.hasRepTarget {
            WatchChip(tint: Theme.textSecondary) {
                Image(systemName: "target")
                    .font(.system(size: 9, weight: .bold))
                Text("Target \(set.targetLabel) reps")
                    .font(Theme.rounded(12, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .accessibilityLabel("Target \(set.targetLabel) reps")
        }
    }

    /// A number, and whether the crown is on it.
    private func tile(title: String, value: String, field: Field) -> some View {
        let isEditing = editing == field
        return WatchValueTile(title: title, value: value, isEditing: isEditing, phase: phase)
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
    @ViewBuilder
    private var stepperRow: some View {
        if editing != nil {
            HStack(spacing: 6) {
                stepButton(symbol: "minus", delta: -crownStep, verb: "Decrease")
                stepButton(symbol: "plus", delta: crownStep, verb: "Increase")
            }
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
        // Held, it keeps stepping — the phone's keys do the same, and on the
        // wrist it is the one way to cover a big change without the crown.
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel("\(verb) \(editingName)")
    }

    private var editingName: String {
        switch editing {
        case .weight: "weight"
        case .reps: "reps"
        case .seconds: "seconds"
        case nil: "value"
        }
    }

    private func step(by delta: Double) {
        guard let editing else { return }
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

    /// Hands the crown a number — or hands it back.
    ///
    /// Tapping the number the crown is already on releases it, so the screen
    /// scrolls again without having to log the set first.
    private func select(_ field: Field) {
        focus.touch(at: .now)
        if editing == field {
            editing = nil
        } else {
            editing = field
            crownValue = currentValue(of: field)
        }
        WatchHaptics.tick()
    }

    /// What the crown writes back to, and the sane bounds for it.
    private func write(_ turned: Double) {
        guard let editing else { return }
        let next: Double
        switch editing {
        // Onto the ladder: the crown is the only way in here — there is no
        // keypad to reach a weight between two pins — so a turn should always
        // land on something the machine can be set to.
        case .weight: next = scale.snap(display: max(0, turned))
        case .reps, .seconds: next = max(0, turned.rounded())
        }
        // Selecting a number hands the crown its current value, which arrives
        // here as a turn that changes nothing. Only a real change counts as
        // the lifter having dialled it.
        guard next != currentValue(of: editing) else { return }
        assign(next, to: editing)
        touched.insert(editing)
    }

    private func currentValue(of field: Field) -> Double {
        switch field {
        case .weight: weightDisplay
        case .reps: repsValue
        case .seconds: secondsValue
        }
    }

    private func assign(_ value: Double, to field: Field) {
        switch field {
        case .weight: weightDisplay = value
        case .reps: repsValue = value
        case .seconds: secondsValue = value
        }
    }

    /// The number the crown is on, or the one it would be on. The rotation's
    /// bounds have to resolve to something even while nothing is selected.
    private var crownField: Field { editing ?? .weight }

    private var crownRange: ClosedRange<Double> {
        switch crownField {
        case .weight: 0...scale.displayCeiling
        case .reps: 0...50
        case .seconds: 5...600
        }
    }

    private var crownStep: Double {
        switch crownField {
        case .weight: scale.increment
        case .reps: 1
        case .seconds: 5
        }
    }

    // MARK: - Saying you're starting

    /// The wrist's half of the announcement — the same one tap the phone
    /// offers, on the device that is already in your hand when you walk up to
    /// the bar.
    ///
    /// It was the phone's alone until now, which meant the set that got timed
    /// was the set you happened to be holding your phone for. Sitting directly
    /// above *Log set*, in the order the two things happen, it is hard to walk
    /// past — and it still costs nothing to ignore, because logging is the
    /// button underneath and is unchanged.
    @ViewBuilder
    private func startStrip(for set: WatchSetSnapshot) -> some View {
        if let startedAt = set.startedAt, !set.isCompleted {
            working(since: startedAt, set: set)
        } else {
            Button {
                // Not a second tap of the Log set that has just gone through:
                // the rest card slides under the thumb as it lands.
                guard acceptsSetTap else { return }
                WatchHaptics.start()
                connector.announceStart(set)
                // The rest is over the moment you say you're going — that is
                // what it was counting down to. Silently, because the tap above
                // has already been felt and two a frame apart read as one
                // stutter rather than as two things.
                if rest.isRunning {
                    rest.stop(silently: true)
                    connector.send(.stopRest)
                }
            } label: {
                Label("Start set", systemImage: "play.fill")
            }
            .buttonStyle(WatchQuietButtonStyle(tint: Theme.accent, weight: .heavy, size: 14))
            .accessibilityHint("Optional. Counts you in, then records the moment this set begins")
        }
    }

    /// The count-in the announcement starts, and the clock it becomes. Both off
    /// one `TimelineView` rather than a ticker of their own — the view already
    /// knows when the set begins. Zero arrives without a tap on the wrist: the
    /// one under the thumb was the signal, and another a few seconds later
    /// would land mid-unrack as a buzz asking to be looked at.
    private func working(since start: Date, set: WatchSetSnapshot) -> some View {
        HStack(spacing: 7) {
            WatchGlyphTile(symbol: "stopwatch.fill", tint: Theme.accent, size: 24)

            TimelineView(.periodic(from: SetLeadIn.tickAnchor(for: start), by: 1)) { context in
                readout(SetStartReading(start: start, now: context.date))
            }

            Spacer(minLength: 0)

            Button {
                WatchHaptics.tick()
                connector.cancelStart(set)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .black))
            }
            .buttonStyle(WatchQuietButtonStyle(tint: Theme.textTertiary, size: 11, compact: true))
            .fixedSize()
            .accessibilityLabel("Cancel — this set hasn't started")
        }
        .watchCard(padding: 7, radius: 12, phase: .working)
    }

    private func readout(_ reading: SetStartReading) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(reading.eyebrow)
                .font(Theme.microCaps)
                .tracking(0.8)
                .foregroundStyle(Theme.accent.wash)
            Text(reading.figure)
                .font(Theme.number(17, weight: .bold))
                .foregroundStyle(Theme.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(reading.spoken)
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

    /// Whether a tap that changes the record is one the lifter meant, or the
    /// second half of a double tap on Log set. See `WatchLoggerRules`.
    private var acceptsSetTap: Bool {
        WatchLoggerRules.acceptsSetTap(lastLoggedAt: lastLoggedAt, now: .now)
    }

    private func log(set: WatchSetSnapshot, exercise: WatchExerciseSnapshot) {
        // The mirror is updated in this same call, so by the second tap of a
        // double tap the button is already bound to the next set, and it would
        // log that one with the same numbers.
        guard acceptsSetTap else { return }
        lastLoggedAt = .now
        WatchHaptics.log()
        let moment = connector.logSet(
            set,
            weightKg: scale.kilograms(weightDisplay),
            reps: Int(repsValue),
            seconds: Int(secondsValue)
        )
        editing = nil
        isCrownFocused = false
        if session.effortEnabled == true {
            effortCompletedAt = moment
            effortSetID = set.id
        }
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
                guard acceptsSetTap else { return }
                undo(last)
            } label: {
                Label("Undo last set", systemImage: "arrow.uturn.backward")
            }
            .buttonStyle(WatchQuietButtonStyle(tint: Theme.textSecondary, weight: .semibold, size: 12))
        }
    }

    /// The effort question, in the flow of the logger and below Log set rather
    /// than over it. Nothing above it ever moves for it, so a thumb going for
    /// the next set of a drop set or a superset finds Log set where it was, and
    /// there is nothing to dismiss: it is answered, or it is left, and it
    /// folds back into `effortButton` on its own.
    @ViewBuilder
    private var effortPrompt: some View {
        if let subject = effortSet, let owner = effortExercise {
            WatchSetFeelView(
                exerciseName: owner.name, setNumber: owner.number(of: subject),
                current: subject.rpe.map(SetFeel.nearest(to:)),
                onPick: { feel in
                    connector.rateSet(subject, rpe: subject.rpe == feel.rawValue ? nil : feel.rawValue)
                    WatchHaptics.tick()
                    // An answer is a touch, so the countdown waits its full
                    // delay after it. A question left to fold away is not, and
                    // the countdown can come back as it goes.
                    focus.touch(at: .now)
                    dismissEffort()
                }
            )
        } else {
            effortButton
        }
    }

    /// A skipped answer stays available during the rest, and a mis-tap can be
    /// corrected without undoing the set. Picking the same answer clears it.
    @ViewBuilder
    private var effortButton: some View {
        if session.effortEnabled == true, let last = lastCompletedSet, let moment = last.completedAt {
            Button {
                effortCompletedAt = moment
                effortSetID = last.id
                editing = nil
                isCrownFocused = false
            } label: {
                if let rpe = last.rpe {
                    Text("Last set: \(SetFeel.nearest(to: rpe).label)")
                } else {
                    Text("Rate last set")
                }
            }
            .buttonStyle(WatchQuietButtonStyle(tint: Theme.accent, size: 12))
            .accessibilityHint("Change difficulty. Tap the selected answer to clear it")
        }
    }

    private func undo(_ set: WatchSetSnapshot) {
        dismissEffort()
        connector.undoSet(set)
        if rest.isRunning {
            rest.stop()
            connector.send(.stopRest)
        } else {
            WatchHaptics.tick()
        }
    }

    /// Completion order matters when the lifter works through exercises out of order.
    private var lastCompletedSet: WatchSetSnapshot? {
        let completed = session.allSets.filter(\.isCompleted)
        let stamped = completed.filter { $0.completedAt != nil }
        return stamped.max {
            ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast)
        } ?? completed.last
    }

    // MARK: - State

    /// Loads the set that's up into the dials, carrying last time's numbers
    /// when the set has none of its own.
    private func load(_ set: WatchSetSnapshot?) {
        guard set != nil else { return }
        // Nothing is selected until it is tapped: until then the crown
        // scrolls the screen rather than changing a number. Nothing has been
        // dialled on this set yet either, so every number follows the phone.
        editing = nil
        touched = []
        adopt(set)
    }

    /// Takes the phone's revision of the set that's already up.
    ///
    /// The phone owns these numbers and goes on revising them after the fact:
    /// the load carried down from the set just logged is the ordinary case, and
    /// a weight changed on the phone mid-session is the other. Until the dials
    /// followed that, the wrist sat on the weight the lifter had moved away
    /// from and wrote it back over the phone's the next time they logged.
    ///
    /// What the lifter has dialled here is theirs and is left alone. The weight
    /// changing under a thumb already reaching for the bar is worse than the
    /// two screens disagreeing.
    private func adopt(_ set: WatchSetSnapshot?) {
        guard let set else { return }
        if !touched.contains(.weight) { weightDisplay = scale.display(set.weightKg) }
        if !touched.contains(.reps) { repsValue = Double(set.reps > 0 ? set.reps : max(set.targetRepsLow, 1)) }
        if !touched.contains(.seconds) { secondsValue = Double(set.seconds > 0 ? set.seconds : 45) }
    }

    private func trimmed(_ value: Double) -> String { scale.text(value) }
}

// MARK: - The countdown

/// The rest's clock and its bar, drawn from the end date alone.
///
/// Takes values rather than the timer, so nothing about it changes between
/// ticks except the time. The `TimelineView` re-evaluates this small view
/// once a second and leaves the logger that holds it alone.
struct WatchRestCountdown: View {
    let endsAt: Date
    let totalSeconds: Int

    var body: some View {
        TimelineView(.periodic(from: WatchRestRules.tickAnchor(endsAt: endsAt, totalSeconds: totalSeconds,
                                                              now: .now), by: 1)) { context in
            let remaining = max(0, endsAt.timeIntervalSince(context.date))
            VStack(spacing: 7) {
                Text(remaining.clockString)
                    .font(Theme.number(46, weight: .heavy))
                    .foregroundStyle(SessionPhase.resting.gradient)
                    .shadow(color: SessionPhase.resting.glow, radius: 10)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("\(Int(remaining.rounded())) seconds of rest left")

                WatchRestProgressBar(progress: progress(remaining: remaining))
            }
        }
    }

    private func progress(remaining: TimeInterval) -> Double {
        guard totalSeconds > 0 else { return 0 }
        return min(1, max(0, 1 - remaining / Double(totalSeconds)))
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
                switch WatchLoggerRules.tap(on: exercise) {
                case .focus:
                    Button {
                        WatchHaptics.tick()
                        connector.focus(on: exercise.id)
                        dismiss()
                    } label: {
                        row(for: exercise)
                    }
                    .listRowBackground(rowBackground)
                case .review:
                    // Looking at what was logged, and nothing more. Focusing a
                    // finished exercise moved the phone, the Lock Screen and
                    // the dock off the one being lifted, so this sends nothing.
                    NavigationLink {
                        WatchExerciseReviewView(exercise: exercise, unit: session.unit)
                    } label: {
                        row(for: exercise)
                    }
                    .listRowBackground(rowBackground)
                }
            }
        }
        .navigationTitle("Exercises")
    }

    private func row(for exercise: WatchExerciseSnapshot) -> some View {
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

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(LinearGradient(colors: [Theme.surfaceRaised, Theme.surface],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.hairline, lineWidth: 1)
            )
    }
}

/// A finished exercise, read-only: what was logged on each set. Reached from
/// the exercise list without moving the session onto it.
struct WatchExerciseReviewView: View {
    let exercise: WatchExerciseSnapshot
    let unit: WeightUnit

    private var scale: LoadScale { exercise.resolvedScale(sessionUnit: unit) }

    var body: some View {
        List {
            ForEach(exercise.sets.filter(\.isCompleted)) { set in
                VStack(alignment: .leading, spacing: 1) {
                    Text("Set \(exercise.number(of: set))")
                        .font(Theme.rounded(11, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    Text(summary(of: set))
                        .font(Theme.number(15, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if let rpe = set.rpe {
                        Text(SetFeel.nearest(to: rpe).label)
                            .font(Theme.rounded(11, weight: .semibold))
                            .foregroundStyle(SetFeel.nearest(to: rpe).tint)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle(exercise.name)
    }

    /// The numbers the exercise is tracked in, and only those: a set of
    /// bodyweight reps says reps, not "0 kg".
    private func summary(of set: WatchSetSnapshot) -> String {
        if exercise.tracking == .duration { return "\(set.seconds)s" }
        guard exercise.tracking.logsWeight || set.weightKg > 0 else { return "\(set.reps) reps" }
        return "\(scale.text(scale.display(set.weightKg))) \(scale.unit.short) × \(set.reps)"
    }
}
