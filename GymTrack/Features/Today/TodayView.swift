import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Binding var activeWorkout: ActiveWorkout?
    @Binding var isSessionExpanded: Bool

    @Query(sort: \Plan.createdAt) private var plans: [Plan]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var showingDayPicker = false
    @State private var showingSettings = false
    @State private var showingCoachReview = false
    @State private var showingPastWorkout = false
    @State private var pastSession: WorkoutSession?

    private var activePlan: Plan? { Plan.displayed(among: plans) }
    private var scheduledDay: PlanDay? { activePlan?.nextDay(on: .now, after: finishedSessions) }
    /// Nothing is pinned to today, so the card is offering the next day of a
    /// rotation. Calling that "today's session" would state a schedule the
    /// plan never set.
    private var isNextInRotation: Bool { activePlan?.day(for: .now) == nil }
    private var finishedSessions: [WorkoutSession] { sessions.filter { !$0.isActive } }
    /// The workout that trained a day of the plan today, the scheduled one
    /// first. A freestyle session or the tail of one that started last night
    /// leaves the scheduled day on the card as if nothing had been done, so a
    /// ten-minute arm pump doesn't turn Leg Day into a victory card. An empty
    /// session is not a day trained either.
    private var completedToday: WorkoutSession? {
        TrainingStats.completedToday(in: sessions, plan: activePlan)
    }
    private var streak: TrainingStats.Streak { TrainingStats.streak(from: finishedSessions) }

    /// Sessions trained since the start of the current week. One closed with
    /// nothing logged is left out, as the week strip and the calendar leave it.
    private var thisWeek: [WorkoutSession] {
        TrainingStats.sessionsThisWeek(finishedSessions)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    greeting
                    if let expiry = BuildExpiry.upcoming() { expiryNotice(expiry) }
                    if CoachInbox.shared.showsOnToday { coachNotice }
                    heroCard
                    weekStrip
                    statsRow
                    if !finishedSessions.isEmpty { recentSection }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 28)
            }
            .scrollIndicators(.hidden)
            .gtScreenBackground()
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showingSettings = true } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingCoachReview) {
                NavigationStack { CoachReviewView(showsClose: true) }
                    .gtSheetBackground()
            }
            .sheet(isPresented: $showingDayPicker) {
                DayPickerSheet(plan: activePlan) { day in
                    showingDayPicker = false
                    start(day: day)
                }
            }
            .sheet(isPresented: $showingPastWorkout) {
                if let activePlan {
                    PastWorkoutSheet(plan: activePlan, history: finishedSessions)
                }
            }
            .navigationDestination(item: $pastSession) { SessionDetailView(session: $0) }
        }
    }

    // MARK: - Coach

    /// Shown only while a review is waiting that has something to decide, and
    /// never otherwise: no badge, no count, nothing to dismiss.
    private var coachNotice: some View {
        Button { showingCoachReview = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "checklist")
                    .foregroundStyle(Theme.accent)
                    .accessibilityHidden(true)
                Text("A plan review is ready")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                DisclosureChevron()
            }
            .gtCard(padding: 12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Signing

    /// Shown a few days before this build stops opening, and never otherwise.
    /// Nothing to dismiss: a fresh install moves the date and it goes.
    private func expiryNotice(_ expiry: Date) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(Theme.warning)
            Text("This build stops opening \(Self.expiryMoment(expiry)). Reinstall it from your Mac with scripts/install-phone.sh before then; your workouts stay.")
                .font(Theme.rounded(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .gtCard(padding: 12)
    }

    private static func expiryMoment(_ expiry: Date) -> String {
        let calendar = Calendar.current
        let time = expiry.formatted(date: .omitted, time: .shortened)
        if calendar.isDateInToday(expiry) { return "today at \(time)" }
        if calendar.isDateInTomorrow(expiry) { return "tomorrow at \(time)" }
        return "on \(expiry.formatted(.dateTime.weekday(.wide))) at \(time)"
    }

    // MARK: - Greeting

    private var greeting: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()).uppercased())
                    .font(Theme.eyebrow)
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Text(greetingText)
                    .font(Theme.rounded(28, weight: .heavy))
                    .foregroundStyle(Theme.ink)
            }
            Spacer()
            if streak.current > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .foregroundStyle(Theme.accent.wash)
                    Text("\(streak.current)")
                        .font(Theme.number(15))
                        .foregroundStyle(Theme.accent)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background {
                    Capsule().fill(LinearGradient(colors: [Theme.accent.opacity(0.22), Theme.accent.opacity(0.06)],
                                                  startPoint: .top, endPoint: .bottom))
                }
                .overlay { Capsule().strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1) }
                .shadow(color: Theme.accent.opacity(0.22), radius: 8, y: 2)
            }
        }
        .padding(.top, 4)
    }

    private var greetingText: String {
        let name = AppSettings.shared.userName
        let hour = Calendar.current.component(.hour, from: .now)
        let part = hour < 12 ? "Morning" : hour < 18 ? "Afternoon" : "Evening"
        return name.isEmpty ? "Good \(part.lowercased())" : "\(part), \(name)"
    }

    // MARK: - Hero

    @ViewBuilder
    private var heroCard: some View {
        if let workout = activeWorkout {
            inProgressCard(workout)
        } else if let session = completedToday {
            completedCard(session)
        } else if let day = scheduledDay {
            scheduledCard(day)
        } else if activePlan != nil {
            restDayCard
        } else {
            EmptyStateView(
                icon: "list.bullet.rectangle.portrait",
                title: "No plan yet",
                message: "Create a routine and today's session will show up right here.",
                actionTitle: "Start a freestyle session",
                action: startFreestyle
            )
            .gtCard()
        }
    }

    /// Today's hero while a session is open. The card people land on first has
    /// to say "you're mid-workout" before it says anything else — otherwise a
    /// minimised session looks like no session at all.
    private func inProgressCard(_ workout: ActiveWorkout) -> some View {
        let phase = workout.phase
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(phase.tint)
                            .frame(width: 7, height: 7)
                            .shadow(color: phase.glow, radius: 4)
                        Text(phase == .resting ? "RESTING" : "SESSION IN PROGRESS")
                            .font(Theme.eyebrow)
                            .tracking(1.4)
                            .foregroundStyle(phase.tint)
                    }
                    Text(workout.session.title)
                        .font(Theme.rounded(26, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    Text(workout.restTimer.isRunning
                         ? "Resting · then \(workout.currentGroup?.name ?? "your next set")"
                         : sessionStatus(workout))
                        .font(Theme.rounded(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        // "Standing Barbell Overhead Press · set…" hid the one
                        // part of the line that changes; cut the name instead.
                        .truncationMode(.middle)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    VStack(spacing: 2) {
                        Text(workout.session.duration.clockString)
                            .font(Theme.number(22))
                            .foregroundStyle(phase.tint)
                            .shadow(color: phase.glow, radius: 8)
                        Text("elapsed")
                            .gtFont(size: 10, weight: .semibold, relativeTo: .caption2, maxScale: 1.5)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }

            VStack(spacing: 9) {
                HStack(spacing: 14) {
                    ProgressRing(progress: workout.progress, lineWidth: 6, phase: phase,
                                 label: "\(Int(workout.progress * 100))")
                        .frame(width: 46, height: 46)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(workout.completedCount) of \(workout.totalCount) sets logged")
                            .gtFont(size: 14, weight: .bold, relativeTo: .subheadline)
                            .foregroundStyle(Theme.ink)
                        Text("\(AppSettings.shared.weight(workout.volumeKg)) moved so far")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer()
                }
                PhaseProgressBar(completed: workout.completedCount,
                                 total: workout.totalCount,
                                 phase: phase, height: 5, maxTicks: 24)
            }
            .gtWell()

            // Amber is the session's state, not an action — a rest isn't
            // something you press. The button stays the colour of the thing it
            // actually does, exactly as the watch's log button does mid-rest.
            Button(phase == .done ? "Back to finish up" : "Back to workout") { isSessionExpanded = true }
                .buttonStyle(PrimaryButtonStyle(phase: phase == .done ? .done : .working))

            Label("Also on your Lock Screen while the app is closed",
                  systemImage: "lock.iphone")
                .font(Theme.rounded(11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity)
        }
        .gtCard(padding: 18, phase: phase)
    }

    private func sessionStatus(_ workout: ActiveWorkout) -> String {
        if workout.totalCount > 0, workout.completedCount >= workout.totalCount {
            return "Every set logged — ready to finish"
        }
        guard let group = workout.currentGroup else { return "Tap to log your first set" }
        return "\(group.name) · set \(workout.nextSetNumber) of \(workout.currentSetTotal)"
    }

    /// Once today's work is saved, the hero stops offering the same workout as
    /// though it never happened. The result is useful at a glance, while both
    /// reviewing it and choosing to train again remain close at hand.
    private func completedCard(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 13) {
                GlyphTile(symbol: "checkmark", tint: SessionPhase.done.tint, size: 54, solid: true)

                VStack(alignment: .leading, spacing: 3) {
                    Text("WORKOUT DONE")
                        .font(Theme.eyebrow)
                        .tracking(1.4)
                        .foregroundStyle(SessionPhase.done.tint)
                    Text(session.title)
                        .font(Theme.rounded(24, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                    if session.isLoggedAfterwards {
                        Text("Logged afterwards")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    } else if let endedAt = session.endedAt {
                        Text("Finished at \(endedAt.formatted(.dateTime.hour().minute()))")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: 0)
            }

            HStack(spacing: 0) {
                completionStat("\(session.effortSets.count)", label: "sets")
                completionDivider
                completionStat(AppSettings.shared.weight(session.totalVolumeKg), label: "moved")
                completionDivider
                completionStat(session.isLoggedAfterwards ? "—" : session.duration.durationString, label: "time")
            }
            .gtWell(vertical: 12, horizontal: 8)

            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(SessionPhase.done.tint)
                Text("You're done for today. Recovery starts now.")
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }

            Button("View workout") { pastSession = session }
                .buttonStyle(PrimaryButtonStyle(phase: .done))

            Button("Start another workout") {
                if activePlan != nil {
                    showingDayPicker = true
                } else {
                    startFreestyle()
                }
            }
            .gtFont(size: 14, weight: .semibold, relativeTo: .subheadline)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
        }
        .gtCard(padding: 18, phase: .done)
        .accessibilityElement(children: .contain)
    }

    private func completionStat(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.number(17, weight: .bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label.uppercased())
                .font(Theme.microCaps)
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var completionDivider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.08))
            .frame(width: 1, height: 32)
    }

    private func scheduledCard(_ day: PlanDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(isNextInRotation ? "NEXT UP" : "TODAY'S SESSION")
                        .font(Theme.eyebrow)
                        .tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)
                    Text(day.name)
                        .font(Theme.rounded(26, weight: .heavy))
                        .foregroundStyle(Theme.ink)
                    if let plan = activePlan {
                        Text(plan.name)
                            .font(Theme.rounded(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(day.items.count)")
                        .font(Theme.number(26))
                        .foregroundStyle(Theme.accent.wash)
                    Text("moves")
                        .gtFont(size: 10, weight: .semibold, relativeTo: .caption2, maxScale: 1.5)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if !day.targetedMuscles.isEmpty {
                HStack(spacing: 6) {
                    ForEach(day.targetedMuscles.prefix(4), id: \.self) { muscle in
                        Pill(text: muscle.name, color: Theme.accent)
                    }
                }
            }

            VStack(spacing: 8) {
                ForEach(day.orderedItems.prefix(4)) { item in
                    HStack(spacing: 10) {
                        Image(systemName: item.catalog?.symbol ?? "dumbbell.fill")
                            .gtIcon(size: 12, weight: .semibold, relativeTo: .subheadline, maxScale: 1.6)
                            .foregroundStyle(Theme.accent.opacity(0.75))
                            .frame(width: 20)
                        Text(item.name)
                            .gtFont(size: 14, weight: .semibold, relativeTo: .subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(item.targetSets) × \(item.tracking == .duration ? "\(item.targetSeconds)s" : item.repRangeLabel)")
                            .font(Theme.number(13, weight: .semibold))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                if day.items.count > 4 {
                    Text("+ \(day.items.count - 4) more")
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .gtWell()

            Button("Start workout") { start(day: day) }
                .buttonStyle(PrimaryButtonStyle())
                .accessibilityIdentifier("today.startWorkout")

            Button("Train something else") { showingDayPicker = true }
                .gtFont(size: 14, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .gtCard(padding: 18)
    }

    private var restDayCard: some View {
        VStack(spacing: 14) {
            GlyphTile(symbol: "moon.zzz.fill", tint: SessionPhase.done.tint, size: 62)
            Text(activePlan?.trainingDayCount == 0 ? "Build your routine" : "Rest day")
                .font(Theme.rounded(22, weight: .heavy))
                .foregroundStyle(Theme.ink)
            Text(activePlan?.trainingDayCount == 0
                 ? "Add exercises to a day in Plan, or start a freestyle workout now."
                 : "Nothing scheduled. Recovery is part of the plan — but the gym is still open if you want it.")
                .gtFont(size: 14, weight: .medium, relativeTo: .subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                if activePlan?.trainingDayCount ?? 0 > 0 {
                    Button("Pick a session") { showingDayPicker = true }
                        .buttonStyle(PrimaryButtonStyle(phase: .done))
                }
                Button("Freestyle workout", action: startFreestyle)
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .gtCard(padding: 22)
    }

    // MARK: - Week strip

    /// Training days, like every other reader, so in the small hours the strip
    /// still marks the night's day as today and a session started then fills
    /// it in. See `TrainingDay`.
    private var weekStrip: some View {
        let calendar = Calendar.current
        let today = TrainingDay.key(for: .now, calendar: calendar)
        let start = TrainingStats.weekInterval(containing: today, calendar: calendar).start
        let trained = TrainingStats.trainedDays(in: finishedSessions.filter { $0.startedAt >= start },
                                                calendar: calendar)
        let offeredToday = scheduledDay != nil

        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let date = TrainingStats.startOfDay(offset, from: start, calendar: calendar)
                let weekday = calendar.component(.weekday, from: date)
                let isToday = date == today
                let didTrain = trained.contains(date)
                // Only today can be marked from the rotation. It moves on when
                // a day is trained, not when the date changes, so marking every
                // later unpinned day would promise sessions nobody scheduled.
                // Other days keep to what is pinned, asked by weekday because
                // `date` is a key, and `day(for:)` reads midnight as the night
                // before.
                let isScheduled = isToday ? offeredToday : activePlan?.day(onWeekday: weekday) != nil

                VStack(spacing: 6) {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(Theme.rounded(11, weight: .bold))
                        .foregroundStyle(isToday ? Theme.accent : Theme.textTertiary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(didTrain
                                  ? AnyShapeStyle(SessionPhase.working.gradient)
                                  : AnyShapeStyle(Theme.panel))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(didTrain ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.edge),
                                                  lineWidth: 1)
                            }
                            .shadow(color: didTrain ? SessionPhase.working.glow : .clear, radius: 7, y: 2)
                        if !didTrain && isScheduled {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .strokeBorder(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                        }
                        if didTrain {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .black))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(height: 38)
                    .overlay(alignment: .bottom) {
                        if isToday {
                            Circle().fill(Theme.accent).frame(width: 4, height: 4).offset(y: 7)
                        }
                    }
                }
            }
        }
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    // MARK: - Stats

    private var statsRow: some View {
        HStack(spacing: 10) {
            StatTile(value: "\(thisWeek.count)", label: "This week",
                     caption: activePlan.map { "of \($0.trainingDayCount) planned" })
            StatTile(value: AppSettings.shared.weightUnit.fromKg(TrainingStats.totalVolume(thisWeek)).compactVolume,
                     label: "Volume \(AppSettings.shared.weightUnit.short)",
                     caption: "this week")
            StatTile(value: "\(streak.longest)", label: "Best streak", caption: "days")
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Recent sessions", action: pastWorkoutAction)
            ForEach(finishedSessions.prefix(4)) { session in
                Button { pastSession = session } label: {
                    SessionRow(session: session)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    /// Only with a plan to log against. The sheet builds its rows from a plan
    /// day, and a freestyle session remembered afterwards would be a list of
    /// exercises picked from memory with nothing to check them against.
    private var pastWorkoutAction: (label: String, perform: () -> Void)? {
        guard let activePlan, activePlan.trainingDayCount > 0 else { return nil }
        return ("Log past workout", { showingPastWorkout = true })
    }

    // MARK: - Actions

    private func start(day: PlanDay) {
        activeWorkout = ActiveWorkout.start(day: day, plan: activePlan, context: context, history: finishedSessions)
        isSessionExpanded = true
        Haptics.log()
    }

    private func startFreestyle() {
        activeWorkout = ActiveWorkout.startFreestyle(context: context, history: finishedSessions)
        isSessionExpanded = true
        Haptics.log()
    }
}

// MARK: - Session row

struct SessionRow: View {
    let session: WorkoutSession

    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(session.startedAt.formatted(.dateTime.day()))
                    .font(Theme.number(17))
                    .foregroundStyle(Theme.ink)
                Text(session.startedAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(Theme.rounded(9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 44, height: 44)
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Theme.edge, lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("\(session.effortSets.count) sets · \(AppSettings.shared.weight(session.totalVolumeKg)) · \(session.lengthText)")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            DisclosureChevron()
        }
        .gtCard(padding: 12)
    }
}

// MARK: - Day picker

struct DayPickerSheet: View {
    let plan: Plan?
    let onPick: (PlanDay) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(plan?.orderedDays.filter { !$0.isRest && !$0.items.isEmpty } ?? []) { day in
                        Button { onPick(day) } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(day.name)
                                        .font(Theme.rounded(16, weight: .bold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text("\(day.items.count) exercises · \(day.totalSets) sets")
                                        .font(Theme.rounded(12, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                if let weekday = day.weekdayShortName {
                                    Pill(text: weekday)
                                }
                                DisclosureChevron()
                            }
                            .gtCard(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .gtScreenBackground()
            .navigationTitle("Choose a session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .gtSheetBackground()
    }
}
