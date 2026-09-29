> Detail file from the 2026-09-28 review. The index, the canonical severities and the duplicate map are in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md). Where this file disagrees with the index, the index wins. Line numbers refer to the working tree on 2026-09-28 (HEAD f5809ff plus the uncommitted GT fix pass).

# Cross-cutting audits, design system and test suite: findings

Files read in full: GymTrack/DesignSystem/Components.swift, GymTrack/DesignSystem/Surfaces.swift,
GymTrackShared/SessionStyle.swift, GymTrackShared/Theme.swift, Tests/ActiveWorkoutStructureStubs.swift,
Tests/ActiveWorkoutStructureTests.swift, Tests/BackupServiceStubs.swift, Tests/BackupServiceTests.swift,
Tests/SetEffortDetectionTests.swift, Tests/TrainingStatsCalendarTests.swift,
Tests/TrainingStatsHistoryRecordTests.swift, Tests/TrainingStatsSettingsStub.swift,
Tests/WatchCommandReliabilityTests.swift, Tests/WatchSetRatingTests.swift, all seven scripts/test-*.sh.
Excerpts only (grep, then sed -n) elsewhere.

## Prior findings re-check

Re-checked for regression-test coverage, which is this area. The fixes themselves belong to the domain reviewers.

- GT-001: INCOMPLETE. Only the wire format is tested (`WatchCommandReliabilityTests.swift:31-40`). No test drives `WatchCommandCenter.applyHeadless` `.discardSession` or `.finishSession` with a stale ID while a newer session is active (`WatchCommandCenter.swift:185-218`), and `RootView.handleWatchCommand` cannot be tested at all. See XC-04.
- GT-002: OK. `applyWatchFinish` is tested in both arrival orders, and so is a repeated Finish (`WatchCommandReliabilityTests.swift:67-114`).
- GT-003: OK. The test context has autosave off and the app's `mainContext` has it on. That does not matter, because there is no suspension point between `deleteStoredRecords`, `insertArchive` and `save` (`BackupService.swift:533-541`), so autosave cannot commit a half-done restore.
- GT-011: OK. Tested (`ActiveWorkoutStructureTests.swift:44-80`).
- GT-012: INCOMPLETE. The doc says "session factory regression passed", but the only factory test uses a repeated slot, which takes the `isRepeated` branch (`ActiveWorkout.swift:38-39`). The fixed branch, `suggestion.action == .increaseWeight` (`ActiveWorkout.swift:40-41`), has no test in the repo. See XC-06.
- GT-013: OK. Tested: take, re-rate, take again, then undo (`ActiveWorkoutStructureTests.swift:98-109`).
- GT-014: INCOMPLETE. The call sites I checked convert correctly (`TodayView.swift:190,255,531`, `SessionSummaryView.swift:95`, `ExerciseDetailView.swift:316`), but all three `AppSettings` stubs hard-code `.kg`, so no test ever runs in pounds. See XC-08.
- GT-015, GT-018, GT-022: OK. Tested in `TrainingStatsCalendarTests.swift`.
- GT-016, GT-017: OK. Tested in `TrainingStatsHistoryRecordTests.swift`.
- GT-020: OK for backup linkage and erase cleanup (`BackupServiceTests.swift`). An in-flight Health write can still escape the cleanup; see XC-02.

## Findings

