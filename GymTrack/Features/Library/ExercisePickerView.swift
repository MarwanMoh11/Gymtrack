import SwiftUI

/// Modal search used when adding an exercise to a plan day or a live session.
struct ExercisePickerView: View {
    let onPick: (CatalogExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var muscle: Muscle?

    private var results: [CatalogExercise] {
        Array(ExerciseCatalog.shared.search(query, muscle: muscle).prefix(200))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                muscleFilter
                List(results) { exercise in
                    Button {
                        onPick(exercise)
                        Haptics.log()
                    } label: {
                        HStack {
                            ExerciseRow(exercise: exercise)
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 19))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .listRowBackground(Theme.surface)
                    .listRowSeparatorTint(Theme.hairline)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .gtScreenBackground()
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Theme.background)
    }

    private var muscleFilter: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                chip("All", active: muscle == nil) { muscle = nil }
                ForEach(Muscle.allCases) { option in
                    chip(option.name, active: muscle == option) { muscle = option }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(_ text: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            Haptics.tick()
        } label: {
            Text(text)
                .font(Theme.rounded(13, weight: .semibold))
                .foregroundStyle(active ? .black : Theme.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? Theme.accent : Theme.surface, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}
