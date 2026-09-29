> Detail file from the 2026-09-28 review. The index, the canonical severities and the duplicate map are in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md). Where this file disagrees with the index, the index wins. Line numbers refer to the working tree on 2026-09-28 (HEAD f5809ff plus the uncommitted GT fix pass).

# Exercise catalog, library, load scales, plans and onboarding: findings

Files read in full: GymTrack/Models/CatalogExercise.swift, GymTrack/Models/ExerciseSearch.swift, GymTrack/Models/Muscle.swift, GymTrack/Models/NoteTag.swift, GymTrack/Services/ExerciseVisibility.swift, GymTrack/Services/LoadScaleBook.swift, GymTrackShared/LoadScale.swift, GymTrack/Services/PlanTemplates.swift, GymTrack/Services/SampleData.swift, GymTrack/Features/Library/ExerciseDetailView.swift, GymTrack/Features/Library/ExerciseEditorView.swift, GymTrack/Features/Library/ExercisePickerView.swift, GymTrack/Features/Library/LibraryView.swift, GymTrack/Features/Library/LoadScaleSheet.swift, GymTrack/Features/Plans/DayEditorView.swift, GymTrack/Features/Plans/PlansView.swift, GymTrack/Features/Onboarding/OnboardingView.swift. I checked GymTrack/Resources/exercises.json with python3. I read excerpts of Entities.swift, TrainingStats.swift, ActiveWorkout.swift, ActiveWorkoutView.swift, WatchCommandCenter.swift, WatchBridge.swift, BackupService.swift, GymTrackApp.swift, RootView.swift, TodayView.swift and MachineWeightsView.swift.

## Prior findings re-check
- GT-016 (catalog side): INCOMPLETE. `ExerciseCatalog.canonicalID(for:)` (`CatalogExercise.swift:120`) and `exercise(id:)` (`CatalogExercise.swift:147-149`) are correct. History, lastPerformance, records and the PR baseline all canonicalise (`TrainingStats.swift:127,185,221,320,342,352`; `ActiveWorkout.swift:352-354`). But stored IDs are never migrated, and other readers still key on the raw ID:
  - `LoadScaleBook` (see LIB-03).
  - `ActiveWorkout.addExercise` and `exerciseGroups` (`ActiveWorkout.swift:782`, `Entities.swift:324`). Adding the survivor to a session whose plan slot holds the losing ID gives a second card for the same movement.
  - The export's catalog (`BackupService.swift:442-456`). It gives the loser and the survivor two entries with the same name and nothing to link them.
- GT-021: OK. `ExerciseEditorView.swift:270-277` renames every `PlanItem` with the ID before `record.apply`, and the change goes through the same save and rollback. Two gaps remain: rows of a session already running keep the old name, and nothing tests the fix (see LIB-10).
- Handoff item "`Plan.trainingDayCount` counts empty days": fixed in commit 2dc40a6 (`Entities.swift:34`). `day(onWeekday:)` also skips empty days (`Entities.swift:42-44`).
- Handoff item "Delete day icon draws green": the code fix is in (`.tint(Theme.negative)` at `PlansView.swift:154`, commit 5771545). Whether a tint on a `.contextMenu` Button reaches the UIMenu icon can't be settled from code. It needs a look on the simulator, ideally on iOS 17 as well as 26.
- Handoff item "a deleted custom duration exercise's sets fall back to weight × reps and read 0": fixed.
  - `SetLog.tracking` prefers the `trackingRaw` snapshot (`Entities.swift:619-622`).
  - Every `SetLog` creation site passes a tracking mode.
  - `delete()` backfills legacy sets and plan items (`ExerciseEditorView.swift:336-347`).
  - One path still writes a wrong snapshot: see LIB-01.
