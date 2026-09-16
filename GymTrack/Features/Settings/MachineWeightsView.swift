import SwiftUI

/// Everywhere the app has been told a machine is marked differently, in one
/// place — and, above it, what it assumes when it hasn't been told.
///
/// This screen isn't where the feature is meant to be used; the logger is. It's
/// here so the behaviour is inspectable: if the leg press suddenly steps by
/// fifteens, this says why, and undoes it in one tap.
struct MachineWeightsView: View {

    @State private var book = LoadScaleBook.shared
    @State private var settings = AppSettings.shared
    @State private var showingResetConfirm = false

    private var customised: [(exercise: CatalogExercise, scale: LoadScale)] { book.customised }

    var body: some View {
        Form {
            if customised.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Nothing corrected yet")
                            .font(Theme.rounded(15, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Every exercise is following the table below. When a machine disagrees — it's stamped in pounds, or its stack jumps in fifteens — tap the unit under the weight while you're logging it, and it'll be remembered here.")
                            .font(Theme.rounded(13, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 4)
                }
                .listRowBackground(Theme.surface)
            } else {
                Section {
                    ForEach(customised, id: \.exercise.id) { entry in
                        row(for: entry.exercise, scale: entry.scale)
                    }
                    .onDelete { offsets in
                        for index in offsets { book.clear(customised[index].exercise.id) }
                    }
                } header: {
                    Text("Set up by you")
                } footer: {
                    Text("Swipe to put one back on the default. History isn't touched — every lift is stored in kilograms and converted for display.")
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                ForEach(LoadScaleBook.equipmentPriority, id: \.self) { equipment in
                    defaultRow(equipment)
                }
                defaultRow("Everything else", key: "")
            } header: {
                Text("Defaults in \(settings.weightUnit.label.lowercased())")
            } footer: {
                Text("What one tap of + is worth when an exercise hasn't been corrected. These follow the weight unit in Settings.")
            }
            .listRowBackground(Theme.surface)

            if !customised.isEmpty {
                Section {
                    Button("Reset every machine", role: .destructive) {
                        showingResetConfirm = true
                    }
                }
                .listRowBackground(Theme.surface)
            }
        }
        .scrollContentBackground(.hidden)
        .gtScreenBackground()
        .navigationTitle("Machine weights")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Put every exercise back on its default?",
                            isPresented: $showingResetConfirm, titleVisibility: .visible) {
            Button("Reset \(customised.count) exercise\(customised.count == 1 ? "" : "s")", role: .destructive) {
                book.clearAll()
                Haptics.warn()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your logged weights don't change — only how new ones are entered.")
        }
    }

    // MARK: - Rows

    private func row(for exercise: CatalogExercise, scale: LoadScale) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name)
                .font(Theme.rounded(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("\(scale.unit.label) · \(scale.incrementLabel) a step")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(Theme.accent)
        }
        .padding(.vertical, 2)
    }

    private func defaultRow(_ label: String, key: String? = nil) -> some View {
        HStack {
            Text(label)
                .font(Theme.rounded(14, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(LoadScale(unit: settings.weightUnit,
                           increment: LoadScaleBook.increment(for: key ?? label,
                                                              in: settings.weightUnit)).incrementLabel)
                .font(Theme.number(13))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}
