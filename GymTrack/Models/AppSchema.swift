import SwiftData

/// Every model the store holds, in one list.
///
/// The app opens its store from this list and the tests build their in-memory
/// containers from it, so a model added to one cannot be missing from the
/// other. A test container short of a model fails only when a relationship
/// reaches it, far from the test that forgot it.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        Plan.self, PlanDay.self, PlanItem.self,
        WorkoutSession.self, SetLog.self, ExerciseNote.self,
        CustomExerciseRecord.self, BodyMetric.self, BodyMeasurement.self,
        ExerciseLoadPreference.self, HiddenExerciseRecord.self,
    ]
}
