import SwiftUI
import SwiftData

/// Everything about Apple Health and the Apple Watch in one place.
///
/// The three Health switches are deliberately separate: writing workouts,
/// reading vitals back and syncing body weight are different asks, and someone
/// happy to have their sessions in Fitness may not want GymTrack near their
/// weigh-ins.
struct HealthWatchSettingsView: View {
    @Environment(\.modelContext) private var context

    @State private var settings = AppSettings.shared
    @State private var health = HealthKitService.shared
    @State private var watch = WatchBridge.shared
    @State private var isRequesting = false
    @State private var importedCount: Int?
    @State private var isImporting = false

    var body: some View {
        Form {
            healthSection
            if health.isAvailable { dataSection }
            watchSection
            howSection
        }
        .scrollContentBackground(.hidden)
        .gtScreenBackground()
        .navigationTitle("Health & Watch")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Health

    private var healthSection: some View {
        Section {
            if health.isAvailable {
                HStack(spacing: 12) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Theme.negative.gradient, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(health.hasRequestedAuthorization ? "Connected to Health" : "Not connected")
                            .font(Theme.rounded(15, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(health.hasRequestedAuthorization
                             ? "Change what GymTrack can see in Health → Sharing → Apps."
                             : "GymTrack asks for heart rate, energy, body weight and workouts.")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 4)

                Button {
                    connect()
                } label: {
                    HStack {
                        Label(health.hasRequestedAuthorization ? "Review permissions" : "Connect Health",
                              systemImage: "arrow.triangle.2.circlepath")
                        if isRequesting {
                            Spacer()
                            ProgressView().controlSize(.small)
                        }
                    }
                }
                .disabled(isRequesting)
            } else {
                Label("Health isn't available on this device", systemImage: "heart.slash")
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Apple Health")
        } footer: {
            if let message = health.lastErrorMessage {
                Text(message).foregroundStyle(Theme.negative)
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var dataSection: some View {
        Section {
            Toggle("Save workouts to Health", isOn: Binding(
                get: { settings.healthWriteWorkouts },
                set: { settings.healthWriteWorkouts = $0; if $0 { connect() } }
            ))
            .tint(Theme.accent)

            Toggle("Heart rate & energy", isOn: Binding(
                get: { settings.healthReadVitals },
                set: { settings.healthReadVitals = $0; if $0 { connect() } }
            ))
            .tint(Theme.accent)

            Toggle("Sync body weight", isOn: Binding(
                get: { settings.healthBodyWeight },
                set: { settings.healthBodyWeight = $0; if $0 { connect(thenImport: true) } }
            ))
            .tint(Theme.accent)

            if settings.healthBodyWeight {
                Button {
                    importWeights()
                } label: {
                    HStack {
                        Label("Import weigh-ins now", systemImage: "square.and.arrow.down")
                        Spacer()
                        if isImporting {
                            ProgressView().controlSize(.small)
                        } else if let importedCount {
                            Text(importedCount == 0 ? "Up to date" : "+\(importedCount)")
                                .font(Theme.number(13, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .disabled(isImporting)
            }
        } header: {
            Text("What gets shared")
        } footer: {
            Text("A finished session is written as a traditional strength training workout, one activity per exercise, with your sets, reps and volume attached. Heart rate and energy come back from whatever your watch recorded during it.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Watch

    private var watchSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "applewatch")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(watch.isLinked ? .black : Theme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(watch.isLinked ? Theme.accent : Theme.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(watch.isLinked ? "GymTrack is on your watch" : "Watch app not ready")
                        .font(Theme.rounded(15, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(watch.statusDescription)
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.vertical, 4)

            Toggle("Wake the watch when a session starts", isOn: Binding(
                get: { settings.watchAutoLaunch },
                set: { settings.watchAutoLaunch = $0 }
            ))
            .tint(Theme.accent)
            .disabled(!watch.isLinked)
        } header: {
            Text("Apple Watch")
        } footer: {
            Text("Start a workout on either device and it appears on the other. The watch records your heart rate and the energy you burn, and logs sets straight from your wrist.")
        }
        .listRowBackground(Theme.surface)
    }

    private var howSection: some View {
        Section("On the wrist") {
            ForEach(WatchFeature.all) { feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(feature.title)
                            .font(Theme.rounded(14, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(feature.detail)
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(.vertical, 2)
            }
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Actions

    private func connect(thenImport shouldImport: Bool = false) {
        guard health.isAvailable else { return }
        isRequesting = true
        Task {
            await health.requestAuthorization()
            isRequesting = false
            if shouldImport { importWeights() }
        }
    }

    private func importWeights() {
        isImporting = true
        Task {
            let added = await health.importBodyMass(into: context)
            importedCount = added
            isImporting = false
            if added > 0 { Haptics.success() }
        }
    }
}

/// The pitch for the watch app, kept as data so the same lines can be reused.
private struct WatchFeature: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String

    static let all: [WatchFeature] = [
        WatchFeature(symbol: "figure.strengthtraining.traditional",
                     title: "Log without your phone",
                     detail: "Every set, weight and rep, adjusted with the Digital Crown."),
        WatchFeature(symbol: "heart.fill",
                     title: "Heart rate and calories",
                     detail: "A real workout session runs on the watch, so the rings move."),
        WatchFeature(symbol: "timer",
                     title: "Rest on your wrist",
                     detail: "The rest timer taps you when it's time for the next set."),
        WatchFeature(symbol: "arrow.triangle.2.circlepath",
                     title: "Always the same session",
                     detail: "Start on either device, finish on the other — it stays in step."),
    ]
}
