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
        ModelContext(try container())
    }
}
