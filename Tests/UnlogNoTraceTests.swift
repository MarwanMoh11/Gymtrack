import Foundation
import SwiftData

/// Run with scripts/test-unlog-no-trace.sh; no simulator is needed.
///
/// XC-10 / data rule 2: anything undone leaves no trace. The existing undo
/// tests each look at the fields their fix touched. This one lists every stored
/// property of `SetLog` and `WorkoutSession` and says, for each, what logging a
/// set does to it. The list is checked against the SwiftData schema, so a field
/// added to either model fails this test until somebody classifies it here,
/// which is the moment to decide whether logging can write it and whether
/// `SetLog.unlog()` has to erase it.
///
/// To add a field: put its name in `setFields` or `sessionFields` under the
/// right kind, add its reader, and, if logging can write it, make
/// `simulateLogging` give it a value that differs from the fresh state.
@main
struct UnlogNoTraceTests {
    @MainActor static var failures = 0

    @MainActor static func check(_ condition: Bool, _ message: String) {
        guard !condition else { return }
        failures += 1
        FileHandle.standardError.write(Data("FAIL: \(message)\n".utf8))
    }

    enum Kind {
        /// Written by logging a set, or by the readings taken through its
        /// window. Must be exactly what it was before once the set is un-logged.
        case loggedByTheSet
        /// Never written by logging. Must be untouched by log plus un-log.
        case identity
        /// The numbers on the row. They are also the prefill for the next
        /// attempt, so un-logging keeps them on purpose (see `SetLog.unlog`).
        case keptOnPurpose
    }

    typealias Reader<Model> = (Model) -> String

    static func text(_ value: Any?) -> String { String(describing: value) }

    /// One entry per stored property of `SetLog`.
    static let setFields: [(name: String, kind: Kind, read: Reader<SetLog>)] = [
        ("isCompleted", .loggedByTheSet, { text($0.isCompleted) }),
        ("completedAt", .loggedByTheSet, { text($0.completedAt) }),
        ("startedAt", .loggedByTheSet, { text($0.startedAt) }),
        ("rpe", .loggedByTheSet, { text($0.rpe) }),
        ("averageHeartRate", .loggedByTheSet, { text($0.averageHeartRate) }),
        ("maxHeartRate", .loggedByTheSet, { text($0.maxHeartRate) }),
        ("heartRateWindowRaw", .loggedByTheSet, { text($0.heartRateWindowRaw) }),
        ("detectedStartedAt", .loggedByTheSet, { text($0.detectedStartedAt) }),
        ("detectedEndedAt", .loggedByTheSet, { text($0.detectedEndedAt) }),
        ("loadNudgeOutcomeRaw", .loggedByTheSet, { text($0.loadNudgeOutcomeRaw) }),
        ("loadNudgeToKg", .loggedByTheSet, { text($0.loadNudgeToKg) }),
        ("id", .identity, { text($0.id) }),
        ("catalogID", .identity, { text($0.catalogID) }),
        ("exerciseName", .identity, { text($0.exerciseName) }),
        ("exerciseOrder", .identity, { text($0.exerciseOrder) }),
        ("setIndex", .identity, { text($0.setIndex) }),
        ("trackingRaw", .identity, { text($0.trackingRaw) }),
        ("targetRepsLow", .identity, { text($0.targetRepsLow) }),
        ("targetRepsHigh", .identity, { text($0.targetRepsHigh) }),
        ("session", .identity, { text($0.session?.id) }),
        // A drop's second row is a continuation before it is logged and after
        // it is taken back; only removing the row un-makes it.
        ("continuesPreviousSet", .identity, { text($0.continuesPreviousSet) }),
        ("weightKg", .keptOnPurpose, { text($0.weightKg) }),
        ("reps", .keptOnPurpose, { text($0.reps) }),
        ("seconds", .keptOnPurpose, { text($0.seconds) }),
    ]