### XC-01: Typed stepper entry is unbounded: huge reps or seconds crash the logger, and absurd or non-finite weights are stored as measured
- Severity: P2
- Category: bug
- Confidence: confirmed (path traced; the crash input is unusual, but a fat-fingered weight is common)
- Location: `GymTrack/DesignSystem/Components.swift:300-304` (`StepperField` alert "Set"), `GymTrack/Features/Session/ActiveWorkoutView.swift:1315,1319` (`repsBinding`, `secondsBinding`), `ActiveWorkoutView.swift:1307-1311` (`weightBinding`), `GymTrackShared/LoadScale.swift:100` (`displayCeiling`, used only at `GymTrackWatch/Views/WatchLoggerView.swift:493`)
- What happens: the alert accepts any parsed `Double`: `if let entered = Double(...) { value = max(0, entered) }`. For reps and seconds the binding then runs `set.reps = max(0, Int($0))`. `Int(Double)` traps when the value is outside the `Int` range. For weight there is no ceiling at all. The phone ignores the 500 kg / 1,100 lb `displayCeiling` that the watch's Digital Crown respects. A pasted or hardware-keyboard value like `1e999` parses to `+inf`. `max(0, inf)` keeps it, and the inf is then written to `set.weightKg`.
- Failure scenario: (a) The user types 20 digits into Reps and taps Set. `Int(1e20)` traps, and the app crashes mid-workout. (b) The user means 100 and types 1000 kg. It is stored as a measured set, becomes a PR, and feeds the next suggestion and the AI export. That breaks data rule 1. (c) A weight of `inf`: `BackupService.export` throws, because `JSONEncoder`'s default `nonConformingFloatEncodingStrategy` is `.throw`. `WatchLink`'s `try? JSONEncoder.watchLink.encode(self)` returns `[:]` (`WatchLink.swift:415`), so the watch silently stops receiving mirrors. The widget snapshot is dropped as well (`SharedStore.swift:35`).
- Suggested fix: validate inside `StepperField` before assigning. Reject input unless `entered.isFinite`. Clamp to a `maximum` parameter: `scale.displayCeiling` for weight, and sane caps for reps (for example 1000) and seconds (for example 3600). Let the `LoadScale` initialiser pass the ceiling through. In the bindings, use `Int(exactly:)` or clamp before converting.
- Verify by: a unit test on a pure `StepperField.parse(_:ceiling:)` helper covering "1e999", 20 digits, "1000" with a 500 ceiling, "60,5" and "٦٠٫٥". Also, manually: type 99999999999999999999 into Reps and confirm the app does not crash.

### XC-02: The post-finish Health write keeps a WorkoutSession across 12 s of awaits, so an erase, restore or delete in that window leaves an orphan Health workout or touches a deleted model
- Severity: P2
- Category: bug
- Confidence: likely (the window and the missing guards are traced; the SwiftData outcome on a deleted model, crash or stale read, is not proven)
- Location: `GymTrack/Services/ActiveWorkout.swift:904-925` (`recordToHealth`), `GymTrack/Services/HealthKitService.swift:155-236` (`saveWorkout`), `GymTrack/Services/BackupService.swift:694-713` (`wipe` guards only open sessions), `GymTrack/Features/Session/SessionSummaryView.swift:416-424` (`SessionDetailView` delete)
- What happens: after Finish, `recordToHealth` starts a `Task` that holds `session`. For a watch-driven session it polls `session.healthWorkoutID` for up to 12 s. It then awaits `saveWorkout(for: session)`, which reads and writes the model across roughly five HealthKit awaits, and then awaits `backfillVitals`. Nothing checks `session.isDeleted` or `session.modelContext` after any await. `wipe` and `restore` refuse only when a session has `endedAt == nil`, and this session is already closed.
- Failure scenario: the user finishes a watch-driven workout, opens Settings and taps Erase all data within about 10 s. `wipe` deletes the session and deletes the Health workouts it knows about; the watch's ID has not arrived yet. The task then resumes. If the read does not crash, the phone saves a new Health workout for a session that no longer exists, and no later erase can find it. Meanwhile the watch's own workout ID reaches `RootView.applyLateMetrics`, finds no session, and is orphaned too (`RootView.swift:417-421`). The same happens after deleting the just-finished session from `SessionDetailView`: `healthWorkoutID` is still nil at that moment, so nothing is deleted from Health.
- Suggested fix: after every await in `recordToHealth`, `saveWorkout` and `backfillVitals`, bail out if `session.isDeleted || session.modelContext == nil`. If `saveWorkout` already produced a workout when it bails, enqueue that UUID through the existing `enqueueCleanup` path. Separately, have `wipe`, `restore` and `SessionDetailView` delete wait for, or cancel, an in-flight `recordToHealth` Task: store the Task on `HealthKitService` keyed by session ID. Also record late watch IDs whose session is gone, so they are deleted rather than dropped.
- Verify by: once a Health-writing seam exists (XC-05), a test that finishes, deletes the session while the fake store's `finishWorkout` is suspended, resumes it, and asserts no workout remains in the fake store and nothing traps.