- Handoff item "changing a custom exercise's tracking reinterprets past sets": fixed for sets. The picker is disabled once any `SetLog` exists, and save checks the count again (`ExerciseEditorView.swift:107, 250-251, 259-268`). Plan-slot targets are not migrated: see LIB-04.
- Handoff item "guard `ActiveWorkout.planItem(for:)`": fixed (`ActiveWorkout.swift:240-243`). Deleting a plan item, or the whole plan, while a session is running now falls back to the default rest instead of reading a deleted model.
- Catalog integrity, no finding:
  - exercises.json has 414 entries and all of them decode (required fields and types checked).
  - No duplicate IDs. No duplicate normalised names apart from the four merges.
  - Each merge loser and its survivor are both present, with the same unit and equipment.
  - Every template ID resolves, and none is a merged loser.
  - One ID has a leading space (`" Cossack-squat-bodyweight"`). It is harmless because nothing trims IDs.
  - Custom IDs are `custom-` plus 8 hex characters, and no bundled ID starts with `custom-`.
  - Decoding is all-or-nothing (`CatalogExercise.swift:233-240`), but the test scripts load the bundled file in a debug build, where `assertionFailure` traps. So a broken file would fail those scripts.
- Search performance, no finding: each body evaluation runs one scoring pass over prepared entries (`LibraryView.swift:27`, `ExercisePickerView.swift:20`), and the token sets are built once in `rebuildIndex`. The editor's clash check normalises 414 names per keystroke, which is still cheap.
- Load-scale maths, no finding:
  - The `snap` and `step` epsilon handling survives lb round-trips (for example, 134.99999 lb steps to 140 and 130).
  - `SessionFactory` snaps every opening weight (`ActiveWorkout.swift:29-31`).
  - The progression climbs and deloads with `step` from an already snapped weight.
  - Suggested weights are off the ladder only on the paths in LIB-01 and LIB-03.

## Findings

### LIB-01: A workout started from the watch while the phone app is closed records custom exercises as weight × reps
- Severity: P1
- Category: data-rule
- Confidence: likely. Traced end to end. It depends on the background launch creating no view hierarchy, which CLAUDE.md documents.
- Location:
  - `GymTrack/App/GymTrackApp.swift:62-75` (`configureServices`)
  - `GymTrack/App/RootView.swift:37-39, 452-454` (`syncCustomExercises`, the only loader)
  - `GymTrack/Services/WatchCommandCenter.swift:60-73` (`applyHeadless`, `.startToday`)
  - `GymTrack/Services/ActiveWorkout.swift:45-56` (`SessionFactory.build`, `tracking: item.tracking`)
  - `GymTrack/Models/Entities.swift:149-152` (`PlanItem.tracking`), `619-622` (`SetLog.tracking`)
  - `GymTrack/Features/Plans/DayEditorView.swift:157-169` (`add`)
- What happens:
  - Custom exercises reach `ExerciseCatalog.shared` only through `RootView`'s `.task`. `configureServices` loads `LoadScaleBook` and the watch link, but not the custom exercises.
  - On the headless path, `SessionFactory.build` reads `item.tracking`, which is `catalog?.tracking ?? trackingRaw.flatMap(...) ?? .weightReps`. The catalog lookup returns nil. A plan item's `trackingRaw` is nil unless its custom exercise was deleted. So every custom slot becomes `.weightReps`.
  - That value is snapshotted into each new `SetLog.trackingRaw`, and `SetLog.tracking` prefers the snapshot from then on.
- Failure scenario:
  1. Monday's plan day has a custom "Farmer Hold" set to Duration. `DayEditorView.add` stored a 0–0 rep range for it.
  2. The phone app has been terminated and the phone is in a locker. The lifter starts today's workout from the watch.
  3. The rows are created with `trackingRaw = "weightReps"`, 0 kg and 0 reps. The mirror's `WatchTracking(group.sets.first?.tracking)` shows a weight/reps editor for them.
  4. `.logSet` stores seconds only `if set.tracking == .duration`, so the hold time can't be recorded at all.
  5. The session, the progression and the export keep "0 kg × N" weight × reps for a timed hold. Opening the phone later doesn't repair the rows.
  6. The mirror's scale for a custom Machine exercise also falls back to `derived(for: nil)`, which is 1.25 kg instead of 5 kg. The wrist steps off the machine's ladder until the phone app is opened.