    /// One entry per stored property of `WorkoutSession`. Logging a set writes
    /// none of them, so every one is `.identity`: the session after log plus
    /// undo is the session before. Health metrics arrive at finish, not here.
    static let sessionFields: [(name: String, kind: Kind, read: Reader<WorkoutSession>)] = [
        ("id", .identity, { text($0.id) }),
        ("title", .identity, { text($0.title) }),
        ("startedAt", .identity, { text($0.startedAt) }),
        ("endedAt", .identity, { text($0.endedAt) }),
        ("notes", .identity, { text($0.notes) }),
        ("noteTagsRaw", .identity, { text($0.noteTagsRaw) }),
        ("planDayID", .identity, { text($0.planDayID) }),
        ("planName", .identity, { text($0.planName) }),
        ("preferredExerciseID", .identity, { text($0.preferredExerciseID) }),
        ("healthWorkoutID", .identity, { text($0.healthWorkoutID) }),
        ("averageHeartRate", .identity, { text($0.averageHeartRate) }),
        ("maxHeartRate", .identity, { text($0.maxHeartRate) }),
        ("activeEnergyKcal", .identity, { text($0.activeEnergyKcal) }),
        ("wasWatchDriven", .identity, { text($0.wasWatchDriven) }),
        ("heartRateSourceRaw", .identity, { text($0.heartRateSourceRaw) }),
        ("energySourceRaw", .identity, { text($0.energySourceRaw) }),
        ("heartRateReadings", .identity, { text($0.heartRateReadings) }),
        ("sets", .identity, { text($0.sets.map(\.id).sorted { $0.uuidString < $1.uuidString }) }),
        ("exerciseNotes", .identity, { text($0.exerciseNotes.map(\.id)) }),
    ]