### XC-03: Restore accepts plan values that crash views on every launch
- Severity: P2
- Category: bug
- Confidence: confirmed (code path; needs a hand-edited, foreign or AI-generated archive)
- Location: `GymTrack/Services/BackupService.swift:578` (`PlanDay(... weekday: dayDTO.weekday ...)`, unvalidated), `GymTrack/Models/Entities.swift:76-84` (`weekdaySymbols[weekday - 1]`), called from `GymTrack/Features/Plans/PlansView.swift:165` and `GymTrack/Features/Today/TodayView.swift:566`; `GymTrack/Features/Plans/DayEditorView.swift:241` (`in: item.targetRepsLow...60`)
- What happens: restore copies `weekday`, `targetRepsLow` and the other plan fields straight from JSON. `weekdayName` and `weekdayShortName` index `Calendar.current.weekdaySymbols[weekday - 1]` with no bounds check. The day editor builds `item.targetRepsLow...60`, which traps when the low end is above 60. The editor's own steppers cap low reps at 50, but restore does not.
- Failure scenario: `docs/AI_COACH.md:15,176` plans for approved plan proposals to be imported. An archive that uses 0-based weekdays (0 = Sunday), or has a low rep target of 70, restores cleanly. The Today tab then crashes on render, on every launch, and the store keeps the bad row, so the crash repeats until the app is deleted.
- Suggested fix: validate in `insertArchive`, or reject the file before `deleteStoredRecords`, so a bad file never replaces good data. Clamp or null `weekday` outside 1...7, clamp reps to 1...60 with low <= high, force `targetSets >= 1`, and drop non-finite weights. Also make `weekdayName` defensive: `weekdaySymbols.indices.contains(weekday - 1)`.
- Verify by: a `BackupServiceTests` case that restores an archive with `weekday: 0` and `targetRepsLow: 70`, then asserts the stored values are in range and that `PlanDay.weekdayName` does not trap.

### XC-04: The watch-command routing that GT-001 fixed has no regression test, and the one headless test only checks the no-op path
- Severity: P2
- Category: test-gap
- Confidence: confirmed
- Location: `Tests/ActiveWorkoutStructureTests.swift:131-154`, `GymTrack/Services/WatchCommandCenter.swift:185-218`, `GymTrack/App/RootView.swift` (`handleWatchCommand`)
- What happens: the only test that compiles `WatchCommandCenter` sends `.undoSet` and `.logSet` with no active session and asserts that nothing changed. A handler that ignored every command would pass it. Nothing tests a stale `.discardSession(id: old)` or `.finishSession(batch for old)` arriving while a newer session is active. That is exactly GT-001's failure, and it deletes a live workout. The UI-side decision in `RootView.handleWatchCommand` cannot be reached from any harness.
- Failure scenario: a later edit drops the `session.id == id` guard in `.discardSession`. Every script still passes, and a delayed wrist Discard deletes the next workout.
- Suggested fix: add tests. (1) With finished session A and active session B, `handle(.discardSession(id: A.id))` leaves B, and `handle(.finishSession(batchFor: A))` leaves B active. (2) A positive path: `handle(.logSet(id: B.set))` sets `isCompleted`, the weight, the reps and `completedAt`. (3) `.finish(nil)` and `.discard` change nothing. Extract the phone-side routing into a pure function, for example `WatchCommandRouting.decide(command, activeSessionID:) -> Action`, and test its table.
- Verify by: temporarily delete the ID guard at `WatchCommandCenter.swift:213`, and the new test must fail.