- Suggested fix:
  - In `GymTrackApp.configureServices`, before `WatchCommandCenter.configure`, load the custom exercises and hidden IDs from a fresh context (`ModelContext(container).refreshCustomExercises()` and `ExerciseVisibility.reload`).
  - As a defence, snapshot `PlanItem.trackingRaw` whenever a slot is created (`DayEditorView.add`, `PlanTemplate.materialise`, `BackupService` plan restore) and when `ExerciseEditorView.save` changes tracking. An unresolved catalog lookup can then never fall back to `.weightReps`.
- Verify by:
  - A harness test: clear custom exercises with `ExerciseCatalog.shared.setCustom([])`, call `SessionFactory.build` on a day holding a custom duration item, and assert every row is `.duration`.
  - A manual check: terminate the phone app, start today from the watch simulator, then inspect `ZSETLOG.ZTRACKINGRAW`.

### LIB-02: Chest Dip and other bodyweight "strength" entries are tracked as weight × reps, and the progression invents a load for them
- Severity: P2
- Category: data-rule
- Confidence: confirmed
- Location:
  - `GymTrack/Models/CatalogExercise.swift:259-265` (`trackingMode`)
  - exercises.json entries `chest-dip`, `hyper-extension`, `tibialis-raise`, `ghd-back-extension`
  - `GymTrack/Services/PlanTemplates.swift:113`
  - `GymTrack/Services/TrainingStats.swift:431, 457-473, 388-390` (`suggestion`, `climb`)
  - `GymTrack/Services/ActiveWorkout.swift:29-31`
  - `GymTrack/Features/Session/ActiveWorkoutView.swift:1184-1187`
- What happens:
  - `if category == "strength" { return .weightReps }` catches bodyweight movements whose only equipment is "Other", "None" or "Bench", which the loader filters out to an empty list.
  - The progression treats only `.bodyweightReps` at 0 kg as unloaded (`let isUnloadedBodyweight = item.tracking == .bodyweightReps && lastWeight == 0`).
  - A weight × reps set at 0 kg that clears the top of the range therefore goes through `climb(scale, from: 0, rungs: 1)`. That lands on the first rung of the default ladder, 1.25 kg (2.5 lb).
- Failure scenario:
  1. The user picks Push / Pull / Legs. Push B holds Chest Dip, 3 × 8–12.
  2. They log 12, 12, 12 at bodyweight (the field reads "0", not "BW").
  3. Next Push B, the suggestion says "Go to 1.25 kg and reset to 8 reps", and `SessionFactory` opens every dip set at 1.25 kg × 8.
  4. Tapping Log set mid-set records a weighted dip that never happened. The next session climbs from there, so the invented load grows.
- Suggested fix:
  - Add an explicit per-ID tracking override next to `ExerciseCatalog.merges`. Alternatively, return `.bodyweightReps` for strength entries with no loadable equipment, except the genuinely loaded `wrist-roller` and `walking-lunge-weighted-vest`.
  - In `TrainingStats.suggestion`, never `climb` from a working weight of 0: treat `lastWeight == 0` as unloaded for every mode except duration.
- Verify by:
  - A catalog test asserting `exercise(id: "chest-dip")?.tracking == .bodyweightReps`.
  - A suggestion test with a weight × reps item whose last sets are all at 0 kg and at the top of the range: it must not return `.increaseWeight`.

### LIB-03: Machine-weight corrections never reach plan slots that store a merged exercise ID
- Severity: P2
- Category: bug
- Confidence: confirmed
- Location:
  - `GymTrack/Services/LoadScaleBook.swift:56-58, 66, 69-75, 79-100`
  - `GymTrack/Features/Library/LoadScaleSheet.swift:216-221` (`save`)
  - `GymTrack/Features/Session/ActiveWorkoutView.swift:917, 1189, 1231-1240`
  - `GymTrack/Features/Plans/DayEditorView.swift:268-271, 320-326`
  - `GymTrack/Features/Settings/MachineWeightsView.swift:35-39`
  - `GymTrack/Models/CatalogExercise.swift:147-149`
- What happens:
  - `set.catalog` and `item.catalog` resolve a losing ID to the survivor's `CatalogExercise`, whose `id` is the survivor's.
  - `LoadScaleSheet.save` writes the override under `exercise.id`, the survivor.
  - The set and the plan item read `LoadScaleBook.shared.scale(for: catalogID)` with their raw losing ID. `overrides[loser]` is nil, so they get the derived default.