    static func snapshot<M>(_ model: M, _ fields: [(name: String, kind: Kind, read: Reader<M>)]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.read(model)) })
    }

    @MainActor static func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Plan.self, PlanDay.self, PlanItem.self, WorkoutSession.self, SetLog.self,
            ExerciseNote.self, CustomExerciseRecord.self, BodyMetric.self,
            ExerciseLoadPreference.self, HiddenExerciseRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// Two exercises, three sets of the first. The second row of the first is
    /// a continuation so the identity of that flag is exercised on a row that has it.
    @MainActor static func makeSession(_ context: ModelContext) -> (WorkoutSession, [SetLog]) {
        let session = WorkoutSession(title: "Today", startedAt: .now.addingTimeInterval(-3_600))
        context.insert(session)
        var rows: [SetLog] = []
        for index in 0..<3 {
            let row = SetLog(catalogID: "bench-test", exerciseName: "Bench", exerciseOrder: 0,
                             setIndex: index, weightKg: 60, reps: 8,
                             targetRepsLow: 8, targetRepsHigh: 12, tracking: .weightReps)
            row.session = session
            context.insert(row)
            rows.append(row)
        }
        rows[1].continuesPreviousSet = true
        let other = SetLog(catalogID: "row-test", exerciseName: "Row", exerciseOrder: 1, setIndex: 0,
                           weightKg: 50, reps: 10, targetRepsLow: 8, targetRepsHigh: 12, tracking: .weightReps)
        other.session = session
        context.insert(other)
        rows.append(other)
        return (session, rows)
    }

    /// Everything logging a set, and the readings taken through its window, can
    /// write, each to a value different from a fresh row's.
    @MainActor static func simulateLogging(_ set: SetLog, at moment: Date) {
        set.startedAt = moment.addingTimeInterval(-40)
        set.rpe = Double(SetFeel.hard.rawValue)
        set.apply(SetHeartRate(average: 131, peak: 149, source: .measured))
        set.recordDetectedWindow(DetectedSetWindow(start: moment.addingTimeInterval(-38),
                                                   end: moment.addingTimeInterval(-2)))
        set.recordLoadNudge(.taken, toKg: 62.5)
    }

    @MainActor static func main() throws {
        AppSettings.shared.restTimerAutoStart = false
        let container = try makeContainer()
        try schemaIsClassified(container)
        try modelLevel(container)
        try throughTheLogger(container)
        guard failures == 0 else { preconditionFailure("\(failures) unlog check(s) failed") }
        print("Un-logging a set leaves no trace on the set or the session")
    }

    /// A stored property nobody has classified is a field somebody added
    /// without deciding whether logging can write it.
    @MainActor static func schemaIsClassified(_ container: ModelContainer) throws {
        func stored(_ name: String) -> Set<String> {
            Set(container.schema.entities.first { $0.name == name }?.storedProperties.map(\.name) ?? [])
        }
        let known: [(String, Set<String>)] = [
            ("SetLog", Set(setFields.map(\.name))), ("WorkoutSession", Set(sessionFields.map(\.name))),
        ]
        for (entity, classified) in known {
            let actual = stored(entity)
            check(!actual.isEmpty, "The schema has no entity \(entity)")
            check(actual.subtracting(classified).isEmpty,
                  "\(entity) has stored properties this test has not classified: "
                  + "\(actual.subtracting(classified).sorted()). Decide whether logging can write each, "
                  + "and whether unlog() must erase it, then add it to the tables in this file.")
            check(classified.subtracting(actual).isEmpty,
                  "\(entity) is listed here with properties the model no longer has: "
                  + "\(classified.subtracting(actual).sorted())")
        }
    }

    /// `SetLog.unlog()` alone, which is what the wrist's undo runs with no logger.
    @MainActor static func modelLevel(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        let (session, rows) = makeSession(context)
        let set = rows[0]
        let setBefore = snapshot(set, setFields)
        let sessionBefore = snapshot(session, sessionFields)
        let siblingsBefore = rows.dropFirst().map { snapshot($0, setFields) }

        let moment = Date.now
        set.isCompleted = true
        set.completedAt = moment
        simulateLogging(set, at: moment)
        set.weightKg = 62.5
        set.reps = 10

        // The simulation has to reach every field it claims to, or the
        // comparison below is vacuous.
        let logged = snapshot(set, setFields)
        for field in setFields where field.kind == .loggedByTheSet {
            check(logged[field.name] != setBefore[field.name],
                  "The simulated log did not change SetLog.\(field.name), so the test proves nothing about it")
        }

        set.unlog()

        let after = snapshot(set, setFields)
        for field in setFields {
            switch field.kind {
            case .loggedByTheSet, .identity:
                check(after[field.name] == setBefore[field.name],
                      "unlog() left SetLog.\(field.name) as \(after[field.name] ?? "?"); it was \(setBefore[field.name] ?? "?") before the log")
            case .keptOnPurpose:
                check(after[field.name] == logged[field.name],
                      "unlog() must keep the number on the row, SetLog.\(field.name) changed to \(after[field.name] ?? "?")")
            }
        }
        check(snapshot(session, sessionFields) == sessionBefore, "unlog() changed the session")
        check(rows.dropFirst().map { snapshot($0, setFields) } == siblingsBefore, "unlog() changed another set")

        // And no key: an un-logged set is indistinguishable from one never logged.
        check(set.averageHeartRate == nil && set.heartRateWindowRaw == nil && set.detectedWindow == nil
              && set.loadNudgeOutcome == nil && set.rpe == nil && set.startedAt == nil,
              "An un-logged set must hold no optional value at all")

        // Repeating it must be harmless.
        set.unlog()
        check(snapshot(set, setFields) == after, "A second unlog() changed the set")
    }

    /// The phone's path: `complete`, a rating, then `uncomplete`.
    @MainActor static func throughTheLogger(_ container: ModelContainer) throws {
        let context = ModelContext(container)
        let (session, rows) = makeSession(context)
        let workout = ActiveWorkout(session: session, context: context, history: [])
        let set = rows[0]
        let setBefore = snapshot(set, setFields)
        let sessionBefore = snapshot(session, sessionFields)
        let othersBefore = rows.dropFirst().map { snapshot($0, setFields) }

        let moment = Date.now
        set.startedAt = moment.addingTimeInterval(-40)
        workout.complete(set, restSeconds: nil, at: moment)
        workout.rate(set, feel: .hard)
        set.apply(SetHeartRate(average: 131, peak: 149, source: .measured))
        set.recordDetectedWindow(DetectedSetWindow(start: moment.addingTimeInterval(-38),
                                                   end: moment.addingTimeInterval(-2)))
        set.recordLoadNudge(.declined, toKg: 62.5)
        check(set.isCompleted && set.rpe != nil && set.hasHeartRate, "The fixture did not log the set")

        workout.uncomplete(set)

        let after = snapshot(set, setFields)
        for field in setFields where field.kind != .keptOnPurpose {
            check(after[field.name] == setBefore[field.name],
                  "uncomplete() left SetLog.\(field.name) as \(after[field.name] ?? "?"); it was \(setBefore[field.name] ?? "?") before")
        }
        check(snapshot(session, sessionFields) == sessionBefore,
              "Logging and un-logging a set changed the session: "
              + "\(sessionFields.filter { snapshot(session, sessionFields)[$0.name] != sessionBefore[$0.name] }.map(\.name))")
        // Other rows may take the weight forward as a prefill, so only what
        // logging is are compared: none of them may hold a log-written value.
        for (row, before) in zip(rows.dropFirst(), othersBefore) {
            let now = snapshot(row, setFields)
            for field in setFields where field.kind == .loggedByTheSet {
                check(now[field.name] == before[field.name],
                      "Logging and un-logging one set left \(field.name) changed on another row")
            }
        }
        check(workout.lastLoggedSetID != set.id, "The undone set is still the last one logged")
        check(!workout.isPR(set), "The undone set is still marked a record")
    }
}