### XC-05: HealthKit duplicate prevention and cleanup have no test seam and no test
- Severity: P2
- Category: test-gap
- Confidence: confirmed
- Location: `GymTrack/Services/HealthKitService.swift:155-240` (`saveWorkout`, the `enqueueCleanup` race branch), `:268-295` (`retryPendingWorkoutCleanup`), `ActiveWorkout.swift:913-917` (the 12 s wait)
- What happens: GT-007, GT-008 and GT-020 all come down to "one Health workout per session". The logic that enforces it is the watch-ID-arrives-mid-save branch, the persisted pending-cleanup queue and the retry loop. It talks to `HKHealthStore` directly and is stubbed out of every test (`ActiveWorkoutStructureStubs.swift:55-61`, `BackupServiceStubs.swift:17-21`). Its correctness is currently asserted only by reading it.
- Failure scenario: a refactor reorders `session.healthWorkoutID = workout?.uuid` ahead of the watch-ID check. Every script passes, and Health gets two workouts for every watch-driven session.
- Suggested fix: put a small protocol, for example `HealthWorkoutStore { save(session) async throws -> UUID; delete(UUID) async -> Bool }`, behind `HealthKitService`, and test with a fake. (a) The watch ID is set while the fake save is suspended: the phone copy is queued for deletion and the link stays on the watch ID. (b) A delete that fails persists the pending entry, and a retry succeeds. (c) `saveWorkout` on a session that already has `healthWorkoutID` is a no-op. (d) The deleted-session race in XC-02.
- Verify by: the four cases above in a new `scripts/test-health-linkage.sh` (or an XCTest target, see XC-09).

### XC-06: GT-012's rep reset after a weight increase is untested; the factory test only covers repeated slots
- Severity: P2
- Category: test-gap
- Confidence: confirmed
- Location: `GymTrack/Services/ActiveWorkout.swift:29-42` (`SessionFactory.build`), `Tests/ActiveWorkoutStructureTests.swift:29-51`
- What happens: both `repeat-test` items in the fixture are repeated slots, so the history (60 kg x 12, top of range) is deliberately ignored. The assertions `[30,30,45,45,45]` and `[6,6,10,10,10]` prove that the repeated-slot branch ignores history. The single-slot branches, `.increaseWeight` giving `suggestion.reps` and otherwise `previous?.reps`, and the `loadScale.snap` of the suggestion, never run in any test.
- Failure scenario: the fix is reverted or broken. The new session opens at a raised weight with last time's 12 reps, which is GT-012 exactly, and every script still passes.
- Suggested fix: add a single-slot item (range 8-12, 3 sets) with history of 3 x 12 at 60 kg. Assert every built set has `weightKg == suggestion.weightKg`, snapped to the ladder, and `reps == 8`. Add a hold case, history 3 x 10, and assert reps are carried from `last[setIndex]`.
- Verify by: the new assertions fail if lines 40-41 are removed.

### XC-07: Streak and sessions-this-week count empty finished sessions, while the calendar and the finished-today check exclude them
- Severity: P3
- Category: bug
- Confidence: confirmed
- Location: `GymTrack/Services/TrainingStats.swift:18-19` (`streak` keys days on `!isActive` only) versus `:71-73` (`trainedDays` requires `!completedSets.isEmpty`) and `:48-51` (`finishedToday`); callers `TodayView.swift:23`, `WidgetPublisher.swift:57`, `WatchBridge.swift:262-263` (`sessionsThisWeek` counts `finished` unfiltered)
- What happens: GT-018 taught `trainedDays` that an empty session is not training, but `streak` and the watch's `sessionsThisWeek` were not updated. Finish is offered with nothing logged: `SessionDock.swift:49` and `ActiveWorkout.finish()` keep an empty session with `endedAt` set.
- Failure scenario: the user starts a session, logs nothing and taps Finish from the dock. Today, the widget and the watch show the streak extended and "1 this week", while the consistency calendar shows the day as rest. The day was inferred, not trained, which breaks data rule 1.
- Suggested fix: make `streak` use `trainedDays(in:)`, and filter `sessionsThisWeek` with `!completedSets.isEmpty`. Better still, treat Finish with zero completed sets as Discard in `ActiveWorkout.finish()`, so the empty session is never stored or exported.
- Verify by: extend `TrainingStatsCalendarTests`. With `emptyYesterday` plus `currentDay`, assert `streak(from:).current == 1`.

