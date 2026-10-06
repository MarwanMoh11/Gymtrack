import Foundation
import SwiftData
@testable import GymTrack

/// A fresh in-memory store per test, built from the same model list the app
/// opens, so a test can never read what another one saved.
@MainActor
enum TestStore {
    static func container() throws -> ModelContainer {
        try ModelContainer(
            for: Schema(AppSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    static func context() throws -> ModelContext {
        let container = try container()
        retained.append(container)
        return ModelContext(container)
    }

    /// A context does not keep its container alive, and SwiftData traps on
    /// some operations (a rollback after a restore's wipe, for one) once the
    /// container has gone. In-memory stores are small, so each test's is
    /// simply kept until the process ends.
    private static var retained: [ModelContainer] = []
}
