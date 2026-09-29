import Foundation
import SwiftData

/// Only the app services that backup needs outside the iOS process.
final class AppSettings {
    static let shared = AppSettings()
    var weightUnit: WeightUnit = .kg
    var userName = ""
    var defaultRestSeconds = 90
    var trackRPE = true
}

enum LoadNudgeOutcome: String {
    case taken
    case declined
}

/// Records every deletion that reaches it, so a test can prove a path that
/// takes no injected closure never asked Health to delete anything.
@MainActor
final class HealthKitService {
    static let shared = HealthKitService()
    var deletedIDs: [UUID] = []
    func deleteWorkout(id: UUID) async -> Bool {
        deletedIDs.append(id)
        return true
    }
    func deleteWorkouts(ids: [UUID]) async -> [UUID] {
        deletedIDs.append(contentsOf: ids)
        return []
    }
}

extension ModelContext {
    func refreshCustomExercises() {
        ExerciseCatalog.shared.setCustom(
            ((try? fetch(FetchDescriptor<CustomExerciseRecord>())) ?? []).map(\.asCatalogExercise)
        )
    }
}
