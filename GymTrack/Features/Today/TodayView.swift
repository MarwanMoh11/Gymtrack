import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Binding var activeWorkout: ActiveWorkout?

    @Query(sort: \Plan.createdAt) private var plans: [Plan]
    @Query(sort: \WorkoutSession.startedAt, order: .reverse) private var sessions: [WorkoutSession]

    @State private var showingDayPicker = false
    @State private var showingSettings = false
    @State private var pastSession: WorkoutSession?

    private var activePlan: Plan? { plans.first(where: \.isActive) ?? plans.first }
    private var scheduledDay: PlanDay? { activePlan?.day(for: .now) }
    private var finishedSessions: [WorkoutSession] { sessions.filter { !$0.isActive } }
    private var streak: TrainingStats.Streak { TrainingStats.streak(from: finishedSessions) }

    /// Sessions logged since Monday of the current week.
    private var thisWeek: [WorkoutSession] {
        let calendar = Calendar.current
        guard let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start else { return [] }
        return finishedSessions.filter { $0.startedAt >= weekStart }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    greeting
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
                }
            }
            .sheet(isPresented: $showingSettings) { SettingsView() }
            .sheet(isPresented: $showingDayPicker) {
                DayPickerSheet(plan: activePlan) { day in
                    showingDayPicker = false
                    start(day: day)
                }
            }
            .navigationDestination(item: $pastSession) { SessionDetailView(session: $0) }
        }
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
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if streak.current > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                    Text("\(streak.current)")
                        .font(Theme.number(15))
                }
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(Theme.accentDim, in: Capsule())
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
        if let day = scheduledDay {
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

    private func scheduledCard(_ day: PlanDay) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("TODAY'S SESSION")
                        .font(Theme.eyebrow)
                        .tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)
                    Text(day.name)
                        .font(Theme.rounded(26, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
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
                        .foregroundStyle(Theme.accent)
                    Text("moves")
                        .font(Theme.rounded(10, weight: .semibold))
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
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 20)
                        Text(item.name)
                            .font(Theme.rounded(14, weight: .semibold))
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
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(Color.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button("Start workout") { start(day: day) }
                .buttonStyle(PrimaryButtonStyle())

            Button("Train something else") { showingDayPicker = true }
                .font(Theme.rounded(14, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
        }
        .gtCard(padding: 18, background: Theme.surface)
    }

    private var restDayCard: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 62, height: 62)
                .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            Text("Rest day")
                .font(Theme.rounded(22, weight: .heavy))
                .foregroundStyle(Theme.textPrimary)
            Text("Nothing scheduled. Recovery is part of the plan — but the gym is still open if you want it.")
                .font(Theme.rounded(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 8) {
                Button("Pick a session") { showingDayPicker = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Freestyle workout", action: startFreestyle)
                    .buttonStyle(SecondaryButtonStyle())
            }
            .padding(.top, 4)
        }
        .gtCard(padding: 22)
    }

    // MARK: - Week strip

    private var weekStrip: some View {
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        let trained = Set(finishedSessions.map { calendar.startOfDay(for: $0.startedAt) })

        return HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { offset in
                let date = calendar.date(byAdding: .day, value: offset, to: start)!
                let day = calendar.startOfDay(for: date)
                let isToday = calendar.isDateInToday(date)
                let didTrain = trained.contains(day)
                let isScheduled = activePlan?.day(for: date) != nil

                VStack(spacing: 6) {
                    Text(calendar.veryShortWeekdaySymbols[calendar.component(.weekday, from: date) - 1])
                        .font(Theme.rounded(11, weight: .bold))
                        .foregroundStyle(isToday ? Theme.accent : Theme.textTertiary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(didTrain ? Theme.accent : Theme.surface)
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
            StatTile(value: TrainingStats.totalVolume(thisWeek).compactVolume,
                     label: "Volume \(AppSettings.shared.weightUnit.short)",
                     caption: "last 7 days")
            StatTile(value: "\(streak.longest)", label: "Best streak", caption: "days")
        }
    }

    // MARK: - Recent

    private var recentSection: some View {
        VStack(spacing: 10) {
            SectionHeader("Recent sessions")
            ForEach(finishedSessions.prefix(4)) { session in
                Button { pastSession = session } label: {
                    SessionRow(session: session)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - Actions

    private func start(day: PlanDay) {
        activeWorkout = ActiveWorkout.start(day: day, plan: activePlan, context: context, history: finishedSessions)
        Haptics.log()
    }

    private func startFreestyle() {
        activeWorkout = ActiveWorkout.startFreestyle(context: context, history: finishedSessions)
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
                    .foregroundStyle(Theme.textPrimary)
                Text(session.startedAt.formatted(.dateTime.month(.abbreviated)).uppercased())
                    .font(Theme.rounded(9, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 44, height: 44)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(session.title)
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text("\(session.completedSets.count) sets · \(AppSettings.shared.weight(session.totalVolumeKg)) · \(session.duration.durationString)")
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
                    ForEach(plan?.orderedDays.filter { !$0.isRest } ?? []) { day in
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
        .presentationBackground(Theme.background)
    }
}