### XC-08: No test ever runs in pounds; every AppSettings stub hard-codes kilograms
- Severity: P3
- Category: test-gap
- Confidence: confirmed
- Location: `Tests/ActiveWorkoutStructureStubs.swift:16`, `Tests/BackupServiceStubs.swift:7`, `Tests/TrainingStatsSettingsStub.swift:6`; `GymTrackShared/Units.swift:17-18`, `GymTrackShared/LoadScale.swift:69-84`
- What happens: GT-014 was a kg-with-lb-label bug, and its status is "UI verification pending". Conversion and ladder stepping in pounds (`step(kg:by:)` goes kg to display, steps, then back to kg, with a 0.001 epsilon) are never exercised, so a drift that sticks a stepper or shows 134.9 lb would pass.
- Suggested fix: make the stub's `weightUnit` settable and add an lb pass. For kg on every rung of 5 lb and 2.5 lb ladders from 0 to 400 lb, assert that `step(kg:+1)` then `step(kg:-1)` round-trips within 1e-9. Assert that `text(display(kg))` never prints a trailing .9 or .1 for an on-ladder weight, and that the volume strings behind `AppSettings.weight(_:)` equal `kg * 2.20462262`.
- Verify by: running the new pass under `weightUnit = .lb`.

### XC-09: The test suite is not run by anything, runs on the Mac's SwiftData instead of iOS 17's, and its stubs have already drifted from the app
- Severity: P3
- Category: code-health
- Confidence: confirmed
- Location: `scripts/test-*.sh` (7 scripts), `Tests/*Stubs.swift`, `GymTrack.xcodeproj/project.pbxproj` (no test target)
- What happens:
  1. No runner, no CI, and no mention in CLAUDE.md, AGENTS.md or README. The only record of a run is the coordinator's log.
  2. The scripts compile the app sources for macOS with `xcrun swiftc`, so SwiftData behaves like the host Mac's version, not like the iOS 17.0 minimum. iOS 17's rollback, cascade and relationship behaviour differs and is never exercised.
  3. Source lists are hand-maintained per script.
  4. The stubs diverge. `AppSettings` in `ActiveWorkoutStructureStubs.swift:17-20` has `restTimerAutoStart = false` and `watchAutoLaunch = false`, while the app registers both as `true` (`AppSettings.swift:104,111`), so tests run a configuration no user has. The real `RestTimer` is not `@MainActor` but the stub is. There are three separate `AppSettings` stubs and two copies of `LoadNudgeOutcome`. `WatchSessionRecovery.discardUntouchedOverlaps` is stubbed to identity (`ActiveWorkoutStructureStubs.swift:94-98`), so the data-deleting pass that `WatchCommandCenter.allSessions` runs before every headless command is never executed. `WorkoutSession.writeNote`, `dropNote` and `pruneEmptyNotes` are stubbed as no-ops only because the model extension lives in `Features/Session/SessionNotes.swift`.
  5. The scripts are otherwise hermetic: in-memory stores, fixed dates except the calendar test's `.now`, output confined to `build/`.
- Failure scenario: a change breaks `discardUntouchedOverlaps` so it deletes a legitimate new session. This can happen if its overlap test meets a watch clock running ahead of the phone. No script can see it, and nobody runs the scripts anyway.
- Suggested fix: add `scripts/test-all.sh` now and reference it in CLAUDE.md's Building section. Then add a `GymTrackTests` target, unit tests hosted by the app or model-only, run with `xcodebuild test` on an iOS 17.x simulator runtime. `@testable import` removes the stubs and source lists, and SwiftData runs at the minimum OS. What it would catch that the scripts cannot: iOS 17 SwiftData semantics, stub drift, `WatchSessionRecovery`, `SessionNotes`, and anything behind `#if os(iOS)`. Move `SessionNotes.swift`'s model extension into `Models/`. Add a direct test for `discardUntouchedOverlaps`: an active planned session whose `startedAt` falls a few seconds inside a finished session's interval must survive when it was presented on the phone.
- Verify by: `scripts/test-all.sh` exits 0, and a deliberately broken stub default is caught once the XCTest target exists.

### XC-10: The "undo leaves no trace" rule has no field-exhaustive test, and export-import has no round-trip test
- Severity: P3
- Category: test-gap
- Confidence: confirmed
- Location: `GymTrack/Models/Entities.swift:789-820` (`SetLog.unlog`), `GymTrack/Services/BackupService.swift` (DTOs)
- What happens: `unlog()` clears each logged-time field by hand. A new field such as a future effort metric will not be cleared unless someone remembers to add it. Likewise, a new model field can be exported and not imported, or the reverse, without any test noticing. The backup test checks only titles, health IDs and settings.
- Suggested fix: (a) Log a set with every optional populated (rpe, startedAt, heart-rate window, detected window, load nudge), `unlog()` it, then encode its backup DTO. Assert it equals the DTO of a never-logged twin with the same identity fields. The export becomes the oracle for "no trace", and it also proves absent keys rather than nulls. (b) Export, restore into a fresh container, export again, and assert the two JSON documents are equal with sorted keys.
- Verify by: both tests fail if any line of `unlog()` is removed, or if a DTO field is dropped on one side.