- Failure scenario:
  1. A plan built before 2026-09-19 holds `dumbbell-pullover-chest`.
  2. In the logger, the lifter taps the "kg · 2" caption, picks lb and 5, and taps Done.
  3. `onSave` moves the pending sets onto the lb ladder: 20 kg becomes 45 lb, stored as 20.41 kg.
  4. The field still reads `set.loadScale`, so it shows kg, steps by 2, and the caption stays grey (`isCustomised(loser)` is false). Reopening the sheet shows lb/5.
  5. Every suggestion for that slot keeps snapping to the kg/2 ladder. The correction can never take effect.
  6. Separately, an override saved on a losing ID between 16 and 19 Sep lists under the survivor's name in Settings. There, swipe-to-clear calls `clear(survivorID)`, so the row can't be removed, and the `ForEach` IDs can clash.
- Suggested fix:
  - Preferred: migrate stored IDs once at launch through `ExerciseCatalog.merges`, for `PlanItem.catalogID`, `ExerciseLoadPreference.catalogID` and `HiddenExerciseRecord.catalogID`, leaving `SetLog` IDs as logged.
  - Alternative: key `LoadScaleBook` by `ExerciseCatalog.canonicalID(for:)` in `scale`, `isCustomised`, `set`, `clear`, `reload` and `customised`.
  - In either case, canonicalise the group lookup in `ActiveWorkout.addExercise`.
- Verify by: a test that calls `LoadScaleBook.set(lb5, for: "dumbbell-pullover")` and then asserts `scale(for: "dumbbell-pullover-chest") == lb5`. Also a manual check on a plan slot with the losing ID.

### LIB-04: Changing a custom exercise from Duration to reps leaves its plan slots on a 0–0 range, and the progression then adds weight every session
- Severity: P2
- Category: bug
- Confidence: confirmed
- Location:
  - `GymTrack/Features/Library/ExerciseEditorView.swift:259-269` (`save`)
  - `GymTrack/Features/Plans/DayEditorView.swift:163-164` (`add`), `240-241`
  - `GymTrack/Models/Entities.swift:149-152`
  - `GymTrack/Services/TrainingStats.swift:413, 457-473`
  - `GymTrack/Services/ActiveWorkout.swift:36-44`
- What happens:
  - The tracking lock counts only `SetLog` rows. Plan items keep the targets written for the old mode, and `add` writes `targetRepsLow`/`targetRepsHigh` of 0 for a duration exercise.
  - `PlanItem.tracking` reads the catalog first, so the slot becomes weight × reps with a 0–0 range.
  - `allHitTop = ... setsAtWeight.allSatisfy { $0.reps >= item.targetRepsHigh }` is then always true.
- Failure scenario:
  1. The user creates a custom "Sled Drag" as Duration and adds it to a day.
  2. Before ever logging it, they change it to Weight × reps. This is allowed because no sets exist yet.
  3. Their first session opens every set at 0 reps (`targetRepsLow`).
  4. After 60 kg × 10, the next session says "You cleared 0 reps on every set. Go to 62.5 kg and reset to 0 reps". It adds a rung and opens at 0 reps every session, whatever was lifted.
  5. The exported sets carry a 0–0 target range.
- Suggested fix:
  - When tracking changes in `ExerciseEditorView.save`, fetch the plan items with that ID and normalise their targets. Moving into a reps mode with `targetRepsHigh == 0` should set the `add` defaults of 8–12. Write `trackingRaw` too (see LIB-01).
  - Guard `TrainingStats.suggestion` so that `targetRepsHigh < 1` never yields `.increaseWeight`.
- Verify by: a suggestion test with `targetRepsHigh == 0`, and the manual flow above.

