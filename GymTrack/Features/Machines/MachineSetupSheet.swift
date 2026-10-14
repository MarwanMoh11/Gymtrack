import SwiftData
import SwiftUI

/// The machine an exercise is done on and how the lifter sets it up.
///
/// Every tap saves: there is no Save button to forget mid-set, and nothing to
/// dismiss. Tapping the position that is already set takes it back, leaving
/// that adjustment unset rather than at some default, because a seat height
/// the app made up would read as one the lifter chose.
struct MachineSetupSheet: View {
    let catalogID: String
    let exerciseName: String
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var records: [MachineSetupRecord]
    @State private var focus: String?
    @State private var choosing = false

    private var setup: MachineSetupRecord? { MachineSetups.setup(for: catalogID, in: records) }

    var body: some View {
        NavigationStack {
            Group {
                if let setup, let rig = setup.rig {
                    setupScreen(rig: rig, settings: setup.settings.valid(for: rig))
                } else {
                    MachinePickerList(catalogID: catalogID, exerciseName: exerciseName, current: nil, records: records) { id in
                        guard let id else { return }
                        MachineSetups.choose(id, for: catalogID, context: context)
                        Haptics.success()
                    }
                }
            }
            .gtScreenBackground()
            .navigationTitle(exerciseName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(Theme.rounded(15, weight: .bold))
                        .accessibilityIdentifier("machine.done")
                }
            }
            .navigationDestination(isPresented: $choosing) {
                MachinePickerList(catalogID: catalogID, exerciseName: exerciseName,
                                  current: setup?.machineID, records: records) { id in
                    if let id {
                        MachineSetups.choose(id, for: catalogID, context: context)
                    } else {
                        MachineSetups.clear(catalogID, context: context)
                    }
                    focus = nil
                    choosing = false
                    Haptics.success()
                }
                .gtScreenBackground()
                .navigationTitle("Machine")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .gtSheetBackground()
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func setupScreen(rig: MachineRig, settings: MachineSettings) -> some View {
        ScrollView {
            VStack(spacing: 14) {
                modelCard(rig: rig, settings: settings)
                ForEach(sections(of: rig), id: \.name) { section in
                    VStack(alignment: .leading, spacing: 14) {
                        SectionHeader(section.name)
                        ForEach(section.adjustments) { adjustment in
                            AdjustmentRow(adjustment: adjustment, value: settings[adjustment.id]) { value in
                                focus = adjustment.id
                                MachineSetups.set(adjustment.id, to: value, for: catalogID, context: context)
                                Haptics.tick()
                            }
                        }
                    }
                    .gtCard()
                }
                Text("Saved as you tap. Tap a set position again to clear it.")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private func modelCard(rig: MachineRig, settings: MachineSettings) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            MachineModelView(rig: rig, settings: settings, focus: focus)
                .frame(height: 300)
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(rig.brand.uppercased())
                        .font(Theme.eyebrow)
                        .tracking(1.4)
                        .foregroundStyle(Theme.textTertiary)
                    Text(rig.model)
                        .font(Theme.rounded(17, weight: .bold))
                        .foregroundStyle(Theme.ink)
                    Text([rig.name, rig.code].compactMap { $0 }.joined(separator: " · "))
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                Button("Change") { choosing = true }
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("machine.change")
            }
            .padding(16)
        }
        .gtCard(padding: 0)
    }

    private struct Section { let name: String; let adjustments: [RigAdjustment] }

    private func sections(of rig: MachineRig) -> [Section] {
        guard let stations = rig.stations else { return [Section(name: "Your setup", adjustments: rig.adjustments)] }
        return stations.map { station in
            Section(name: station.name, adjustments: station.adjustments.compactMap { rig.adjustment($0) })
        }
    }
}

/// One adjustment: a row of numbered holes, or a choice of options.
private struct AdjustmentRow: View {
    let adjustment: RigAdjustment
    let value: Int?
    let choose: (Int?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(adjustment.name)
                    .font(Theme.rounded(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(valueText)
                    .font(value == nil ? Theme.rounded(12, weight: .medium) : Theme.number(15, weight: .bold))
                    .foregroundStyle(value == nil ? AnyShapeStyle(Theme.textTertiary) : AnyShapeStyle(Theme.accent))
                    .accessibilityIdentifier("machine.value.\(adjustment.id)")
            }
            if let options = adjustment.options {
                HStack(spacing: 8) {
                    ForEach(options.indices, id: \.self) { index in
                        Button { choose(value == index ? nil : index) } label: {
                            Pill(text: options[index], color: value == index ? Theme.accent : Theme.textSecondary,
                                 filled: value == index)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("machine.option.\(adjustment.id).\(index)")
                        .accessibilityAddTraits(value == index ? .isSelected : [])
                    }
                }
            } else {
                pins
            }
        }
    }

    private var valueText: String {
        guard let value else { return "Not set" }
        if adjustment.options != nil { return adjustment.display(value) }
        return "\(value) of \(adjustment.range.upperBound)"
    }

    private var pins: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(Array(adjustment.range), id: \.self) { n in
                        Button { choose(value == n ? nil : n) } label: { pin(n) }
                            .buttonStyle(.plain)
                            .id(n)
                            .accessibilityLabel("\(adjustment.name) \(n)")
                            .accessibilityAddTraits(value == n ? .isSelected : [])
                            .accessibilityIdentifier("machine.pin.\(adjustment.id).\(n)")
                    }
                }
                .padding(.vertical, 1)
            }
            .scrollIndicators(.hidden)
            .onAppear { if let value { proxy.scrollTo(value, anchor: .center) } }
        }
    }

    private func pin(_ n: Int) -> some View {
        let on = value == n
        return Text("\(n)")
            .font(Theme.number(14, weight: on ? .bold : .semibold))
            .foregroundStyle(on ? AnyShapeStyle(Color.black) : AnyShapeStyle(Theme.textSecondary))
            .frame(width: 38, height: 38)
            .background {
                Circle().fill(on ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.well))
            }
            .overlay { if !on { Circle().strokeBorder(Theme.hairline, lineWidth: 1) } }
    }
}

