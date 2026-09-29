> Detail file from the 2026-09-28 review. The index, the canonical severities and the duplicate map are in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md). Where this file disagrees with the index, the index wins. Line numbers refer to the working tree on 2026-09-28 (HEAD f5809ff plus the uncommitted GT fix pass).

# Backup, export, settings and AI-coach readiness: findings

Files read in full: GymTrack/Services/BackupService.swift, GymTrack/Services/AppSettings.swift, GymTrackShared/Units.swift, GymTrack/Features/Settings/SettingsView.swift, GymTrack/Features/Settings/HealthWatchSettingsView.swift, GymTrack/Features/Settings/MachineWeightsView.swift, GymTrack/Models/Entities.swift, Tests/BackupServiceTests.swift, docs/AI_COACH.md (sections: Decision, Information already available, Package the history, Proposal contract).
Excerpts traced: ActiveWorkout.swift (session/set creation), SessionClosing.swift (`close`), HealthKitService.swift (`deleteWorkout`, `vitals`, `backfillVitals`, pending cleanup), GymTrackApp.swift (`dropWarmupSets`, idle timer), RootView.swift (watch/widget republish, stale-session close), WatchCommandCenter.swift (mirror), WatchBridge.swift, LoadScaleBook.swift, LoadScaleSheet.swift, CatalogExercise.swift (`merges`), SetFeel.swift, SetHeartRate.swift (detected window end), git history of BackupService.swift.

Round-trip summary (every stored property on every @Model):
- Plan, PlanDay, BodyMetric: complete.
- PlanItem: `id` dropped (new UUID on import). Nothing in the app reads it.
- WorkoutSession: `planDayID` dropped (see DATA-05). `preferredExerciseID` dropped, which is fine because it only matters on an open session and export skips open sessions.
- SetLog: `id` dropped (new UUID on import). Everything else round-trips. `continuesPreviousSet` is re-derived from the key's presence, `heartRateWindowRaw` only when it is a known value, and the detected window only when `start < end <= completedAt`. `SetHeartRate.swift:260` clamps `end` to `completedAt`, so a window the app wrote itself always survives.
- ExerciseNote: `id` and `updatedAt` are dropped (`updatedAt` resets to the import time).
- CustomExerciseRecord `createdAt`, ExerciseLoadPreference `updatedAt`, HiddenExerciseRecord `hiddenAt`: dropped. Nothing reads them.
- Settings: only `weightUnit`, `userName` and `defaultRestSeconds` travel. `trackRPE`, `restTimerAutoStart`, the Health toggles, `watchAutoLaunch`, `haptics` and `keepScreenAwake` stay per device. That is reasonable, except `trackRPE` for the coach (DATA-08).
- Absent-key rule: Codable synthesis uses `encodeIfPresent` for every Optional, so nil values are omitted and never written as null. The zeros, placeholders and empty strings come from non-optional fields (DATA-04).
- Backward compatibility: every non-optional DTO field was already in the first version-2 DTO (5b7b123). `restSeconds` Int to Int? and `isWarmup` Bool to Bool? still decode. Unknown keys are ignored by JSONDecoder, so a file from a newer build decodes, but it loses whatever this build doesn't know. `version` is never checked on restore. No finding raised for that.

## Prior findings re-check
- GT-003: OK. The deletes, the inserts and `beforeCommit` share one `context.save()`, a throw rolls back, and settings and caches are touched only after the commit (`BackupService.swift:534-557`). No `await` sits between the open-session guard and the save, so autosave cannot interleave. The injected-failure test covers plans with their descendants (`Tests/BackupServiceTests.swift:47-62`). The Health deletion that now follows the commit is a separate problem (DATA-01).
- GT-020: REGRESSION. The link is now exported (`BackupService.swift:329`) and restored (`:605`). But the restore deletes Health workouts by set difference of `healthWorkoutID`, not by session identity. Every backup written before this fix has no `healthWorkoutID`, so restoring one deletes from Health the workouts of the very sessions it brings back, and the test asserts this as correct (`Tests/BackupServiceTests.swift:81-90`). See DATA-01. Erase now also deletes Health workouts, but its dialog was not updated (DATA-02).