### XC-11: Weight and rep entry silently discards digits typed on a non-Latin number keypad
- Severity: P3
- Category: bug
- Confidence: likely (depends on the device using Arabic-Indic or other native digits)
- Location: `GymTrack/DesignSystem/Components.swift:298-304`
- What happens: `Double(draft.replacingOccurrences(of: ",", with: "."))` handles a comma decimal separator but only ASCII digits. With Arabic (for example ar_EG) or another locale using native digits, the `.decimalPad` offers "٦٠٫٥". `Double(...)` returns nil, and Set does nothing: no error, no change.
- Failure scenario: a user whose phone uses Arabic numerals taps the weight, types 60.5 on the pad and taps Set. The old value stays, and they may log the wrong weight.
- Suggested fix: parse with a `NumberFormatter` (`.decimal`, `locale = .current`, `isLenient = true`), fall back to the current POSIX parse, and apply the XC-01 finite and ceiling checks. Formatting the prefill with the same formatter keeps the round trip consistent.
- Verify by: a unit test on the extracted parser with "٦٠٫٥", "60,5", "60.5" and "1٬000" (the Arabic thousands separator).

### XC-12: Unbounded session fetches: an inventory, and which ones grow with history
- Severity: P3
- Category: performance
- Confidence: confirmed (the cost is modest at realistic sizes, a few hundred sessions a year)
- Location and scaling:
  - `RootView.swift:13` `@Query sessions` (all, unsorted). Feeds `watchIdle`, which is computed on every RootView body pass for `.onChange(of: watchIdle)` (`RootView.swift:66,290-292`). That pass runs `TrainingStats.streak` (O(sessions), with a sort) and plan lookups, as well as `publishWidgets` and history for every `ActiveWorkout`. Grows with sessions.
  - `TodayView.swift:10` all sessions sorted; `streak` is recomputed per render (`TodayView.swift:23`). Grows with sessions.
  - `ExerciseDetailView.swift:10` all sessions for one exercise's screen; `history(for:)` walks every set. Grows with sets.
  - `SessionSummaryView.swift:9` and `ProgressDashboardView.swift:6` all sessions. The records and heat map walk every set, which is intended but grows with sets.
  - `WatchCommandCenter.swift:340-356` fetches every session and runs `discardUntouchedOverlaps` for each headless command, including every wrist Log set while the phone is asleep. Grows with sessions.
  - `HealthKitService.swift:278` fetches every session to find one by `id`. `RootView.swift:399` fetches all on a watch start.
- Suggested fix: use `FetchDescriptor(predicate: #Predicate { $0.id == id })` for the ID lookups in `HealthKitService` and `WatchCommandCenter.session(id:)`. Use `#Predicate { $0.endedAt == nil }` for `activeSession(in:)`, and run `discardUntouchedOverlaps` once at launch rather than per command. Cache `watchIdle` in `@State`, recomputed on `sessions.count` and day change, rather than computing it in `body`.
- Verify by: seed about 2,000 sessions (a 10x `-GTSeedSampleData`) and profile a wrist Log set with the phone in the background, and a Today tab render.

### XC-13: Design-system type ignores Dynamic Type, and tertiary text is below AA contrast
- Severity: P3
- Category: missing-feature
- Confidence: confirmed
- Location: `GymTrackShared/Theme.swift:37-50` (every token is `.system(size:)`), `Theme.swift:22` (`textTertiary = white.opacity(0.38)`), used for `SectionHeader`, `StatTile` labels, `StepperField` titles and units (`Components.swift:19,127,258,319`)
- What happens: fixed point sizes never scale with the user's text-size setting. White at 38% on `Theme.surface` works out to about 3.6:1 contrast, under the 4.5:1 AA threshold, and it is used for 8-11 pt captions. In a dim gym, at arm's length, the unit captions and field titles are the hardest text in the logger to read.
- Suggested fix: build the `Theme` fonts with `Font.custom`-style relative sizing (`.system(.body, design: .rounded)` plus weight, or `@ScaledMetric` for numerals with a cap), and raise `textTertiary` to about 0.5 opacity for text. Keep 0.38 for non-text strokes.
- Verify by: Accessibility Inspector contrast audit, and the logger at the largest non-accessibility Dynamic Type size.