### LIB-05: Search aliases make exercises vanish while a word is being typed
- Severity: P3
- Category: bug
- Confidence: confirmed (the scoring was simulated against exercises.json in python, mirroring `ExerciseSearch`)
- Location: `GymTrack/Models/ExerciseSearch.swift:34-53` (aliases), `69-74` (`tokenise`), `89-97` (`Entry.init`), `126-130` (`score`)
- What happens: aliases are applied to both the index and the query. The long form of an alias therefore never exists in the index, and an alias key that begins an unrelated word replaces that word.
- Failure scenario (result counts):
  - "calv" and "calve" return 0 results; "calves" returns 7.
  - "fli" and "flie" return 0; "flies" returns 11.
  - "quadr" through "quadrice" return 0.
  - "abdo" through "abdomina" return 0.
  - "ham" returns 30 hamstring entries and none of the Hammer Curl or Hammer Strength entries.
  - "ext rot" returns 0, so the External Rotation entries can't be reached with that query.
  - "ham curl" returns leg curls.
  - Library then says "No exercise here is called 'calv'… add it", and the picker offers "Add 'calv'". Both invite duplicate custom exercises.
- Suggested fix: in `score`, accept a query token if either its alias expansion or its raw form prefixes an entry token. Index the raw normalised words alongside the aliased ones in `Entry.allTokens`, and keep a raw `squashedName` too.
- Verify by: an `ExerciseSearch` test over the bundled JSON that asserts a non-empty result for every prefix of "calves", "flies", "quadriceps" and "abdominals", Hammer Curl found for "ham", and External Rotation found for "ext rot".

### LIB-06: Removing an exercise from a day and then adding one can give two exercises the same position
- Severity: P3
- Category: bug
- Confidence: likely. It depends on SwiftData keeping a deleted child in `day.items` until pending changes are processed.
- Location: `GymTrack/Features/Plans/DayEditorView.swift:157-169` (`add`), `171-175` (`delete`), `184-187` (`reindex`); `GymTrack/Models/Entities.swift:71` (`orderedItems`)
- What happens:
  - `delete(at:)` calls `context.delete` and then `reindex()` straight away, which walks `day.orderedItems`.
  - The deleted row is still in the relationship until the save, so it keeps its index and the survivors keep their old numbers, leaving a gap.
  - `add` then uses `order: day.items.count`, which collides with the last survivor.
- Failure scenario:
  1. A day holds A (0), B (1), C (2). The user swipe-deletes A, then adds D.
  2. The orders are now B (1), C (2), D (2).
  3. `orderedItems` sorts only by `order`, so C and D swap unpredictably in the editor. `SessionFactory` may also build D before C, on the phone and on the wrist.
- Suggested fix:
  - Reindex over `day.orderedItems.filter { !$0.isDeleted }`, or call `context.processPendingChanges()` first.
  - In `add`, use `(day.items.map(\.order).max() ?? -1) + 1`.
  - Break ties in `orderedItems` with a stable key.
- Verify by: a harness test that deletes the first and then a middle item, saves, adds an item, and asserts the orders run 0…n-1 with no repeats.