## Findings

### DATA-01: Restoring any pre-fix backup deletes from Apple Health the workouts of the sessions it is restoring
- Severity: P1
- Category: bug
- Confidence: confirmed (traced end to end; the regression test asserts the behavior)
- Location: `GymTrack/Services/BackupService.swift:532-558` (`restore(data:)`), `:722-724` (`deleteStoredRecords`), `Tests/BackupServiceTests.swift:81-90`, `GymTrack/Features/Settings/SettingsView.swift:150-154,196-198` (no confirmation before restore)
- What happens: `let replacementHealthIDs = Set(archive.sessions.compactMap(\.healthWorkoutID))` is compared with the healthWorkoutIDs of the local sessions, and every local ID missing from the file is deleted from Health: `deleteHealthWorkouts(oldHealthIDs.subtracting(replacementHealthIDs), …)`. Session identity is never consulted. A backup written by any committed build has no `healthWorkoutID` key (it was added in this working tree), so every linked session in it counts as "disappearing" even though the same session `id` is restored. The restored session gets `healthWorkoutID = nil`. `HealthKitService.saveWorkout` only runs at finish (`:156-157`), so nothing ever writes it back. The test builds exactly this case (same session, key absent) and asserts `deleted == [healthID]`.
- Failure scenario: The user has three weeks of sessions, each linked to a Health workout, and a backup exported last week from a current build. To recover an exercise they deleted by mistake, they pick that backup under Settings, Restore. No confirmation appears. The data is replaced, then every GymTrack workout in Apple Health is deleted, the older sessions included. Fitness history, ring credit and the watch's workout records are gone, and iCloud Health sync carries the deletion to every device. A second case: a backup in the new format taken between the phone's fallback save and the watch's late save still links the phone copy. Restoring it deletes the watch's measured workout (`watchID` is not in the file), and the link it keeps points at a copy that GT-008 cleanup already removed.
- Suggested fix: Key the decision by session `id`. For a session present both locally and in the archive, keep the local `healthWorkoutID` when the archive has none or a different one. Consider only sessions absent from the archive as candidates for Health deletion. Better still, don't delete from Health on restore at all: restore means "bring my data back", and deleting records outside the app is a separate action that needs its own explicit consent. In any case add a confirmation before the importer that says restore replaces everything. Invert the assertion at `Tests/BackupServiceTests.swift:88`.
- Verify by: In `BackupServiceTests`, restore a file with the same session `id` and no `healthWorkoutID`. Assert that `deleted` is empty and that the restored session still has `healthID`. Add a case where the archive link differs from the local one and assert the local one survives.

