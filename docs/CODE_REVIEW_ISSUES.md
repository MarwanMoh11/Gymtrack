# Code review backlog

Review date: 2026-09-25. Fix pass: 2026-09-26. All 22 findings have code changes in the working tree. IDs remain stable for follow-up. P1 means potential data loss or a workout being applied to the wrong session; P2 means materially incorrect behavior or record; P3 means a smaller presentation error. The original locations and failure descriptions below are retained as review evidence; line numbers may have shifted after fixes.

The focused SwiftData and watch protocol regressions pass, as do the iOS, widgets, and watchOS simulator builds. These checks do not prove HealthKit behavior on real devices: the simulator cannot grant the needed Health access. Watch delivery, Health deletion and deduplication, and store-open recovery still need the validation called out in their statuses. GT-008 now persists a failed fallback cleanup and retries it after relaunch or renewed Health authorization; a copy can remain in Health while read permission is unavailable. No fix has been committed yet.

## P1

### GT-001 — A delayed wrist Finish or Discard can act on the next workout

**Status:** Implemented; paired-watch delivery validation pending. **Code:** [`WatchCommandCenter.swift`](../GymTrack/Services/WatchCommandCenter.swift) (`.finish`/`.discard` handling around lines 183–200), [`RootView.swift`](../GymTrack/App/RootView.swift) (watch command handling around line 330).

The commands do not identify the session being ended. If the watch sends a
command for workout A after A has ended and workout B has started, the phone
selects its current active session and closes or deletes B. Put the expected
session ID in lifecycle commands and reject commands for any other session,
including in the headless command path. Verify with a delayed command from A
after starting B.

### GT-002 — Queued wrist sets can be lost when Finish arrives first

**Status:** Implemented; ordering regression passed; paired-watch validation pending. **Code:** [`WatchConnector.swift`](../GymTrackWatch/WatchConnector.swift) (queued set delivery around lines 190–210), [`WatchRootView.swift`](../GymTrackWatch/Views/WatchRootView.swift) (`end()` around line 101), [`WatchCommandCenter.swift`](../GymTrack/Services/WatchCommandCenter.swift) (`.finish` around line 183).

Offline set logs travel through `transferUserInfo`; Finish can travel through
the immediate `sendMessage` path. If Finish reaches the phone first, closing
the session removes uncompleted set rows, so later queued logs have nothing to
update. Reconcile pending logs before close, or make late logs safely attach to
the identified finished session. Test both message arrival orders.

### GT-003 — A failed restore can erase the existing database

**Status:** Fixed; restore failure regression passed. **Code:** [`BackupService.swift`](../GymTrack/Services/BackupService.swift) (`restore` around line 486, `wipe` around line 649).

Restore calls `wipe`, which saves deletions, before constructing and saving the
replacement archive. A failure after the wipe leaves the old data gone. Stage
and validate the complete replacement, or provide transaction-like rollback,
before deleting the original store. Inject a failure after deletion and verify
the original data survives.

### GT-004 — Store-open failure silently turns logging into temporary data

**Status:** Implemented; store fault-injection verification pending. **Code:** [`GymTrackApp.swift`](../GymTrack/App/GymTrackApp.swift) (container setup around line 41).

If the on-disk `ModelContainer` fails to open, the app silently creates an
in-memory container. New workouts then disappear on restart without a visible
warning. Expose a recovery state that makes the storage failure explicit and
prevents users from trusting transient logs as saved. Verify with an
unopenable store and a relaunch.

## P2

### GT-005 — Late watch metrics can be assigned to the wrong workout

**Status:** Implemented; paired-watch validation pending. **Code:** [`WatchBridge.swift`](../GymTrack/Services/WatchBridge.swift) (metrics cache around line 144), [`ActiveWorkout.swift`](../GymTrack/Services/ActiveWorkout.swift) (metrics consumption around line 1020).

The cached metrics are not scoped to a session ID when the next workout uses
them. Metrics arriving for A after B begins can be merged into B. Store and
consume metrics only with a matching session ID; test a late A payload while B
is active.

### GT-006 — Watch workout recording ignores the Health write setting

**Status:** Implemented; physical HealthKit validation pending. **Code:** [`WatchBridge.swift`](../GymTrack/Services/WatchBridge.swift) (mirrored `healthEnabled` around line 124), [`WatchRootView.swift`](../GymTrackWatch/Views/WatchRootView.swift) (recorder start around line 81).

The phone mirrors the user's save-to-Health preference, but the watch starts
its Health workout recorder without checking that value. Turning the setting
off does not prevent the watch's Health write. Honor the mirrored preference
on the watch and verify on physical devices.

### GT-007 — Phone Discard can cause an orphan Health workout on the watch