### LIB-07: After a custom exercise is deleted, its weight caption opens a blank sheet
- Severity: P3
- Category: bug
- Confidence: confirmed
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:1184-1189, 1230-1233`; `GymTrack/Features/Plans/DayEditorView.swift:268-271, 320-321`
- What happens: the caption or chip always sets `showingScale = true`, but the sheet's content is `if let catalog = set.catalog { LoadScaleSheet(...) }` (and the same for `item.catalog`). A deleted custom exercise resolves to nothing, so the sheet presents empty.
- Failure scenario:
  1. The user deletes a custom "Iso Row" that sits in a plan. The delete dialog allows this and says the slots keep their numbers.
  2. Tapping the slot's "Marked in" chip, or the logger's kg caption during a workout, opens a blank sheet with no title and no Done button. It has to be swiped away, mid-set, against the friction rule.
- Suggested fix: hide the caption when `catalog == nil`, or let `LoadScaleSheet` take a catalog ID and a display name. Overrides are keyed by ID and still apply to such slots, so they could still be corrected.
- Verify by: a manual check on a plan slot and a live row after deleting their custom exercise.

### LIB-08: Days not pinned to a weekday are never offered; Today calls every day a rest day and the watch starts an empty freestyle session
- Severity: P3
- Category: missing-feature
- Confidence: confirmed
- Location:
  - `GymTrack/Models/Entities.swift:36-44` (`day(for:)`, `day(onWeekday:)`)
  - `GymTrack/Features/Plans/PlansView.swift:231-237` (`addDay`, weekday nil)
  - `GymTrack/Features/Today/TodayView.swift:17, 120-123, 381-400`
  - `GymTrack/Services/WatchCommandCenter.swift:69-77`
- What happens:
  - Scheduling is by weekday only, and "Add day" and "Start from blank" create days with no weekday. `day(for:)` is therefore nil every day.
  - Today shows "Rest day. Nothing scheduled. Recovery is part of the plan".
  - The watch's Start Today falls through to an empty "Freestyle Session".
- Failure scenario: a lifter running A/B/C in rotation has to tap "Pick a session" before every workout and remember which day comes next. The app also tells them they are resting on a day they meant to train.
- Suggested fix:
  - Add `Plan.nextRotationDay(after:)`. It returns the training day that follows, in `orderedDays` order and wrapping round, the day behind the latest finished session's `planDayID`.
  - Use it when no pinned day matches today, in Today, `WatchCommandCenter` `.startToday`, `WatchBridge.idle` and `WidgetPublisher`.
  - Don't call an unscheduled day a rest day.
- Verify by: a unit test on the rotation, including wrap-around and a deleted `planDayID`, plus a manual check with an unscheduled routine.

### LIB-09: Onboarding forces a template, and the active routine can never be deleted
- Severity: P3
- Category: missing-feature
- Confidence: confirmed
- Location:
  - `GymTrack/Features/Onboarding/OnboardingView.swift:202-237` (`footer`, `finish`), `116`
  - `GymTrack/Features/Plans/PlansView.swift:23-31, 192-218, 292-321`
- What happens:
  - Onboarding has no blank or skip option. `finish()` always materialises a template as the active plan.
  - The only delete control is the trash button on rows under "Other routines". Neither the active routine nor `PlanSettingsView` has one.
  - A lifter who brings their own program must adopt a template, add a blank routine, activate it, and only then delete the template. A lone routine can't be deleted at all.
  - The unit step's copy, "Steps in 2.5 kg" / "Steps in 5 lb", no longer holds now that ladders depend on the equipment (dumbbells step 2 kg, machines 5 kg).
- Failure scenario: a new user with their own split ends up with an unwanted template as their active routine and needs four extra screens to get rid of it.
- Suggested fix:
  - Add "Start from blank" to onboarding's plan step, creating an empty active `Plan` as `onBlank` does.
  - Add "Delete routine" to `PlanSettingsView`. Block it while a session from any of the plan's days is open (as `isInUse` does), and activate the next plan if there is one.
  - Reword the unit copy.
- Verify by: a manual check of both flows.

### LIB-10: The custom-exercise edits, the load-scale ladder and search have no regression tests
- Severity: P3
- Category: test-gap
- Confidence: confirmed
- Location: `GymTrack/Features/Library/ExerciseEditorView.swift:255-358`; `GymTrackShared/LoadScale.swift:51-96, 162-168`; `GymTrack/Models/ExerciseSearch.swift`; `GymTrack/Services/PlanTemplates.swift:52-55`
- What happens:
  - GT-021 is still marked "plan rename verification pending". The rename, the tracking lock and the delete snapshot live in private view methods, so no script can reach them.
  - `LoadScale.step`, `snap` and `converted` are pure functions, but their lb round-trips are untested.
  - Template IDs are only guarded by `assertionFailure`.
  - The alias holes in LIB-05 would have been caught by a basic search test.
- Failure scenario: a change to `ExerciseEditorView.save` that drops the plan-item rename, or a new alias that hides "hammer", ships unnoticed.
- Suggested fix:
  - Move `save` and `delete` into a `CustomExercises` service (static functions over a `ModelContext`).
  - Add `scripts/test-custom-exercises.sh`, in the style of the existing scripts. It should check:
    - a rename updates plan items and leaves set logs alone;
    - a tracking change is refused once sets exist;
    - delete snapshots `trackingRaw`;
    - `LoadScale` stepping from values converted out of lb;
    - every `PlanTemplate` ID resolves;
    - the search prefixes from LIB-05.
- Verify by: the new script passing.