### DATA-02: Erase deletes every linked Health workout, the dialog doesn't say so, and the backup it recommends can't bring them back
- Severity: P2
- Category: data-rule
- Confidence: confirmed (in code; whether HealthKit lets the phone delete a workout the watch app saved is unverified)
- Location: `GymTrack/Features/Settings/SettingsView.swift:199-204` (dialog), `:283-302` (`wipe`), `GymTrack/Services/BackupService.swift:694-715` (`wipe`), `GymTrack/Services/HealthKitService.swift:319-336` (`deleteWorkout`, `guard !workouts.isEmpty else { return false }`)
- What happens: The dialog reads "Every routine, session and record on this device is deleted. Export a backup first if you might want it back." `wipe` now also deletes every linked HKWorkout, which is not "on this device": Health syncs across devices through iCloud. The backup holds only the IDs of those workouts. A restore after the erase brings back sessions whose `healthWorkoutID` points at deleted workouts, and nothing re-saves them. `deleteWorkout` returns false when the query finds nothing, so every later erase or restore reports "We could not confirm removal of N workouts" for workouts that are already gone.
- Failure scenario: The user follows the dialog's advice: Export, then Erase, then Restore. Their history is back in GymTrack, but every GymTrack workout has vanished from Fitness and Health for good, on the Mac and iPad too. The next erase shows an alert blaming Health access for N workouts that no longer exist.
- Suggested fix: Make Health cleanup an explicit, separate choice in the Erase dialog. Either add a second destructive button, "Erase and remove N workouts from Health", or leave Health alone by default. Update the dialog text to match. In `deleteWorkout`, tell "not found" apart from "refused", so a workout that is already gone counts as cleaned up (or at least isn't reported as a failure), for example by returning an enum.
- Verify by: Manual test on a real device: erase with the default choice and confirm the workouts remain in Fitness. A unit test: a stub that reports "not found" gives `isComplete == true`.

### DATA-03: Restoring a backup from the warm-up era turns warm-up sets back into working sets
- Severity: P2
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrack/Services/BackupService.swift:130-132` (`isWarmup`, "ignored — a set is a set now"), `:624-671` (`insertArchive` set loop), `GymTrack/App/GymTrackApp.swift:106-127` (`dropWarmupSets`: `DELETE FROM ZSETLOG WHERE ZISWARMUP = 1`)
- What happens: When warm-ups were removed (9d21a0f), the store migration deleted every warm-up row because they "would put noise in a record whose whole value is that everything in it actually happened". The import was changed the same day to decode `isWarmup` and ignore it. Every set with `"isWarmup": true` in an older file is therefore inserted as an ordinary completed working set, with nothing left to mark it.
- Failure scenario: A backup exported on 2026-09-18 holds sessions with two warm-up rows per exercise (for example 40 kg x 10 and 60 kg x 5 before 100 kg x 5). Restoring it puts them into history as sets 1 and 2. They inflate volume and effort-set counts, shift `pairingPosition`, so "last time" hints compare set 1 with a warm-up, and they reach the AI coach as working sets that nothing can tell apart from real ones.
- Suggested fix: In `insertArchive`, skip `setDTO.isWarmup == true`, the same rule `dropWarmupSets` applied to the store. Keep decoding the key.
- Verify by: Decode a legacy archive with one `isWarmup: true` set and one working set. Assert that only the working set is inserted.

### DATA-04: Every weighted set is exported with a `seconds` of 45 nobody measured, plus sentinel zeros and invented targets
- Severity: P2
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrack/Services/ActiveWorkout.swift:52` (`seconds: item.targetSeconds`), `:801-803` (`seconds: previous?.seconds ?? 45`, `targetRepsLow: template?.targetRepsLow ?? 8`, `targetRepsHigh … ?? 12`), `:431-432` (continuation targets `0`), `GymTrack/Models/Entities.swift:117` (`targetSeconds = 45` on every PlanItem), `GymTrack/Services/BackupService.swift:334-336,346`
- What happens: A planned set is created with the plan item's hold target as its `seconds`. Every PlanItem defaults to 45, including squats. Nothing clears it on a reps set: the only writers of `seconds` are guarded by `tracking == .duration` (`ActiveWorkout.swift:321,993`, `SessionClosing.swift:38`, `WatchCommandCenter.swift:88`). Export writes `"seconds": 45` on every weighted set. `docs/AI_COACH.md:108` tells the coach that sets carry a "duration". Likewise, a continuation row exports `targetRepsLow/High: 0` as a sentinel for "no target", and an exercise added outside the plan exports an 8-12 "target" that nobody prescribed. Duration sets export whatever `reps` they were seeded with. Every session, day and item also carries `"notes": ""`, which the `noteTags` comment (`BackupService.swift:95-98`) says a file should not do.
- Failure scenario: The coach computes time under tension or work density from `seconds` and concludes that every barbell set lasted 45 s. Or it scores a heavy triple in a freestyle session as "fell short of an 8-12 target".
- Suggested fix: At the source, seed `seconds` only for `.duration` sets and `reps` only for non-duration ones. In the export, write `seconds` only for `.duration`, `reps` only for non-duration, targets only when greater than 0, and `notes` only when non-empty. Make those DTO fields Optional so older files still decode; import defaults them to 0 or "", and `version` stays 2. For targets defaulted outside the plan, either omit them or flag them.
- Verify by: An export test: a planned weightReps set has no `seconds` key, a continuation has no target keys, and a plank has no `reps` key. Old files with those keys still restore.

### DATA-05: The export can't tie a session to its plan day or cite a set, and restore regenerates every set ID
- Severity: P3
- Category: missing-feature
- Confidence: confirmed
- Location: `GymTrack/Services/BackupService.swift:78-102` (`SessionDTO` has no `planDayID`), `:118-214` (`SetDTO` has no `id`), `:597-671`, `GymTrack/Models/Entities.swift:180` (`planDayID`), `GymTrack/Models/SessionClosing.swift:65-67` (unlogged sets are deleted at close)
- What happens: `WorkoutSession.planDayID` is stored but never exported, so a session joins its plan only through `title`/`planName`, which are free-text copies. Plans are edited in place with no revisions, and `close` deletes unlogged sets, so the file cannot show what was planned for a past session. `docs/AI_COACH.md:267` requires citing "session and set IDs", but sets have none in the file, and a restore mints new IDs anyway.
- Failure scenario: The user renames "Push" to "Upper A" (or has two plans that both have a "Day 1"). The coach can no longer attribute old sessions to a day, so adherence, "skipped movements" and substitutions can't be computed. A proposal that cites a set can only cite a guessed composite key.
- Suggested fix: Add optional `planDayID: UUID?` to `SessionDTO` and optional `id: UUID?` to `SetDTO` (and to `ItemDTO`/`ExerciseNoteDTO`), and restore them when present. This is zero friction and all the fields are already stored. Snapshotting the planned prescription per session is a larger follow-up.
- Verify by: A full round-trip test (export, restore, export) asserting identical output apart from `exportedAt`. It would also have caught DATA-01 and DATA-03.

### DATA-06: The export's arrays are in no defined order, so `continues` ("the row above") and the file hash are unreliable
- Severity: P3
- Category: code-health
- Confidence: likely (SwiftData to-many arrays and unsorted fetches have no guaranteed order)
- Location: `GymTrack/Services/BackupService.swift:290-295` (`FetchDescriptor` without `sortBy`), `:333` (`session.sets.map` is unsorted), `:189-213` (`continues` doc: "this row and the one above it"), `:440-441` (claims byte-stable output)
- What happens: Sessions, sets, plans, body metrics, load scales and custom exercises are written in whatever order SwiftData returns them. `continues` is documented as linking a row to "the one above it", which in the file is not necessarily the previous set. The comment at 440 wants "two exports of unchanged data are the same bytes", and the AI_COACH package relies on "the untouched versioned JSON export and its hash".
- Failure scenario: A reader takes "above" literally and attaches a drop to the wrong set. Two exports of unchanged data hash differently, and a diff between monthly exports is noise.
- Suggested fix: Sort sessions by `startedAt`, sets by `SetLog.precedesInSession`, plans by `createdAt`, metrics by `date`, and scales and custom exercises by ID before encoding.
- Verify by: Export the same store twice after relaunching and compare the bytes. Assert that the sets inside each session are in `exerciseOrder`/`setIndex` order.

### DATA-07: Timestamps are UTC with no time zone anywhere in the file, but plan weekdays are local
- Severity: P3
- Category: missing-feature
- Confidence: confirmed
- Location: `GymTrack/Services/BackupService.swift:380` (`.iso8601`), `:383-388` (the file name is local and the contents are UTC), `GymTrack/Models/Entities.swift:53` (`weekday` is local, 1 = Sunday)
- What happens: Every date is written as `...Z`, and neither the user's zone nor the app version is recorded. `DayDTO.weekday` is a local weekday. Only the phone knows the zone.
- Failure scenario: The user trains in Cairo (UTC+3 in summer). A 01:30 Tuesday session is exported as Monday 22:30Z, so the coach assigns it to Monday's plan day, puts it in the wrong week at the week boundary, and misreads time-of-day patterns.
- Suggested fix: Add optional archive-level `timeZone` (`TimeZone.current.identifier`) and `appVersion`. Per-session `timeZone` needs a model field, and only matters for a user who travels.
- Verify by: Check that the exported JSON has the keys, and that old files still decode.

### DATA-08: Effort is exported as a point RPE the lifter never gave, with no way to tell scale or whether it was asked
- Severity: P3
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrackShared/SetFeel.swift:10-14` (`easy = 6` shown as "3+ left"), `GymTrack/Services/BackupService.swift:163,347`, `GymTrack/Services/AppSettings.swift:74-76` (`trackRPE` is not exported)
- What happens: The answer "Easy: three or more reps left" is stored and exported as `rpe: 6`, which by definition means four in reserve. That is a point value inferred from an open range. Ratings from the old 6/7/8/9/10 strip use the same key and the same numbers, so `rpe: 8` may be a literal RPE 8 or the word "Solid". An absent `rpe` means "not answered" when `trackRPE` was on and "never asked" when it was off, and the file doesn't say which.
- Failure scenario: The coach treats "Easy" sets as RPE 6 and recommends a bigger jump than the lifter's answer supports. Or it reads a month with `trackRPE` off as a month of skipped ratings.
- Suggested fix: Next to `rpe`, export a derived `feel` word for answers given on the four-word strip. Going forward, that needs a marker when an answer is stored, for example a `feelRaw`, the way `continues` is derived. Put `trackRPE` into `Settings` as an optional field. The AI_COACH data dictionary should state the scale change on 2026-09-19.
- Verify by: An export test that checks the `feel` key and `settings.trackRPE`.

### DATA-09: Machine rungs are exported only for corrected exercises, though AI_COACH.md says every machine's increment is there
- Severity: P3
- Category: missing-feature
- Confidence: confirmed
- Location: `GymTrack/Services/BackupService.swift:371-373` (`loadScales` holds overrides only), `:270-285` (`CatalogExerciseDTO` has no scale), `GymTrack/Services/LoadScaleBook.swift:115,139` (the defaults are computed from equipment and the app unit), `docs/AI_COACH.md:115`
- What happens: Most exercises follow `LoadScaleBook.derived(for:unit:)`, which the file cannot reproduce. The coach cannot propose legal rungs, and the proposal contract says to reject "impossible load rungs".
- Failure scenario: The coach suggests 27.5 kg on a dumbbell exercise whose default rung is 2 kg or 2.5 kg. The phone rejects it, or snaps it silently.
- Suggested fix: Add optional `unit`, `increment` and `scaleIsDefault` to `CatalogExerciseDTO` (and the same for custom exercises), taken from `LoadScaleBook.shared.scale(for:)`. Restore never reads this section, so there is no restore risk.
- Verify by: An export test: an uncorrected barbell exercise carries its default increment.

### DATA-10: Session heart rate and energy carry no provenance; a few background samples or phone pedometer energy read as a workout measurement
- Severity: P3
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrack/Services/HealthKitService.swift:350-371` (`vitals` queries every source in the window), `:382-393` (`backfillVitals`, `energy > 0`), `GymTrack/Services/BackupService.swift:326-328`
- What happens: Per-set heart rate has `heartRateWindow`, but session `averageHeartRate`/`maxHeartRate` is a statistic over whatever samples lie between start and end. For a phone-only session with the watch merely worn, that can be one to a handful of background readings. `activeEnergyKcal` accepts any value above 0, including a few kcal from the phone's pedometer. `hasHealthMetrics` hides values under 1, but the export does not.
- Failure scenario: A phone-only session exports `averageHeartRate: 88` from two readings and `activeEnergyKcal: 3`. The coach reads a 60-minute session as very low effort.
- Suggested fix: Export a session `vitalsSource` (`watchWorkout` when `wasWatchDriven`, `background` otherwise) or a sample count. Drop session heart rate below a minimum sample count, and apply the same floor of 1 kcal to energy in the export.
- Verify by: A unit test on the export mapping, and a device check with a phone-only session.

### DATA-11: A machine correction saved from the logger is ignored for the four merged exercise IDs
- Severity: P3
- Category: bug
- Confidence: confirmed
- Location: `GymTrack/Features/Library/LoadScaleSheet.swift:217-221` (saves under `exercise.id`, the canonical ID), `GymTrack/Services/LoadScaleBook.swift:56-58` (`overrides[catalogID]` with the raw ID), `:163,167` (`PlanItem`/`SetLog.loadScale` look up the raw ID), `GymTrack/Models/CatalogExercise.swift:111-116` (`merges`)
- What happens: A plan item created before 2026-09-19 can still hold `single-leg-leg-extension` or one of the other three merged IDs. The sheet resolves it to the survivor and saves the override under the survivor's ID. Every reader that goes through a set or plan item looks up the old ID and falls back to the default.
- Failure scenario: The user marks the single-leg extension machine as pounds in 5 lb steps. The sheet shows the change as saved, but the logger, the watch mirror (`WatchCommandCenter.swift:426`) and the nudges keep using the kg default. Machine weights lists the exercise as corrected.
- Suggested fix: Canonicalize in `LoadScaleBook.scale(for catalogID:)`, `set` and `clear` (`ExerciseCatalog.canonicalID(for:)`), and canonicalize keys in `reload()`.
- Verify by: A unit test: `set(scale, for: "dumbbell-pullover")` followed by `scale(for: "dumbbell-pullover-chest")` returns the override.

### DATA-12: "Keep screen awake while training" keeps it awake whenever the app is open
- Severity: P3
- Category: bug
- Confidence: confirmed
- Location: `GymTrack/App/GymTrackApp.swift:41`, `GymTrack/Services/AppSettings.swift:58-63`, `GymTrack/Features/Settings/SettingsView.swift:118`
- What happens: `isIdleTimerDisabled` is set from the setting at launch and on toggle, and never tied to a session starting or ending. The setting defaults to true (`AppSettings.swift:106`).
- Failure scenario: Someone leaves the app open on Progress or Today, and the phone never auto-locks. That drains the battery and leaves the data showing on an unlocked screen.
- Suggested fix: Set `isIdleTimerDisabled = keepScreenAwake && activeWorkout != nil` from RootView when the active workout changes and when the scene becomes active.
- Verify by: Manual: with no workout running the screen locks at the system timeout; during a workout it stays on.

### DATA-13: Changing the weight unit or rest auto-start mid-workout leaves the wrist on the old value
- Severity: P3
- Category: bug
- Confidence: likely
- Location: `GymTrack/App/RootView.swift:82-84` (re-pushes only on `trackRPE`), `GymTrack/Services/WatchCommandCenter.swift:434-437`, `GymTrackWatch/WatchConnector.swift:149` (`mirror.session?.unit ?? mirror.idle.unit`)
- What happens: Settings stays reachable during a session (`SettingsView.swift:169-173`). The wrist takes its unit from the session snapshot first. Only `trackRPE` triggers `pushToWatch()`, so the unit and `restAutoStart` go stale until some other event pushes.
- Failure scenario: Mid-workout the user switches to lb. The phone shows 225 lb and the wrist still shows 102.1 kg with kg crown steps. Or they turn off auto-start and the wrist still starts a rest after the next wrist log.
- Suggested fix: Add `.onChange(of: AppSettings.shared.weightUnit)` and `.onChange(of: AppSettings.shared.restTimerAutoStart)` next to the `trackRPE` handler, both calling `activeWorkout?.pushToWatch()`.
- Verify by: Paired simulators: change the unit mid-session and check the wrist tile immediately.

### DATA-14: Export, restore and erase do all their work on the main thread with no progress, and erase's Health deletes run one by one
- Severity: P3
- Category: performance
- Confidence: likely (depends on history size)
- Location: `GymTrack/Features/Settings/SettingsView.swift:239-246,248-262,283-302`, `GymTrack/Services/BackupService.swift:289-392` (sync export), `:498-559` (`@MainActor` decode, insert, save), `:741-749` (serial Health deletes)
- What happens: Export fetches and faults every session and set, then pretty-prints the JSON synchronously in a button action. Restore decodes and inserts the whole archive on the main actor. Erase then awaits one HealthKit query and one delete per session. Throughout, the Settings sheet shows no progress and its buttons stay enabled.
- Failure scenario: With a year of history (thousands of sets) the UI freezes on Export or Restore. After Erase, the sheet sits on an empty store for many seconds before onboarding appears, and the user taps Erase or Restore again.
- Suggested fix: Build the archive from value snapshots on a background `ModelContext` (or at least `Task.yield` between phases). Show a progress state, and disable the data buttons while an operation is in flight. Delete Health workouts in one `store.delete` with a batch predicate.
- Verify by: Seed around 300 sessions and time Export and Restore in Instruments (look for main-thread hangs).
