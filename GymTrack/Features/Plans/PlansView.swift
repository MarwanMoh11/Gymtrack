import SwiftUI
import SwiftData

struct PlansView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Plan.createdAt) private var plans: [Plan]

    @State private var showingTemplates = false
    @State private var planPendingDeletion: Plan?

    private var activePlan: Plan? { plans.first(where: \.isActive) ?? plans.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let plan = activePlan {
                        activePlanSection(plan)
                    }

                    let others = plans.filter { $0.id != activePlan?.id }
                    if !others.isEmpty {
                        VStack(spacing: 8) {
                            SectionHeader("Other routines")
                            ForEach(others) { plan in
                                planRow(plan)
                            }
                        }
                    }

                    Button {
                        showingTemplates = true
                    } label: {
                        Label("Add a routine", systemImage: "plus")
                    }
                    .buttonStyle(SecondaryButtonStyle())

                    if plans.isEmpty {
                        EmptyStateView(icon: "list.bullet.rectangle.portrait",
                                       title: "No routines yet",
                                       message: "Start from a template or build one exercise at a time.",
                                       actionTitle: "Browse templates") { showingTemplates = true }
                    }
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .gtScreenBackground()
            .navigationTitle("Plan")
            .sheet(isPresented: $showingTemplates) {
                TemplatePickerView { template in
                    template.materialise(in: context, makeActive: plans.isEmpty)
                    try? context.save()
                    showingTemplates = false
                    Haptics.success()
                } onBlank: {
                    let plan = Plan(name: "My Routine", summary: "", isActive: plans.isEmpty)
                    context.insert(plan)
                    try? context.save()
                    showingTemplates = false
                }
            }
            .confirmationDialog("Delete this routine?",
                                isPresented: Binding(get: { planPendingDeletion != nil },
                                                     set: { if !$0 { planPendingDeletion = nil } }),
                                titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let plan = planPendingDeletion {
                        context.delete(plan)
                        try? context.save()
                    }
                    planPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) { planPendingDeletion = nil }
            } message: {
                Text("Sessions you've already logged are kept — only the routine is removed.")
            }
        }
    }

    // MARK: - Active plan

    private func activePlanSection(_ plan: Plan) -> some View {
        VStack(spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("ACTIVE ROUTINE")
                        .font(Theme.eyebrow).tracking(1.4)
                        .foregroundStyle(Theme.accent)
                    Text(plan.name)
                        .font(Theme.rounded(24, weight: .heavy))
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(plan.trainingDayCount) sessions a week")
                        .font(Theme.rounded(13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                NavigationLink {
                    PlanSettingsView(plan: plan)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 38, height: 38)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            .gtCard()

            VStack(spacing: 8) {
                SectionHeader("Days", action: ("Add day", { addDay(to: plan) }))
                ForEach(plan.orderedDays) { day in
                    NavigationLink {
                        DayEditorView(day: day)
                    } label: {
                        dayRow(day)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func dayRow(_ day: PlanDay) -> some View {
        HStack(spacing: 12) {
            VStack(spacing: 0) {
                Text(day.weekdayShortName?.uppercased() ?? "—")
                    .font(Theme.rounded(11, weight: .black))
                    .foregroundStyle(day.weekday == nil ? Theme.textTertiary : Theme.accent)
            }
            .frame(width: 42, height: 42)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(day.name)
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text(day.isRest
                     ? "Rest day"
                     : "\(day.items.count) exercises · \(day.totalSets) sets")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            DisclosureChevron()
        }
        .gtCard(padding: 12)
    }

    private func planRow(_ plan: Plan) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.name)
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(plan.trainingDayCount) sessions a week")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            Button("Activate") { activate(plan) }
                .font(Theme.rounded(12, weight: .bold))
                .foregroundStyle(.black)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.accent, in: Capsule())
                .buttonStyle(.plain)
            Button {
                planPendingDeletion = plan
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .gtCard(padding: 12)
    }

    // MARK: - Actions

    private func activate(_ plan: Plan) {
        for other in plans { other.isActive = false }
        plan.isActive = true
        try? context.save()
        Haptics.success()
    }

    private func addDay(to plan: Plan) {
        let day = PlanDay(name: "New Day", order: plan.days.count)
        day.plan = plan
        context.insert(day)
        try? context.save()
        Haptics.tick()
    }
}

// MARK: - Template picker

struct TemplatePickerView: View {
    let onPick: (PlanTemplate) -> Void
    let onBlank: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(PlanTemplate.all) { template in
                        Button { onPick(template) } label: {
                            HStack(spacing: 14) {
                                Image(systemName: template.symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 44, height: 44)
                                    .background(Theme.accentDim, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(template.name)
                                        .font(Theme.rounded(16, weight: .bold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(template.summary)
                                        .font(Theme.rounded(12, weight: .medium))
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Pill(text: "\(template.daysPerWeek)×/week", color: Theme.accent)
                                }
                                Spacer(minLength: 0)
                            }
                            .gtCard(padding: 14)
                        }
                        .buttonStyle(.plain)
                    }

                    Button("Start from blank", action: onBlank)
                        .buttonStyle(SecondaryButtonStyle())
                        .padding(.top, 4)
                }
                .padding(16)
            }
            .scrollIndicators(.hidden)
            .gtScreenBackground()
            .navigationTitle("Add a routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationBackground(Theme.background)
    }
}

// MARK: - Plan settings

struct PlanSettingsView: View {
    @Bindable var plan: Plan
    @Environment(\.modelContext) private var context

    var body: some View {
        Form {
            Section("Name") {
                TextField("Routine name", text: $plan.name)
            }
            .listRowBackground(Theme.surface)

            Section("Notes") {
                TextField("What this routine is for", text: $plan.summary, axis: .vertical)
                    .lineLimit(2...5)
            }
            .listRowBackground(Theme.surface)

            Section {
                LabeledContent("Days", value: "\(plan.days.count)")
                LabeledContent("Training days", value: "\(plan.trainingDayCount)")
                LabeledContent("Weekly sets", value: "\(plan.days.reduce(0) { $0 + $1.totalSets })")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .gtScreenBackground()
        .navigationTitle("Routine settings")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { try? context.save() }
    }
}