### XC-14: Swift 6 readiness: delegate hops rely on unstructured-Task ordering, and two singletons hide mutable state behind @unchecked Sendable
- Severity: P3
- Category: code-health
- Confidence: speculative (ordering on iOS 17 and watchOS 10 runtimes is not verified)
- Location: `GymTrack/Services/WatchBridge.swift:200-222`, `GymTrackWatch/WatchConnector.swift:387-397` (`Task { @MainActor in self.handle(...) }` per callback); `GymTrack/Models/CatalogExercise.swift:86`, `GymTrack/Services/LoadScaleBook.swift:20` (`@unchecked Sendable` with unlocked `var`s); `GymTrack/Services/RestTimer.swift:8` (`@Observable` but not `@MainActor`); `project.pbxproj` `SWIFT_VERSION = 5.0` with no `SWIFT_STRICT_CONCURRENCY`
- What happens: each WCSession callback spawns its own Task to reach the main actor. FIFO order between those Tasks is guaranteed only when the runtime enqueues them directly on the main executor, and older concurrency runtimes first scheduled them on the global executor. Order matters for a wrist Log set followed quickly by Undo for the same set. `undoSet` carries no timestamp, so if the two run swapped, the undo is a no-op and the log sticks, which breaks data rule 2.
- Failure scenario (speculative): the lifter mis-taps Log set on the wrist and taps Undo within a second while the phone is reachable. On a runtime that reorders, the set stays logged on the phone and the mirror re-logs it on the wrist.
- Suggested fix: route delegate payloads through `DispatchQueue.main.async { MainActor.assumeIsolated { ... } }` (FIFO guaranteed) or a single `AsyncStream` consumer. Mark `RestTimer`, `AppSettings`, `ExerciseCatalog` and `LoadScaleBook` `@MainActor`. Then turn on `SWIFT_STRICT_CONCURRENCY = complete` in Debug to surface the rest.
- Verify by: a test that feeds 1,000 alternating log and undo payloads for one set through the nonisolated entry point and asserts the final state equals applying them sequentially.

## Sweep notes (no finding)

- Availability: clean. The deployment targets are iOS 17.0 and watchOS 10.0 (`project.pbxproj:384,435,505,531,571,599`), and the compiler rejects unguarded newer APIs, so the three successful builds prove none exist. Every hit is at or below the target: `onGeometryChange` (back-deployed to 16), `contentMargins`, `containerBackground` (watchOS 10), `buttonRepeatBehavior`, `presentationBackground`, `defaultScrollAnchor`, and the two-argument `onChange`. The watch build's "Metadata extraction skipped" warning is expected, because the intents are `#if os(iOS)`.
- Crash sites: no `try!`, `as!`, `fatalError` or `precondition` in app code. Every `Calendar.date(byAdding: .day)!` works from a start of day, and none is reachable as nil. `Dictionary(uniqueKeysWithValues:)` in `ProgressDashboardView.swift:353-363` uses distinct keys. The reachable traps are covered in XC-01 and XC-03.
- Leaks: no `NotificationCenter` observers, `Timer.publish` or Combine sinks. Both rest timers invalidate, capture `[weak self]` and run on `.common` mode. `ActiveWorkout` clears `restTimer.onChange` on finish and discard.
- Colours: every literal `Color(...)` outside `Theme` is intentional, and the app is forced dark (`Info.plist UIUserInterfaceStyle = Dark`, `GymTrackApp.swift:153`). The widgets draw on their own `containerBackground`. Nothing breaks in light mode.
- Date arithmetic: no fixed `86400`-style day arithmetic anywhere. Display dates use `.formatted` and follow the locale. Number display uses `String(format:)`, which is POSIX: a period, not the user's decimal comma. That is cosmetic only, since input parsing accepts both.