**Status:** Implemented; physical HealthKit validation pending. **Code:** [`WatchRootView.swift`](../GymTrackWatch/Views/WatchRootView.swift) (`syncRecorder()` around line 85).

When the phone discards, it pushes a nil session. The watch interprets that as
an ordinary finish and calls `recorder.end(title: nil)`, saving a Health workout
even though the local session was discarded. Send the end reason, or otherwise
tell the watch to discard samples for phone-initiated Discard. Verify the
resulting Health store, not only the app UI.

### GT-008 — A disconnected watch can lead to duplicate Health workouts

**Status:** Implemented; physical HealthKit and reconnect validation pending. **Code:** [`ActiveWorkout.swift`](../GymTrack/Services/ActiveWorkout.swift) (12-second wait around line 879), [`WatchRootView.swift`](../GymTrackWatch/Views/WatchRootView.swift) (`syncRecorder()` around line 81), [`HealthKitService.swift`](../GymTrack/Services/HealthKitService.swift) (persisted cleanup retry).

The phone waits about 12 seconds for the wrist workout ID, then writes its own
Health workout. A disconnected watch may later reconnect and save its workout,
leaving two records for one session. Coordinate ownership or deduplicate using
the session identity. Verify with disconnection longer than the timeout.

### GT-009 — Watch workout totals can carry into the next recording

**Status:** Implemented; two-workout watch validation pending. **Code:** [`WatchWorkoutRecorder.swift`](../GymTrackWatch/WatchWorkoutRecorder.swift) (`end` around line 156).

Ending a watch recording does not reset its average heart rate, peak heart
rate, or energy accumulators. The next workout can inherit old totals before
new samples arrive. Reset all per-workout fields when the recorder ends and
test two workouts in one process.

### GT-010 — Offline wrist completions are lost across watch relaunch

**Status:** Implemented; persistence regression passed; watch relaunch validation pending. **Code:** [`WatchConnector.swift`](../GymTrackWatch/WatchConnector.swift) (`pendingCompletions` around line 35).

Set completions awaiting phone delivery exist only in memory. If the watch app
relaunches while disconnected, its local mirror can offer those sets as open
again and the unsynced work may be lost. Persist the pending completion queue
and reconcile it by set and session ID after relaunch.

### GT-011 — Repeating an exercise creates colliding set numbers and groups

**Status:** Fixed; plan and freestyle regression passed. **Code:** [`ActiveWorkout.swift`](../GymTrack/Services/ActiveWorkout.swift) (`addExercise` around line 758), [`Entities.swift`](../GymTrack/Models/Entities.swift) (grouping around line 323).

Adding the same exercise twice during a workout, or placing it twice in a plan
day, starts the second slot's set indices at zero. Session grouping keys on
catalog ID, so both slots merge and their sets can interleave. The SwiftData
harness built two plan slots and observed one group with two index-zero sets.
Choose explicit slot identity or intentionally merge duplicates while keeping
unique, ordered set indices. Verify both plan and freestyle paths.

### GT-012 — Planned sessions ignore the suggested rep reset

**Status:** Fixed; session factory regression passed. **Code:** [`ActiveWorkout.swift`](../GymTrack/Services/ActiveWorkout.swift) (`SessionFactory.build` around lines 19–36).

The factory applies `suggestion.weightKg` but seeds reps from the previous
sets. After progression raises the weight and recommends returning to the low
end of the rep range, the new workout can open at the previous high-end reps.
The SwiftData harness produced a 12 kg / 8-rep suggestion but a 12 kg / 12-rep
set. Apply the suggested reps when building each set and test the weight-rise
case.

### GT-013 — Taking a second load nudge overwrites the first undo snapshot

**Status:** Fixed; nudge undo regression passed. **Code:** [`ActiveWorkout.swift`](../GymTrack/Services/ActiveWorkout.swift) (`apply` and `undoTakenNudge` around lines 640–675).

After a taken nudge, changing the effort answer can surface another nudge for
the same set. Taking it replaces `takenNudge.previousKg` with the already
changed weights. Undo then returns to the intermediate values instead of the
state before the first tap. Preserve the original snapshot until the whole
gesture is settled, and test take → change rating → take → undo.

### GT-014 — Some volume totals show kilograms with a pounds label

**Status:** Implemented; UI verification pending. **Code:** [`TodayView.swift`](../GymTrack/Features/Today/TodayView.swift) (volume tile around line 467), [`ProgressDashboardView.swift`](../GymTrack/Features/Progress/ProgressDashboardView.swift) (week summary around line 129).

These totals use raw kilogram volume while appending the selected unit label.
For example, 120 kg is displayed as 120 lb instead of about 265 lb. Convert
the numeric total before formatting. The selected-day chart metric already
uses `TrainingStats.Metric.value` and is correctly converted.