/// Every machine the app can draw, with the ones built for this exercise
/// first and the ones this lifter already uses next.
struct MachinePickerList: View {
    let catalogID: String
    let exerciseName: String
    let current: String?
    let records: [MachineSetupRecord]
    let pick: (String?) -> Void

    private var sections: [(title: String, rigs: [MachineRig])] {
        let suited = MachineCatalog.suited(to: catalogID)
        let used = MachineSetups.usedMachineIDs(in: records).compactMap(MachineCatalog.rig)
            .filter { !suited.contains($0) }
        let rest = MachineCatalog.all.filter { !suited.contains($0) && !used.contains($0) }
        return [("Built for \(exerciseName)", suited), ("At your gym", used), ("Other machines", rest)]
            .filter { !$0.rigs.isEmpty }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(sections, id: \.title) { section in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionHeader(section.title)
                        ForEach(section.rigs) { rig in row(rig) }
                    }
                }
                if current != nil {
                    Button("No machine") { pick(nil) }
                        .font(Theme.rounded(13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("machine.none")
                }
            }
            .padding(16)
        }
        .scrollIndicators(.hidden)
    }

    private func row(_ rig: MachineRig) -> some View {
        Button { pick(rig.id) } label: {
            HStack(spacing: 12) {
                MachineThumbnail(rig: rig, size: 64)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rig.brand.uppercased())
                        .font(Theme.eyebrow)
                        .tracking(1.2)
                        .foregroundStyle(Theme.textTertiary)
                    Text(rig.model)
                        .font(Theme.rounded(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.leading)
                    Text(rig.name)
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 4)
                if rig.id == current {
                    Image(systemName: "checkmark")
                        .gtIcon(size: 15, weight: .bold, relativeTo: .subheadline)
                        .foregroundStyle(Theme.accent)
                }
            }
            .gtCard(padding: 10, radius: Theme.cornerRadiusSmall + 4, selected: rig.id == current)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("machine.pick.\(rig.id)")
    }
}

/// The exercise's machine and setup at a glance, inside the card that already
/// holds the exercise. Shows nothing at all until a machine is chosen.
///
/// The card owning it presents the sheet, not the strip: the strip disappears
/// when "No machine" is chosen, and a sheet hung on it would vanish too.
struct MachineSetupStrip: View {
    let catalogID: String
    let open: () -> Void
    @Query private var records: [MachineSetupRecord]

    var body: some View {
        if let setup = MachineSetups.setup(for: catalogID, in: records), let rig = setup.rig {
            let summary = setup.settings.valid(for: rig).summary(for: rig)
            Button(action: open) {
                HStack(spacing: 10) {
                    MachineThumbnail(rig: rig, size: 38)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(rig.brand) · \(rig.model)")
                            .font(Theme.rounded(11, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                        Text(summary.isEmpty ? "Set your seat and pins" : summary)
                            .font(Theme.rounded(13, weight: .semibold))
                            .foregroundStyle(summary.isEmpty ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.textPrimary))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 4)
                    DisclosureChevron()
                }
                .gtWell(vertical: 6, horizontal: 8)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("machine.strip")
        }
    }
}

/// The way in for an exercise with no machine chosen yet: one icon in a header
/// that already has room for it, offered only where a machine is used.
struct MachineSetupButton: View {
    let catalogID: String
    let exerciseName: String
    let open: () -> Void
    @Query private var records: [MachineSetupRecord]

    var body: some View {
        if MachineSetups.setup(for: catalogID, in: records) == nil {
            Button(action: open) {
                Image(systemName: "slider.horizontal.3")
                    .gtIcon(size: 15, relativeTo: .subheadline)
                    .foregroundStyle(Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Machine for \(exerciseName)")
            .accessibilityHint("Optional")
            .accessibilityIdentifier("machine.open")
        }
    }
}

/// The exercise's machine on its library page, for setting it up away from a
/// workout. Shown only for exercises done on a machine.
struct MachineCard: View {
    let exercise: CatalogExercise
    @Query private var records: [MachineSetupRecord]
    @State private var open = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Machine")
            if MachineSetups.setup(for: exercise.id, in: records)?.rig != nil {
                MachineSetupStrip(catalogID: exercise.id) { open = true }
            } else {
                Button("Choose the machine you use") { open = true }
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("machine.choose")
            }
        }
        .gtCard()
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("machine.card")
        .sheet(isPresented: $open) { MachineSetupSheet(catalogID: exercise.id, exerciseName: exercise.name) }
    }
}