### GT-015 — The seven-day session total includes an eighth calendar day

**Status:** Fixed; calendar boundary regression passed. **Code:** [`TrainingStats.swift`](../GymTrack/Services/TrainingStats.swift) (`sessions(in:days:)` around line 60).

The cutoff is the start of today minus `days`, inclusive, while the daily
chart shows today and the previous six days. A session exactly seven calendar
days ago enters the headline but has no chart bucket. The SwiftData harness
found one session in the seven-day total with zero chart volume. Align the
cutoff with the displayed date buckets and test their boundary days.

### GT-016 — Merged catalog IDs lose historical progression and history

**Status:** Fixed; merged-ID history regression passed. **Code:** [`CatalogExercise.swift`](../GymTrack/Models/CatalogExercise.swift) (redirect handling around line 111), [`TrainingStats.swift`](../GymTrack/Services/TrainingStats.swift) (`history` and `lastPerformance` around lines 115 and 170).

Catalog lookup redirects an old ID to a survivor, but historical set queries
still compare raw IDs. After a merge, the survivor appears to have no past
sets, which can reset suggestions and hide exercise history. The SwiftData
harness reproduced a resolved survivor with zero returned historical sets.
Canonicalize IDs in these queries or migrate the stored IDs, and verify both
old and new entries appear as one history.

### GT-017 — Duration and unloaded bodyweight sets can appear as load records

**Status:** Fixed; tracking-mode record regression passed. **Code:** [`TrainingStats.swift`](../GymTrack/Services/TrainingStats.swift) (record candidates around line 208), [`ProgressDashboardView.swift`](../GymTrack/Features/Progress/ProgressDashboardView.swift) (record display around line 244).

The PR board uses weight-and-rep criteria for tracking modes where they do
not apply. A duration set was reproduced as `0 kg × 0 reps` with a zero e1RM;
unloaded bodyweight sets are likewise treated as zero-load records. Only
rank/display meaningful metrics for each tracking mode, with an appropriate
bodyweight policy, and test both modes.

### GT-018 — Consistency calendar marks some workout days as rest

**Status:** Fixed; zero-volume consistency regression passed. **Code:** [`ProgressDashboardView.swift`](../GymTrack/Features/Progress/ProgressDashboardView.swift) (calendar around lines 473–499).

The calendar treats a day as trained only when its weight-volume sum is
positive. A finished duration-only or unloaded bodyweight workout can be
labeled Rest. Derive trained days from finished sessions, independently of
volume, and test a zero-load completed workout.

### GT-019 — Freestyle bodyweight exercise cannot gain external load

**Status:** Implemented; phone/watch UI verification pending. **Code:** [`ActiveWorkoutView.swift`](../GymTrack/Features/Session/ActiveWorkoutView.swift) (weight control around line 1184).

The logger hides the weight editor when a bodyweight set starts at zero, so
there is no path to enter added weight. Allow weight editing for bodyweight
sets while keeping a zero-load bodyweight set easy to log. Test adding weight
to a freestyle bodyweight exercise.

### GT-020 — Backup and erase paths lose Health workout linkage

**Status:** Implemented; backup regression passed; physical Health cleanup validation pending. **Code:** [`BackupService.swift`](../GymTrack/Services/BackupService.swift) (`SessionDTO` around line 78, `wipe` around line 655).

The backup omits `healthWorkoutID`. After restore, the local session cannot
identify its original Health workout for cleanup. `wipe` and Erase All Data
also delete local sessions without deleting their linked Health workouts.
Preserve the optional ID in compatible version-2 backups and define Health
cleanup for destructive data operations. Test an older backup and a session
linked to an actual Health workout.

### GT-021 — Renamed custom exercises keep old names in plan items

**Status:** Implemented; plan rename verification pending. **Code:** [`ExerciseEditorView.swift`](../GymTrack/Features/Library/ExerciseEditorView.swift) (rename around line 270), [`ActiveWorkout.swift`](../GymTrack/Services/ActiveWorkout.swift) (session creation around line 29).

Renaming a custom exercise changes the catalog record but leaves matching
`PlanItem.name` values unchanged. New planned sessions copy that stale name
into their set logs. Update the affected plan item names or resolve display
names at session creation, then test an existing plan after rename.

## P3

### GT-022 — Weekly sessions sparkline omits today's sessions

**Status:** Fixed; current-week boundary regression passed. **Code:** [`ProgressDashboardView.swift`](../GymTrack/Features/Progress/ProgressDashboardView.swift) (`weeklySessionCounts` around line 361).

The newest weekly bucket ends at today's midnight, so a workout finished
later today increases the headline count but not the sparkline. Make the
current bucket include today and test at midnight and during the day.
