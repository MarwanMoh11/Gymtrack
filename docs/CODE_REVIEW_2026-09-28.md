# Code review, 2026-09-28

This review covers the whole working tree: HEAD `f5809ff` plus the uncommitted fix
pass for GT-001 to GT-022 (see [`CODE_REVIEW_ISSUES.md`](CODE_REVIEW_ISSUES.md)). It
looked for bugs, violations of the three data rules in `CLAUDE.md`, performance
problems, missing features and test gaps. It is written as a backlog for agents.
Read this index first. Read a detail file only for the IDs you are working on.

**Summary.** After merging duplicates, there are 95 findings: 6 P1, 29 P2, 50 P3
and 10 test gaps. The worst cluster is the watch link:
- A phone Finish, or a phone relaunch mid-workout, can permanently lose sets that
  were logged on the wrist.
- A phone relaunch can discard the watch's Health recording.
- A watch relaunch can duplicate a Health workout.

Three problems sit outside the watch link:
- The GT-020 fix deletes real Apple Health workouts when an older backup is
  restored.
- A workout started from the watch while the phone app is closed records custom
  exercises in the wrong tracking mode.
- Stale sessions are cleaned up only on a cold launch.

The earlier GT fix pass is mostly sound. Two of its fixes regressed (GT-006 and
GT-020) and five are incomplete (GT-002, GT-009, GT-012, GT-016, GT-017). GT-021
is also incomplete, and GT-011's fix caused a new regression (SESS-01). See the
table below.

## Fix progress

These fixes landed in the working tree on 2026-09-28 and 2026-09-29: all 6 P1s, all 29 P2s, all 50 P3s (DATA-14 and XC-14 only in part) and the 10 test gaps. They are uncommitted. All
three schemes build, and `scripts/test-all.sh` runs every `scripts/test-*.sh` and passes. Nothing was UI-tested
or device-tested. Treat the IDs below as done, and don't re-derive them.

| ID | Status | What changed | Test |
|---|---|---|---|
| DATA-01 | Fixed | Restore decides Health links by session `id`. For a session the device already has, the local link wins. Only workouts of local sessions that are absent from the file can be deleted. Restore now asks for confirmation before the picker opens. | `test-backup-service.sh` |
| LIB-01 | Fixed | `configureServices` loads custom and hidden exercises (`ExerciseCatalog.loadLibrary`) before the watch link comes up. New custom plan slots snapshot `trackingRaw`, and a tracking change in the editor re-tracks those slots. | `test-custom-exercise-launch.sh` |
| LINK-02 | Fixed | `WatchMirrorState` sends no mirror until the phone has stated the session. `WatchCommandCenter.configure` seeds it from the store. `pushMirror` and `connectWatch` send the session before the idle screen. | `test-watch-link-recovery.sh` |
| LINK-03 | Fixed | `WorkoutSession.isStale` and `closeIfStale` hold the one twelve-hour rule. It runs on cold launch, on warm resume, on both watch start routes and in `pushMirror`. `close(at:)` ends a stale session at its last set. | `test-watch-command-reliability.sh`, `test-watch-link-recovery.sh` |
| WATCH-01 | Fixed | `WatchSessionTombstone` persists the session that was ended on the wrist. A stale mirror or a relaunch can't revive or re-record it. The phone replaces a linked workout only if the phone itself wrote it (`WatchWorkoutLink`). | `test-watch-session-tombstone.sh` |
| LINK-01 | Fixed, phone side only | When `close` deletes unlogged rows, `DroppedSetMemory` records each row's identity: UserDefaults, 7 days, 200 rows, never exported. A late `.logSet`, or a late finish batch, recreates the row only in a session that is closed, still exists and lacks it, and only when the wrist's time is not after `endedAt`. A late undo forgets or removes the row. `ActiveWorkout.apply` passes unknown set IDs on instead of swallowing them. No protocol change, so older watch builds are covered too. | `test-late-wrist-logs.sh` |
| WATCH-06 | Fixed | `WatchRecordingRules.stillWanted` is checked after every `await` in a start, and an `end()` during a start cancels it. | `test-watch-recording-rules.sh` |
| WATCH-07 | Fixed | The workout session runs whether or not saving to Health is on, and every end discards when it is off. The toggle no longer kills the runtime. Device check needed: `discardWorkout()` does not remove samples already added, so heart-rate and energy samples probably stay in Health. | `test-watch-recording-rules.sh` |
| WATCH-08 | Fixed | Callbacks from a closed builder are ignored (P1 round). Session-delegate callbacks are matched to the current session (P2 round). | |
| WATCH-09 | Fixed | `WatchAppDelegate` handles `handleActiveWorkoutRecovery` and `handle(_ workoutConfiguration:)`. The session being recorded is persisted as `WatchRecordingRecord`. Device-only; unverified. | `test-watch-recording-rules.sh` |
| WATCH-03 | Fixed | `WatchFinishBatch.endedAt` (optional) is stamped at the tap. The phone closes the session at that moment, clamped between the last set and now. | `test-watch-link-ordering.sh` |
| LINK-04 | Fixed | The watch drops live metrics it can't send straight away. A closed session accepts metrics only from a Finish, or from a report that carries the Health ID. | `test-watch-link-ordering.sh` |
| LINK-05 | Fixed | A repeated log is a no-op. `.undoSet` carries an optional stamp, and an undo that arrives before its log blocks that log. While a backlog exists, the watch queues every command behind it. | `test-watch-link-ordering.sh` |
| HK-02 | Fixed | Health activities follow the order sets were logged in. | `test-health-write.sh` |
| HK-03 | Fixed | The summary and the session detail page backfill heart rate when opened, and again on foreground. A later pass replaces a reading only when it has more samples. | `test-health-write.sh` |
| XC-02 | Fixed | `recordToHealth`, `saveWorkout` and the backfill check liveness after every `await` (`isGoneFromStore`, `isGone(fromStore:)`). | `test-health-write.sh` |
| DATA-02 | Fixed | Restore never touches Health. Erase keeps Health workouts unless the user picks a second, explicit button. | `test-backup-service.sh` |
| DATA-03 | Fixed | Restore skips warm-up sets. | `test-backup-archive-integrity.sh` |
| DATA-04 | Fixed | Export: `seconds` is left out on reps sets, `reps` on timed sets, targets of 0 or less, and empty notes; the DTO fields are optional. Source: new rows seed `seconds` only when timed and `reps` only when not. Off-plan rows get 0-0 targets unless the plan has a range for that exercise. | `test-backup-archive-integrity.sh`, `test-logger-entry.sh` |
| STATS-04 | Fixed | `BodyMetric.healthSampleID` keeps the sample's UUID; it is optional and needs only a lightweight migration. Long-press the reading for "Delete" and "Recent weigh-ins", which lists entries with swipe-to-delete. A same-day correction deletes the old sample. A sample from another source is never deleted. `deleteWorkout` returns true for a workout that is already gone. | `test-body-weight-correction.sh` |
| LIB-03 | Fixed | `LoadScaleBook` canonicalises every ID on read and write, reads both spellings, and clears both. This covers DATA-11 too. | `test-load-scale-merges.sh` |
| STATS-01 | Fixed | `TrainingStats.startOfDay(_:from:calendar:)` walks days in a DST-safe way. It drives the streak, the windows, the daily buckets, the weekly counts and `ConsistencyGrid`. | `test-training-stats-calendar.sh` |
| STATS-03 | Fixed | `Plan.nextDay(on:after:)`: a pinned match wins, and otherwise the next unpinned day in rotation after the last finished `planDayID`. All seven call sites use it, and Today says "NEXT UP" for a rotation day. | `test-plan-rotation.sh` |
| STATS-05 | Fixed | A Finish with no sets becomes a Discard on every route (phone, headless, `RootView`, watch idle auto-finish). `TrainingStats.isTrained` keeps empty sessions out of the streak, the windows, the weekly counts, Today, the widget and the watch. | `test-session-lifecycle.sh`, `test-training-stats-calendar.sh` |
| WATCH-10 | Fixed | After 90 minutes with no set logged or started, the watch finishes the session at its last set, or discards it when nothing was logged, with no prompt. A phone stale close pushes `.finished` or `.discarded` and writes Health for sessions that kept sets (`WatchCommandCenter.retire`). | `test-watch-idle-finish.sh`, `test-session-lifecycle.sh` |
| LOG-03 | Fixed | "Edit numbers" in a logged row's long-press menu corrects weight, reps and seconds in place. It leaves `completedAt`, `startedAt`, `rpe` and HR alone (`ActiveWorkout.correct`). | `test-logger-corrections.sh` |
| LOG-02 | Fixed | Remove takes the last unlogged row, preferring a working set, and is hidden when there is none. | `test-logger-corrections.sh` |
| LOG-01 | Fixed on the phone | Opening a finished exercise to review it (`openFromQueue`) doesn't move the working position. On the watch, tapping a finished exercise still moves it. | `test-logger-corrections.sh` |
| SESS-02 | Fixed | Only a later working set of the offer's own exercise settles the offer. Lifting at the offered rung counts as taken, and undoing the settling set restores the offer. | `test-logger-entry.sh` |
| XC-01 | Fixed | `StepperEntry` rejects non-finite, negative and over-ceiling input (reps 100, seconds 3,600, weight 500 kg / 1,100 lb, matching the watch) and converts with `Int(exactly:)`. | `test-logger-entry.sh` |
| XC-03 | Fixed | Restore validates an archive before deleting anything: weekday 1-7, reps 0-60, and finite, non-negative weights and seconds. It never clamps, and a backwards range is allowed. Weekday names and the day editor's range can't trap. | `test-backup-archive-integrity.sh` |
| SESS-01 | Fixed | Each repeated slot has its own progression and history (`SessionFactory.slotPositions`), and `carryLoadForward` stops at the end of the slot. | `test-active-workout-structure.sh` |
| STATS-02 | Fixed | Load goes up only when last time had at least `targetSets` sets at the top load. After a deload or a repeat, reps reset to the prescription. | `test-progression-suggestion.sh` |
| LIB-02 | Fixed | No loadable equipment means bodyweight. Exactly four exercises change. A last load of 0 never climbs. | `test-progression-suggestion.sh` |
| LIB-04 | Fixed | A 0-0 slot moved into a reps mode gets 8-12, and the progression reads 0-0 as no prescription. | `test-custom-exercise-launch.sh` |
| STATS-06 | Fixed | `ProgressHistory` builds per-session digests once per history change; a metric or window tap reads no set (about 1.6 ms instead of 550-680 ms at 7,500 sets). Every figure matches the old code. | `test-progress-history.sh` |
| DATA-05 | Fixed | Sessions export `planDayID` and sets export `id`. Restore keeps both and mints a set ID only when one is missing. A repeated set ID is rejected before anything is wiped. | `test-backup-export-fidelity.sh` |
| DATA-06 | Fixed | Every exported array has a stable order with full tie-breaks (sessions by `startedAt`, sets by `precedesInSession`, days and slots by `order`). Two exports of the same store are byte-identical. | `test-backup-export-fidelity.sh` |
| DATA-07 | Fixed | The export records `timeZone`, `appVersion` and `appBuild`. All three are optional, and `version` stays 2. | `test-backup-export-fidelity.sh` |
| DATA-09 | Fixed | New `effectiveLoadScales` lists every resolvable exercise's scale, each marked `source: correction` or `derived`. It reads the same rows as `loadScales`, so the two can't disagree. | `test-backup-export-fidelity.sh` |
| WATCH-12 | Fixed | The 4 Hz ticker is gone. One timer fires at `endsAt`, and the countdown is a `TimelineView` subview. A mirror whose rest ended long ago clears without a buzz. A local rest still buzzes if its timer wakes up to 60 s late (`WatchRestRules.buzzesOnExpiry`). The same end date never buzzes twice. | `test-watch-logger-rules.sh` |
| WATCH-13 | Fixed | Log set, Start set and Undo last set ignore a second tap within 0.6 s (`WatchLoggerRules.acceptsSetTap`). | `test-watch-logger-rules.sh` |
| WATCH-14 | Fixed | The effort question is a compact card below Log set, not a takeover. After 10 s it falls back to "Rate last set". Skip and Undo on the card are gone. | `test-watch-logger-rules.sh` (rules only) |
| WATCH-15 | Fixed | Every saved wrist workout carries the brand, indoor flag and external UUID. Title, sets and volume are written only when they're for this session and non-zero. | `test-watch-logger-rules.sh` |
| LOG-01 | Fixed on both sides | On the watch, a finished exercise opens a read-only review and sends nothing to the phone. | `test-watch-logger-rules.sh` |
| LOG-04 | Fixed | `discard()` reads `session.id` before the delete (earlier round). | none |
| LOG-05 | Fixed | Undoing an old set stops the rest only if it belonged to that set or its drops. | `test-workout-model-fixes.sh` |
| LOG-09 | Fixed | `removeContinuation` brings back the rest `continueSet` cancelled, unless that rest has already ended or another rest is running. | `test-workout-model-fixes.sh` |
| LOG-10, SESS-06 | Fixed | `WorkoutSession.settleStarts` drops a start that is implausibly long (`SetLog.longestPlausibleLength`) or overtaken by another set's log. Only one set can be under way at a time. The same rules apply on the headless `.logSet` and `.announceStart`. | `test-workout-model-fixes.sh` |
| SESS-08 | Fixed | `pruneDeletedHistory` removes a deleted past session from the running workout's history, PR baseline and "last time" hints. | `test-workout-model-fixes.sh` |
| LOG-07 | Fixed | The summary ranks records per kind (hold, reps, load) and labels them "15 reps", "75s" or "+10 kg x 5", never "0 kg x 15". | `test-record-ranking.sh` |
| LOG-13 | Fixed | The summary's unscoped `@Query` is gone. Records are computed in `.task(id:)`, keyed on session ID and set count, so typing a note costs nothing. | `test-record-ranking.sh` |
| STATS-08 | Fixed | One ranking, `TrainingStats.standing(of:)`, used by both the card and the logger trophy. Epley is capped at 12 reps, a tie keeps the earliest date, and each row is one set. Bodyweight gets two rows: unloaded reps and added load. `records` fell from 529 ms to 91 ms at 7,500 sets. | `test-record-ranking.sh`, `test-training-stats-history-records.sh` |
| HK-06 | Fixed | A history delete queues the workout for cleanup once the delete saves, and the queue retries it. | `test-health-cleanup-queue.sh` |
| HK-07 | Fixed | `HealthCleanupQueue.drain` runs on every foreground. An entry is dropped once its workout is gone, and a single session is fetched per entry. | `test-health-cleanup-queue.sh` |
| HK-13 | Fixed | `WatchCommandCenter.retire` writes a stale session that kept sets to Health (earlier round). | none |
| XC-02 residue | Fixed | A late watch workout ID for a deleted session is queued for deletion (`discardOrphanWorkout`). Nothing is queued if a restore has put the session back. | `test-watch-orphan-workout.sh` |
| DATA-12 | Fixed | `ScreenAwakeRules` keeps the screen awake only while the setting is on, a workout is open (minimised counts) and the app is active. `RootView` applies it in one `.onChange(initial: true)`. The default stays on. | `test-p3-misc.sh` |
| HK-11 | Fixed | The phone asks to read heart rate, active energy, body mass and workouts, and to share body mass and workouts. Resting heart rate, basal energy, activity summaries and energy sharing are gone. Grants already given aren't revoked. | `test-p3-misc.sh` (compares requested with used types) |
| HK-12 | Fixed | An intent posts an in-process announcement after it writes its note, and `RootView` reads the note then as well as on activation. `PendingActionHandoff.Inbox` stays closed until the first `.task` has adopted any unfinished session. A note is taken only once. | `test-p3-misc.sh` |
| SESS-07 | Fixed | `RestChimeRules`: a rest found over more than 2 s late, whose notification already announced it, ends silently. That is deliberately shorter than the watch's 60 s, because the watch posts no notification. `RestTimer.init` cancels a pending "Rest over" left by a process that died. Nothing persists a rest's end, so a rest isn't restored. | `test-p3-misc.sh` |
| STATS-09 | Fixed | `TrainingStats.completedToday`: Today is done only for a trained session that started today on a day of the active plan. The scheduled day wins, but a deliberate swap counts too. A freestyle session or last night's tail leaves the scheduled day on the card. With nothing scheduled, any trained session counts. | `test-calendar-week-stats.sh` |
| STATS-10 | Fixed | One calendar week (`TrainingStats.weekInterval`, `sessionsThisWeek`) for Today, the widgets and Progress's "This week". The heat map and weekly-target verdicts read the last 7 days, and now say so. The consistency grid starts on `firstWeekday`. | `test-calendar-week-stats.sh`, `test-progress-history.sh` |
| STATS-11 | Fixed | Weigh-ins are spaced by date, and the change says its span ("+1.2 kg over 6 weeks"). | `test-calendar-week-stats.sh` |
| `dayLabel` (STATS-01 residue) | Fixed | `ProgressDashboardView.dayLabel` counts calendar days (`TrainingStats.dayCount`). The old code read yesterday as "today" across Cairo's DST change. | `test-calendar-week-stats.sh` |
| LOG-08 | Fixed | The whole session counts efforts. `ActiveWorkout.completedCount` and `totalCount` skip drop and cluster rows, so the logger's header and tick bar, Today, the dock, the finish prompt, the Live Activity and the widget all agree with the card and the summary. The review had the direction backwards: the dock, the Lock Screen and the widget were the ones counting rows. | `test-exercise-removal.sh` |
| LOG-11 | Fixed | The open row with steppers has no long-press menu, so holding − can't lift one. A pending drop row has a small minus button in its header instead. "Separate from the set above" is no longer on that row's long press, but VoiceOver keeps every action. | reading only |
| LOG-15 | Fixed | A queue row's long-press menu offers "Remove from workout", but only for an exercise added this session with no logged row (`canRemove`). Removing it deletes the unlogged rows and the note, restores a rest that a start on those rows cut short, and clears the pick. | `test-exercise-removal.sh` |
| LIB-07 | Fixed in the logger | When the catalog no longer resolves an exercise, the weight caption is plain text and the info button is hidden. | reading only |
| DATA-08 | Fixed | Each set exports its `effort` as the answer given (easy, solid, hard, allOut), matched exactly through `SetFeel.answer(forStored:)`. A top-level `effortScale` says that `rpe` is a bucket code, and `settings.trackRPE` exports the setting as it is at export time. `rpe` stays, for restore. `AI_COACH.md` says what each field means. | `test-session-provenance.sh` |
| DATA-10 | Fixed | `WorkoutSession` records where heart rate and energy came from (`watchWorkout` or `healthSamples`) and how many heart-rate readings there were. The backfill keeps heart rate only with at least 12 readings, about one a minute, spanning half the session. It counts energy only from the wrist, which excludes phone pedometer energy, and under the same coverage rule. Thin data is not stored. Older sessions export no source key, and energy under 1 kcal is not exported. | `test-session-provenance.sh` |
| HK-08 | Fixed | `pushMirror` calls `WidgetPublisher.publishHeadless` once per headless command. It restamps the widget snapshot and syncs the Live Activity, and stands down while a logger is publishing. A session older than `Running.staleAfter` (12 h) stops showing as running, even mid-day, and the widget timeline adds an entry at that moment. | `test-widget-publishing.sh` |
| HK-09 | Fixed | `widgetKindsToReload(replacing:)` reloads nothing when the encoded snapshot is unchanged, only Today for a change to the running session, and both kinds otherwise. It compares against the stored snapshot, so a freshly woken process doesn't reload everything. | `test-widget-publishing.sh` |
| HK-10 | Fixed | The Dynamic Island rest ring drains: `RestProgress.fraction` has the sign the right way round. | `test-widget-publishing.sh` |
| DATA-13 | Fixed | `RootView` pushes the mirror when the unit or rest auto-start changes. The mirror already carried both. | reading only |
| LINK-06 | Fixed | `WatchCommandDelivery` travels beside each command as optional payload keys, so no enum case changes shape. A start carries `sentAt`, and the phone refuses one older than 120 s. Add, focus and rest commands carry the session ID, and the phone refuses one that names a session other than the open one. Either refusal pushes the mirror, so the wrist isn't left waiting. A command with no rider, from an old watch, applies as before. The watch's waiting copy now says two minutes. | `test-watch-link-delivery.sh` |
| LINK-07 | Fixed | The headless mirror sets an optional `restUnknown`, and the wrist then keeps its own rest instead of clearing it. An old watch behaves as before. | `test-watch-link-delivery.sh` |
| LOG-12 | Fixed | The logger builds its groups once per `body` pass and passes them down, so nothing is cached between passes and nothing can go stale. The queue row reads a pending weight itself, so a stepper step no longer redraws the logger. The header reads heart rate itself, and `adoptWatchMetrics` writes only fields that changed. `RestTimer` stores no `remaining`: one timer fires at `endsAt`, and the dock and rest bar count down in a `TimelineView` (`RestCountdown`), so nothing observable changes during a rest. The group lookup went from 0.42 s to 0.02 s over 200 passes. | `test-rest-render.sh`, `test-logger-groups.sh` |
| LIB-05 | Fixed | Search keeps the literal words beside the aliased ones, and a typed word matches any alias key of three or more letters that it begins, so "calv", "fli" and "ham" (Hammer Curl kept) all find results. The empty state no longer offers "Add" while filters hide a real match. | `test-library-fixes.sh` |
| LIB-06 | Fixed | `PlanDay.nextItemOrder` is one past the maximum, and `removeItems` renumbers the survivors densely. | `test-library-fixes.sh` |
| LIB-09 | Fixed | Onboarding has "Start from blank". `PlanSettingsView` has a confirmed "Delete routine", refused while a session from that routine is open; the next routine becomes active. History is untouched, because a session holds `planDayID` and `planName` with no relationship to the plan. Restore doesn't validate `planDayID`, so later backups still restore. The unit copy is reworded. | `test-library-fixes.sh` |
| XC-11 | Fixed | `StepperEntry` normalises Arabic-Indic and extended Arabic-Indic digits and the Arabic decimal separator, and still rejects everything else. | `test-library-fixes.sh` |
| LIB-07 residue | Fixed | `DayEditorView`'s "Marked in" chip is plain text when the exercise no longer resolves. | reading only |
| DATA-14 | Partly fixed | Export encodes and writes off the main actor (`exportOffMain`, byte-identical). Restore reads, decodes and validates off it (`restoreOffMain`), then applies with one save on main. Settings shows progress and disables Export, Restore, Erase and Done while one runs. Erase deletes Health workouts in one `store.delete`, only those this app or its watch app wrote (`deleteWorkouts(ids:)`). At 300 sessions of 25 sets, the snapshot (about 650 ms) and the restore apply (about 800 ms) still run on main. Moving them needs a background `ModelContext`. | `test-backup-off-main.sh` |
| LOG-14 | Fixed | VoiceOver labels on the icon-only controls: undo a set, end rest, the stepper keys, plan and Today controls, the progress calendar cells. Theme fonts at 11-13, 15-17, 20 and 22 pt map to text styles, so they scale while the default size renders as before. 14 pt, 8-10 pt and hero numerals stay fixed. The logger and dock cap at xxxLarge, the widgets and Live Activity at large, and the watch stays fixed. `textTertiary` opacity 0.38 to 0.46, which takes it from 3.6:1 to 4.6:1 on cards. | reading only |
| LINK-08 | Fixed | `WatchCommandCenter` fetches open sessions with `endedAt == nil`, and sessions and plan days by ID with fetchLimit 1. It passes one fetch down per command, and `closeStaleSession` no longer fetches history. `WatchSessionRecovery` fetches only finished sessions within 24 h of an open candidate. RootView's idle mirror lives in `WatchIdleSync`, which recomputes only when its own queries change. The HealthKitService lookups were already predicated. | `test-watch-command-center.sh` |
| LINK-09 | Fixed | `WatchCommandCenter` uses `container.mainContext`, so the headless path and the UI share rows, and late finish batches reach an open summary. | `test-watch-command-center.sh` |
| XC-14 | Partly fixed | WCSession callbacks hop through `DispatchQueue.main.async`, which keeps arrival order, in `WatchBridge` and `WatchConnector`. `ExerciseCatalog`'s state and `LoadScaleBook`'s overrides sit behind an `NSLock`, and `RestTimer` is `@MainActor`. | `test-watch-mirror-reconciliation.sh` |
| STATS-13 | Built | `Services/LiftTrends.swift` and `LiftTrendsCard`. A lift needs at least 4 sessions over 14 or more days in the last 8 weeks. It is moving, flat or sliding by the mean best estimated 1RM of its recent half against its earlier half, and a change within one load rung is flat. Drop rows are excluded. The card shows at most 5 rows, most recent first, hides when nothing qualifies, and is not exported. | `test-lift-trends.sh` |
| XC-04 | Closed | Tests drive every data-changing command through `applyHeadless`, the `uiHandler` routing, the single context, and overlap recovery with the real `WatchSessionRecovery`. | `test-watch-command-center.sh` |
| WATCH-16 | Closed | `WatchMirrorReconciliation` holds `accepts`, `mayReconcile(fromCache:)` and `reconcile`, pulled out of `WatchConnector`. The save-or-discard rule was already `WatchRecordingRules.discardsOnWristFinish`. | `test-watch-mirror-reconciliation.sh` |
| XC-05 | Closed | The pure decisions `PhoneWorkoutWrite`, `WorkoutDeletionPlan`, `CleanupRelink` and `CleanupPassGate` live in `SetHeartRate.swift`, and `HealthKitService` calls them. | `test-health-decisions.sh` |
| HK-15 | Closed | New `asOf` cases. Segmentation, the cleanup queue and `RestProgress.fraction` were already covered. `ContentState.restProgress` is ActivityKit-only and calls the tested function. | `test-snapshot-asof.sh` |
| STATS-12 | Closed | Every suggestion branch, the streak, and the week and streak in Kiritimati and Pago Pago with both week starts. | `test-stats-gaps.sh` |
| XC-06, XC-10, LIB-10 | Closed | Rep reset on plain slots. A field-exhaustive unlog check that fails when a new stored field is left unclassified. Export, restore, export again, compared path by path in kg and lb. lb ladders, an lb scale through `LoadScaleBook`, and custom-exercise edits reaching search. | `test-library-data.sh`, `test-unlog-no-trace.sh`, `test-backup-round-trip.sh` |
| XC-09 | Mostly closed | `scripts/test-all.sh` runs every script with a 240 s timeout each and logs to `build/test-logs/`. The AppSettings stubs now default auto-rest and watch auto-launch to on, as the app does, and `test-stub-drift.sh` fails if they drift again. Every script compiles the real `WatchSessionRecovery`. There is still no Xcode test target: that needs `project.pbxproj`, so it is for the user to add in Xcode. | `test-all.sh`, `test-stub-drift.sh` |
| XC-08 | Closed | The stubs' unit was already settable. New lb runs for backup, progression, opening loads, ladders, snapping and formatting. | `test-pound-backup.sh`, `test-pound-load.sh` |
| XC-01 decision | Fixed | The user chose a 1,000 kg ceiling (2,200 lb) on phone and watch: `LoadScale.displayCeiling`. | `test-pound-load.sh` |
| WATCH-14 decision | Fixed | The logger doesn't scroll to the top while the effort card waits for an answer (`WatchLoggerRules.scrollsToTop`). | `test-watch-wrist-leftovers.sh` |
| LOG-10 residue | Fixed | A headless `.focusExercise` clears a start. Finish batches and `restoreDroppedSet` apply the cap and overtaken rules; `SessionClosing.swift` restates them, and a test pins them equal to the logger's, so change both together. `configure` repairs, once, stored starts that fail the cap. | `test-late-wrist-log-repairs.sh` |
| XC-02 residue | Fixed | `.finish` and `.finishSession` queue a missing session's workout ID through `discardOrphanWorkout`. | `test-late-wrist-log-repairs.sh` |
| LINK-05 residue | Fixed | Phone: `DroppedSetMemory` records each stamped wrist log it applied, and a batch replay skips it, so a set the phone undid stays undone. Wrist: `WatchPendingActions` stamps each undo, and reconciliation clears one the phone refused. | `test-late-wrist-log-repairs.sh`, `test-watch-wrist-leftovers.sh` |
| LINK-01 residue | Partly fixed | A stamped undo keeps the dropped row and blocks its stamp; a re-log with a new stamp restores it. | `test-late-wrist-log-repairs.sh` |
| LOG-01 residue | Fixed | `WatchConnector.focus(on:)` ignores a finished exercise (`WatchLoggerRules.allowsFocus`). | `test-watch-wrist-leftovers.sh` |
| SESS-01, SESS-02 residue | Fixed in the model | The nudge's offer, count and apply belong to the slot the offer was made in, and offers are kept per exercise, so a superset partner's rating doesn't drop one. The undo of a set restores the weights it carried onto later rows unless they were typed over. | `test-slot-offers.sh` |
| HK-08 residue | Mostly fixed | `ActiveWorkout`'s current-set properties read `SessionPosition`, and `activityState` goes through `WorkoutLiveActivity.state(for:)`. | existing scripts |
| LINK-08 residue | Fixed | `SessionFactory.lastPerformances` sorts the history once and stops when every needed exercise is found. | existing scripts |
| DATA-05 residue | Fixed | Restore refuses a repeated plan, day or session ID before the wipe. | `test-backup-ids-tracking.sh` |
| trackingRaw | Fixed | Restore stamps a custom exercise's slots with that exercise's tracking, and `RootView.syncCustomExercises` stamps unstamped custom slots. | `test-backup-ids-tracking.sh`, `test-misc-leftovers.sh` |
| HK-06 residue | Fixed | `CleanupAttemptLedger`: five refusals at least 15 minutes apart and the delete is given up; a locked phone costs nothing; given-up IDs are kept (at most 50) and shown in Health & Watch settings with Retry. Cleanup also retries on `protectedDataDidBecomeAvailable`. | `test-health-leftovers.sh` |
| DATA-10 residue | Fixed | Wrist energy is summed by `HKStatisticsQuery(.cumulativeSum)` over watch sources, which de-duplicates. | `test-health-leftovers.sh` |
| STATS-09 residue | Fixed | The widgets' done card uses `completedToday`. | `test-widget-snapshot.sh` |
| LOG-13, LOG-12 residue | Fixed | The summary fetches only completed sets of its own exercises (`SummaryRecords`). `WatchBridge` assigns `liveMetrics` only when a merge changes it (`LiveMetricsMerge`). | `test-misc-leftovers.sh` |
| Custom rename | Fixed | The rename's reach into plan slots is `ExerciseRename`, and `ExerciseEditorView.save()` calls it. | `test-misc-leftovers.sh` |
| LOG-14 residue | Fixed | The continuation glyph has a label. `textTertiary` is 0.50: 4.7:1 on a selected card, about 5:1 on a plain one. | reading only |
| Unproven tests | Closed | The LINK-09, overlap-recovery, lift-trend drop-row and unlog tests each fail when their fix is reverted in a scratch copy. | n/a |
| Wave 7 wiring | Fixed | The logger card reads its offer, plan slot, last time and previous set per slot and per exercise. `Prefill` is shared, and a headless undo restores the weights its log carried onto later rows. A re-delivered wrist log that the phone already heard is ignored on both the UI and headless paths (`wasHeardLog`). | `test-wrist-redelivery-undo.sh` |

P2 follow-up round (closing gaps the fixes above left in files their authors did not own):
- HK-03: `RootView` runs `backfillRecentSessions` on launch and on every foreground.
- XC-02: `WatchCommandCenter.recordToHealth` checks liveness after every `await`, and `applyLateMetrics` no longer writes to a deleted session.
- SESS-01: a set logged headlessly carries its load only within its own slot (`laterRowsInSlot`).
- `startWatchApp` is gated on workout sharing permission, not on the save setting.
- LIB-03: the export writes load scales once per movement, under the canonical ID. `addExercise` matches cards by canonical ID.
- LOG-03: undoing a set undoes the logged drops directly below it too.
- STATS-01: `SharedStore.asOf` finds yesterday in a DST-safe way.
- STATS-03: the widgets and the watch say NEXT UP on a rotation day (optional `todayIsRotation`).
- `docs/AI_COACH.md` now says which export fields are written only when they apply.
Tests: `test-watch-headless-follow-up.sh`, plus three scripts from the second agent.

Still open after wave 6 (2026-09-29):
- Decided by the user: a 1,000 kg ceiling; Easy on an off-plan set still offers the next rung; a start past `longestPlausibleLength` is still dropped, not clamped; the effort card stays in view (see the rows above).
- Decision waiting on the user: a note pruned at close stays pruned when a late wrist set brings its exercise back. Keeping it means storing the note's text in `DroppedSetMemory`, or pruning later.
- Needs a device:
  - WATCH-07: with saving off, samples already added may stay in Health.
  - STATS-04: without read access, a watch-written workout may count as removed.
  - WATCH-10: `endCollection` in the past should trim later samples.
  - HK-06: the locked-phone retry and the Settings line. DATA-10: energy with two watch apps recording.
- Won't fix:
  - DATA-08: a per-session "effort asked" flag would be a guess.
  - LINK-01's Health part: a saved `HKWorkout` can't be updated, and delete-and-resave would drop the watch's samples.
- Code:
  - DATA-14: moving the snapshot and restore apply to a background `ModelContext` cut main-thread time to about 1 ms and 10 ms, but a later export after a restore trapped in SwiftData (`ModelSnapshot` `_FullFutureBackingData<SetLog>`). It was reverted. It needs chunked work on main with yields, or the trap's cause.
  - XC-14: `ExerciseCatalog` and `LoadScaleBook` can't be `@MainActor` until their nonisolated callers move. No Swift 6 build was tried.
  - LINK-01 and LINK-05: an unstamped undo followed by a re-log still loses the re-log. On the wrist, a phone undo followed by a wrist Finish is covered only once a mirror has arrived.
  - LOG-10: stored starts overtaken by another set's log aren't repaired, because arrival order was never stored.
  - SESS-02: offers and the undo memory are lost on relaunch.
  - HK-06: a refusal because write access is off counts against the cap. An entry whose `relinkSession` never succeeds is never given up (needs `HealthCleanupQueue.drain`).
  - HK-08: `WorkoutSession.staleAfter` still restates `GymTrackSnapshot.Running.staleAfter`; a test pins them equal.
  - LOG-14: 14 pt, 9-10 pt, hero numerals and icons sized with `.font(.system(size:))` don't scale.
  - DATA-05: custom exercise IDs aren't checked for uniqueness on restore.
  - STATS-09: the widgets' fallback to `plans.first` wasn't checked against Today's `activePlan`.
  - `summaryRecords(for:history:)` is no longer called by the app; only a test uses it.
  - The headless carry-forward memory lives in memory only, so a carry the phone logger made and the wrist undid headlessly is not restored.
  - `ActiveWorkout.pendingNudge` and `takenNudge` remain only for four test files; the app calls the per-exercise versions.

## How this review was done

Nine reviewers each read one area in full and traced calls across the boundaries
into other areas. A tenth pass re-checked the five watch-link claims that were
rated likely rather than confirmed. All five held, two were narrowed and one was
downgraded; see [VERIFY.md](code-review-2026-09-28/VERIFY.md). The coordinator
also re-traced LIB-01, LINK-02, LINK-03, XC-01, XC-03 and DATA-01 itself, and
reproduced one SwiftData behavior in a scratch harness. The raw findings (116 in
all) are in [`code-review-2026-09-28/`](code-review-2026-09-28/), one file per
area:

| Prefix | Area | Detail file |
|---|---|---|
| SESS | `ActiveWorkout`, `Entities`, `SessionClosing`, `RestTimer`, `SetFeel`, `SetLeadIn` | [SESS.md](code-review-2026-09-28/SESS.md) |
| LOG | Phone logger UI: `Features/Session/*` | [LOG.md](code-review-2026-09-28/LOG.md) |
| LINK | Phone side of the watch link, `RootView`, `GymTrackApp` | [LINK.md](code-review-2026-09-28/LINK.md) |
| WATCH | `GymTrackWatch/*` and the shared link types | [WATCH.md](code-review-2026-09-28/WATCH.md) |
| HK | HealthKit, per-set heart rate, widgets, Live Activity, intents | [HK.md](code-review-2026-09-28/HK.md) |
| STATS | `TrainingStats`, Progress, Today | [STATS.md](code-review-2026-09-28/STATS.md) |
| DATA | Backup and export, Settings, readiness of the AI-coach export | [DATA.md](code-review-2026-09-28/DATA.md) |
| LIB | Catalog, Library, load scales, Plans, Onboarding | [LIB.md](code-review-2026-09-28/LIB.md) |
| XC | Cross-cutting sweeps, design system, test suite | [XC.md](code-review-2026-09-28/XC.md) |

Several reviewers found the same defect. Each duplicate group has one canonical ID
below, and its aliases are listed with it. The severity in this index is the one
to use. Where a detail file disagrees with it, this index wins.

**Severity.** P1 is data loss or corruption, a workout applied to the wrong session,
a crash, or a Health record that is wrong or duplicated. P2 is materially incorrect
behavior or record, a broken feature, a real performance problem, or a data-rule
violation. P3 is a smaller defect, a minor performance issue, or a nice-to-have.

**Confidence.** *Confirmed* means traced end to end in code, and some findings were
also reproduced in a scratch harness. *Likely* means the code path is traced but
the trigger depends on timing or on device behavior. *Speculative* means it needs
the check named in the detail file before anyone acts on it.

**State at review time.** All three schemes (GymTrack, GymTrackWidgets and
GymTrackWatch) built in Debug with zero warnings. All seven `scripts/test-*.sh`
passed. Nothing was run on a simulator or a device. Every HealthKit claim is from
code and Apple's documented behavior only, because the simulator cannot grant
Health access.

## Notes for the agent fixing these

- The three data rules in `CLAUDE.md` are the acceptance criteria. Several fixes
  below are about honesty, not crashes: no inferred value stored as measured, no
  trace of an undone action, and no new taps in the logger.
- Settled product decisions stay settled. Warm-ups, recovery or readiness data,
  bodyweight at session time, and per-set notes are all rejected. Backup `version`
  stays 2, and every new field is optional.
- **SwiftData check, reproduced on the macOS 26 SDK.** After `context.delete(x)`
  and `context.save()`, reading `x`'s already-loaded attributes does not trap. It
  returns the old values, `x.isDeleted` is `false`, and `x.modelContext` is `nil`.
  To tell whether a held model is still alive, check `modelContext == nil`.
  `isDeleted` alone misses a saved deletion. iOS 17.0 was not tested and may be
  stricter.
- Protocol changes on the watch link must decode in both directions between an
  old watch build and a new phone build, and the reverse. Add optional fields
  only, and prove the decode in `Tests/WatchCommandReliabilityTests.swift`.
- Before calling a change done, build all three schemes and run every
  `scripts/test-*.sh`. XC-09 proposes a `scripts/test-all.sh` that does both.
- Before starting, check for peer sessions with ListAgents and
  `git worktree list`. Several of these findings touch the same files: the link,
  `ActiveWorkout` and `HealthKitService`.

## Status of the earlier review's fixes (GT-001 to GT-022)

| GT | Verdict | Where it stands |
|---|---|---|
| GT-001 | OK | Session-scoped Finish and Discard are correct on both routes. There is no regression test for the routing (XC-04). |
| GT-002 | **Incomplete** | A wrist Finish now carries its batch. A Finish tapped on the phone still loses wrist logs that are still queued (LINK-01). |
| GT-003 | OK | Restore is one transaction. The Health deletion that now follows the restore is a new defect (DATA-01). |
| GT-004 | OK | There is no in-memory fallback any more. A deterministic failure, such as a failed migration, can never succeed on Retry, and the recovery screen offers no other way out, such as exporting the raw store or resetting. |
| GT-005 | OK | Metrics are scoped by session ID. Ordering *within* one session is still open (LINK-04). |
| GT-006 | **Regression** | The watch honors the setting by never starting an `HKWorkoutSession`, and that removes its background runtime, the rest-over haptic and heart rate (WATCH-07). |
| GT-007 | OK | Discard pushes `.discarded`, and the watch saves only a matching finish. |
| GT-008 | OK, with gaps | The fallback cleanup queue works, but it retries only on a cold launch and never drops entries whose workout is already gone (HK-07). One separate duplicate path exists (WATCH-01). |
| GT-009 | **Incomplete** | The fields are reset in `end()`, but a late delegate callback from the ended builder fills them again (WATCH-08). |
| GT-010 | OK | The pending queue persists. A nil mirror still wipes it (LINK-01). |
| GT-011 | OK, with a regression | Slots are normalised. The per-slot loads it protects are flattened, and repeated slots skip progression (SESS-01). |
| GT-012 | **Incomplete** | Reps reset only on `.increaseWeight`, not on `.deload` or `.repeatLoad` (STATS-02). The fixed branch is untested (XC-06). |
| GT-013 | OK | Tested. |
| GT-014 | OK | Every call site converts. No test runs in pounds (XC-08). |
| GT-015 | OK | This is the local-zone fix. DST transitions are still open (STATS-01). |
| GT-016 | **Incomplete** | The stats readers canonicalise. `LoadScaleBook`, `addExercise` grouping and the export catalog still key on raw merged IDs (LIB-03). `topExercises` tallies by name, which is cosmetic. |
| GT-017 | **Incomplete** | `TrainingStats` is fixed. The session summary still ranks and prints unloaded and duration records as load records (LOG-07). |
| GT-018 | OK | The calendar is fixed. The streak, the week strip and the session counts still count empty sessions (STATS-05). |
| GT-019 | OK | A logged weighted bodyweight row reads "10 kg × 8", with nothing saying the 10 kg is added load. This is a nit. |
| GT-020 | **Regression** | Restoring any backup written before this change deletes from Apple Health the workouts of the very sessions it restores, and the test asserts that behavior (DATA-01). |
| GT-021 | **Incomplete** | Only renames made from now on update plan items. Items renamed earlier keep their stale name for good, because `SessionFactory` copies `item.name` verbatim, including on the headless watch start. Resolve `item.catalog?.name ?? item.name` at creation. |
| GT-022 | OK | Tested. |

## Suggested order of work

Each group is a coherent change that one session can own. The groups are listed in
the order they should land. The IDs in each group are in the index below.

1. **Watch-link delivery and identity.** LINK-02, LINK-01, WATCH-01, LINK-05,
   LINK-04, WATCH-03, LINK-06, LINK-07. These share one set of protocol changes:
   stamps and session IDs on commands, one ordered channel while a backlog
   exists, a local tombstone on the watch, and late logs that attach to a
   just-closed session. Write XC-04 and WATCH-16 first so each fix has a failing
   test to turn green.
2. **Health record integrity.** DATA-01 (fix it first; it is a single function),
   DATA-02, WATCH-06, WATCH-07, WATCH-08, WATCH-09, WATCH-15, XC-02, HK-02, HK-03,
   HK-06, HK-07, STATS-04. Add the test seam in XC-05 first.
3. **Session lifecycle.** LINK-03, WATCH-10, HK-13, STATS-05, SESS-07. Add one
   shared "stale or empty session" helper and call it from every start and
   resume path.
4. **Custom exercises on the headless path.** LIB-01. This is small and
   self-contained, and it corrupts data today.
5. **Logger honesty.** LOG-03, LOG-02, SESS-02, LOG-01, LOG-10, LOG-05, LOG-09.
   The main piece of work is an in-place edit for a logged set.
6. **Progression and catalog.** STATS-02, SESS-01, LIB-02, LIB-03, LIB-04, and the
   GT-021 residue. XC-06 comes first.
7. **Export fitness for the AI coach.** DATA-03, DATA-04, XC-03, DATA-05 to
   DATA-10. XC-10's round-trip test comes first.
8. **Calendar and stats.** STATS-01, STATS-03, STATS-08 to STATS-11.
9. **Input and accessibility.** XC-01, XC-11, LOG-14, LOG-11, WATCH-13, WATCH-14.
10. **Performance.** STATS-06, LOG-12, LOG-13, LINK-08, WATCH-12, HK-09, DATA-14.
    These are cheap to do once the correctness work in the same files has landed.
11. **Test infrastructure.** XC-09, then the remaining test gaps.

## P1

| ID | Title | Conf. | Main location | Aliases |
|---|---|---|---|---|
| DATA-01 | Restoring a backup without `healthWorkoutID` (every backup written before this change) deletes from Apple Health the workouts of the sessions being restored, and unlinks them. `Tests/BackupServiceTests.swift:88` asserts the defect. Fix: key the cleanup on session ID, and carry the local link over when the archive has none. | confirmed | `Services/BackupService.swift:530-558` | HK-01 |
| LINK-01 | A Finish tapped on the phone deletes rows that the wrist logged but has not yet delivered. The phone never asks the watch for its batch. Once the phone has finished, `activeWorkout` is nil, so a late `.logSet` falls through to the headless path, and `WatchCommandCenter.swift:85` drops it. The watch's `reconcile(with: nil)` then runs `pending.clear()` and throws away its only copy. Real sets vanish from the record. | confirmed (verified) | `Models/SessionClosing.swift:60-69`, `Services/WatchCommandCenter.swift:85`, `GymTrackWatch/WatchConnector.swift:307-316` | WATCH-02 |
| LINK-02 | A freshly launched phone process, including a background wake by a wrist log after a jetsam, pushes `session: nil` on WCSession activation, before it has read the store. The watch orders mirrors by `sentAt` alone and has no grace period, so it accepts it. `syncRecorder` ends the running Health recording with `discardingSamples: true`, and `reconcile` clears the pending wrist logs, which also feeds LINK-01. | confirmed (verified), device pending | `Services/WatchBridge.swift:169-176`, `GymTrackWatch/Views/WatchRootView.swift:93-115` | |
| LINK-03 | The 12-hour stale-session rule runs only in `RootView.task`, so on a cold foreground launch only. A resident or background-woken app keeps yesterday's session. Every wrist Start is answered with a session the watch refuses to draw, and a warm Finish writes a workout of about 20 hours to the record and to Health. | confirmed | `App/RootView.swift:40,463-494`, `Services/WatchCommandCenter.swift:60-67` | related: WATCH-10, HK-13 |
| WATCH-01 | After a wrist Finish or Discard with the phone out of range, nothing on the watch records that the session ended. The trigger is a *watch relaunch*: the cached context brings the session back, or a `requestMirror` reply overtakes the queued Finish. A watch process that stays alive does not restart recording. On relaunch, recording restarts backdated to the session's start. The second workout is saved when the ended mirror arrives. `acceptWatchWorkout` then queues the accurate first workout for deletion and relinks the session to the second, overwriting HR and energy. | confirmed (verified) | `GymTrackWatch/Views/WatchRootView.swift:119-147`, `GymTrackWatch/WatchConnector.swift:72-96` | |
| LIB-01 | A workout started from the watch while the phone app is terminated records custom exercises as weight × reps. `configureServices` never loads custom exercises, so `PlanItem.tracking` falls back to `.weightReps`, and that value is snapshotted into every `SetLog`. A custom hold cannot record seconds, and the rows stay wrong after the app opens. | confirmed | `App/GymTrackApp.swift:64-77`, `Models/Entities.swift:149-152` | |

## P2

| ID | Title | Conf. | Main location | Aliases |
|---|---|---|---|---|
| SESS-01 | Repeated plan slots skip progression and history and open at the static target, which is 0 kg unless one was typed. The first log's `carryLoadForward` then flattens both slots to one weight. This is a regression from the GT-011/012 fix, and the existing test asserts the static loads. | confirmed | `Services/ActiveWorkout.swift:21-39,313-323` | |
| SESS-02 | Logging *any* set files the standing load offer as `.declined`. That includes a set of another exercise, a drop row, and a set lifted by hand at the offered rung. Undo does not take the decline back, and it is exported. | confirmed | `Services/ActiveWorkout.swift:274-276,325-340` | |
| LINK-05 | Wrist log and undo are neither ordered nor idempotent. A duplicate `.logSet` re-runs `complete()`, which reverts a taken nudge, files a decline and moves loads. An undo can be overtaken by its own log. A stale undo can erase a re-log. The phone must ignore a log for an already-completed set with the same stamp, and an undo should carry the completion stamp it takes back. | likely | `Services/ActiveWorkout.swift:989-997,1017-1020`, `GymTrackWatch/WatchConnector.swift:168-192` | SESS-03, WATCH-05 |
| LINK-04 | Live metrics fall back to `transferUserInfo` when the phone is out of range, so hundreds queue up. Any that land after the finish overwrite the session's final average HR, max HR and energy, because both writers assign rather than merge. | likely | `GymTrackWatch/WatchConnector.swift:168-191`, `App/RootView.swift:416-431`, `Services/WatchCommandCenter.swift:226-232,262-271` | WATCH-04 |
| WATCH-03 | `WatchFinishBatch` has no end time, so a queued wrist Finish closes the session when it *arrives*. The session and any phone-fallback Health workout are inflated by the walk back. | confirmed | `GymTrackShared/WatchLink.swift:308-315`, `Services/WatchCommandCenter.swift:249-253` | |
| WATCH-06 | A session that ends while `startIfNeeded` is suspended, for example in `requestAuthorization`, still completes the start and leaves an orphan `HKWorkoutSession` running. There is no cancellation or still-wanted check, and `end()` bails because `self.session` is unset until `beginCollection` returns. The orphan sends metrics tagged with the finished session every 5 s, and `applyLateMetrics` overwrites that session's HR and energy with them. | confirmed (verified) | `GymTrackWatch/WatchWorkoutRecorder.swift:79-120` | |
| WATCH-07 | With "Save workouts to Health" off, the watch never starts a workout session, so it loses background runtime. There is no rest-over haptic with the wrist down, the app falls to the watch face and no HR is collected. This is the GT-006 regression. Keep the session and discard the samples instead. | likely (device) | `GymTrackWatch/Views/WatchRootView.swift:96-103` | |
| WATCH-09 | No `WKApplicationDelegate`: neither `handleActiveWorkoutRecovery` nor `handle(_ workoutConfiguration:)` is implemented. A crash mid-workout loses the recording, and a phone auto-launch waits for a wrist raise. | likely (device) | `GymTrackWatch/GymTrackWatchApp.swift` | |
| WATCH-10 | A session nobody finishes keeps the watch recording, with the HR sensor on, for up to 12 hours. The recording is then discarded whole. The phone's stale-close pushes no end and writes no Health workout. | confirmed | `GymTrackWatch/WatchConnector.swift:79`, `App/RootView.swift:476-489` | related: LINK-03, HK-13 |
| LOG-03 | A logged set cannot be edited. The only correction path is Undo then Log, which restamps `completedAt` to now, drops the start, the rating and the HR, starts a rest nobody is taking, and reorders the export. A typo fix becomes a false trace. | confirmed | `Features/Session/ActiveWorkoutView.swift:956-963`, `Services/ActiveWorkout.swift:254-340` | SESS-04 |
| LOG-02 | "Remove" deletes the last row even when it is logged, with one tap and no confirmation. It shows on completed cards too. | confirmed | `Services/ActiveWorkout.swift:763-770`, `Features/Session/ActiveWorkoutView.swift:567-575` | SESS-05 |
| LOG-01 | Tapping a finished exercise to review it calls `focus(on:)`, which overwrites `preferredExerciseID`. The wrist, the Lock Screen and the dock then jump to a different exercise from the one being lifted. | confirmed | `Features/Session/ActiveWorkoutView.swift:305-308` | |
| STATS-05 | Finishing with nothing logged keeps an empty session. It extends the streak, counts toward "This week" and the session tiles, and is exported, while the calendar and Today call the day untrained. Route a zero-set Finish to Discard. | confirmed | `Models/SessionClosing.swift:60-68`, `Services/TrainingStats.swift:18-19` | LOG-06, SESS-09, XC-07 |
| STATS-01 | The streak and every daily bucket break on midnight DST transitions (Africa/Cairo, reproduced): `date(byAdding: .day)` is never re-normalised to the start of the day. | confirmed | `Services/TrainingStats.swift:18-41,587-600,635-645`, `Features/Progress/ProgressComponents.swift:247-253` | |
| STATS-02 | The progression reads a partial or off-plan last session as a full one. One logged set at the top of the range, or a light 40 × 20 technique set, gives `.increaseWeight`. After a deload, the reps prefill uses last time's short count (GT-012 residue). | confirmed | `Services/TrainingStats.swift:411-474`, `Services/ActiveWorkout.swift:22-44` | |
| STATS-03 | Plan days with no weekday pinned, which is the default for "Add day", are never scheduled. Today says "Rest day", and Siri, the widget and the wrist's Start Today all start an empty freestyle session. Add rotation: the day after the last finished `planDayID`. | confirmed | `Models/Entities.swift:36-44`, `Features/Today/TodayView.swift:17,120-124` | LIB-08 |
| STATS-04 | A mistyped weigh-in cannot be deleted, and a same-day correction leaves the wrong sample in Apple Health. Keep the sample UUID on `BodyMetric`. | confirmed | `Features/Progress/BodyWeightCard.swift:172-189`, `Services/HealthKitService.swift:530-545` | HK-04 |
| STATS-06 | The Progress tab walks every set of the full history about 7 times inside `body`, on every metric or window tap and twice on first appear. That is about 0.15 to 0.3 s per tap at 7,500 sets. Cache per-session digests. | likely | `Features/Progress/ProgressDashboardView.swift:35,325-381` | |
| DATA-02 | Restore and Erase delete GymTrack workouts from Apple Health with no explicit consent. The Erase dialog says data "on this device" is deleted, Health syncs through iCloud, and a later restore cannot put the workouts back. A workout that is already gone is reported as a failure. | confirmed | `Features/Settings/SettingsView.swift:150-154,199-204`, `Services/BackupService.swift:552,694-749` | HK-05 |
| DATA-03 | Restoring a backup from before warm-ups were removed inserts warm-up sets as working sets. `isWarmup` is decoded and then ignored. | confirmed | `Services/BackupService.swift:130-132,624-671` | |
| DATA-04 | The export states things nobody measured. Every weighted set has `seconds: 45`, because the plan item default is copied into every set. Continuation rows have `0` targets as sentinels. Off-plan exercises carry an 8-12 target nobody set. Empty `notes` are written as `""`. | confirmed | `Services/ActiveWorkout.swift:52,431-432,801-803`, `Models/Entities.swift:117` | |
| HK-02 | Health activities are built in plan order with a moving cursor, so an exercise done out of order, or with a make-up set at the end, is dropped from the workout's activity breakdown. Segment by `completedAt` instead. | confirmed | `Services/HealthKitService.swift:179-212` | |
| HK-03 | Per-set HR is backfilled only within about 13 s of finishing, and never from `SessionDetailView`. A headless finish with the phone locked cannot read Health at all. A partial first pass is frozen, because `recordDetectedWindow` writes once. | likely | `Services/HealthKitService.swift:374-473`, `Features/Session/SessionSummaryView.swift:42-44,361` | |
| XC-01 | Typed stepper entry is unbounded. `Int(Double)` traps on a long run of digits typed into Reps or Seconds, which crashes mid-workout. Weight has no ceiling, so a typo like 1000 kg is stored as measured. A non-finite weight makes the export throw and silently stops watch mirrors. | confirmed | `DesignSystem/Components.swift:300-304`, `Features/Session/ActiveWorkoutView.swift:1307-1320` | |
| XC-02 | `recordToHealth` holds a `WorkoutSession` across up to 12 s of awaits with no liveness check. Erase, restore or delete in that window leaves an orphan Health workout, and the late watch ID is dropped. Check `modelContext == nil` after each await; see the SwiftData note above. | likely | `Services/ActiveWorkout.swift:904-925`, `Services/HealthKitService.swift:155-236` | HK-14 |
| XC-03 | Restore accepts an out-of-range `weekday` or `targetRepsLow`. `weekdaySymbols[weekday - 1]` and `targetRepsLow...60` then trap on every launch. This matters because AI_COACH plans imported plan proposals. Validate before `deleteStoredRecords`. | confirmed | `Services/BackupService.swift:578`, `Models/Entities.swift:76-84`, `Features/Plans/DayEditorView.swift:241` | |
| LIB-02 | Chest Dip, Hyperextension, Tibialis Raise and GHD Back Extension are tracked as weight × reps. After a clean bodyweight session, the progression climbs from 0 kg to an invented 1.25 kg. | confirmed | `Models/CatalogExercise.swift:259-265`, `Services/TrainingStats.swift:431,457-473` | |
| LIB-03 | A machine-weight correction is saved under the survivor ID but read by the raw merged ID, so it never applies to plan slots created before the merge. The Settings row for it cannot be cleared either. | confirmed | `Services/LoadScaleBook.swift:56-100`, `Features/Library/LoadScaleSheet.swift:216-221` | DATA-11 |
| LIB-04 | Changing a custom exercise from Duration to a reps mode leaves its plan slots on a 0-0 rep range. From then on the progression adds weight every session and resets reps to 0. | confirmed | `Features/Library/ExerciseEditorView.swift:259-269`, `Services/TrainingStats.swift:413` | |

## P3

| ID | Title | Conf. | Main location | Aliases |
|---|---|---|---|---|
| LOG-04 | `discard()` reads `session.id` after it has deleted and saved the session. On the current SDK this does not crash (reproduced), so the finding is downgraded from a crash. Capture the ID first anyway, because iOS 17 was not tested. | not reproduced | `Services/ActiveWorkout.swift:877-880` | |
| LOG-05 | Undoing any set stops the running rest, even one that belongs to a different set. | confirmed | `Services/ActiveWorkout.swift:337` | |
| LOG-07 | The session summary ranks unloaded and duration records by e1RM. It prints "0 kg × 15" and can show the lesser of two records. This is the GT-017 UI residue. | confirmed | `Features/Session/SessionSummaryView.swift:13-18,151-153,474-476` | |
| LOG-08 | The logger header, the tick bar, the card and the queue count drop rows as sets, while the dock, the Lock Screen and the summary count efforts. | confirmed | `Features/Session/ActiveWorkoutView.swift:117,171-176,344,737` | |
| LOG-09 | Removing a mis-tapped continuation row does not restore the rest that `continueSet` stopped. | confirmed | `Services/ActiveWorkout.swift:439,448-454` | |
| LOG-10 | A start that is announced and then abandoned for another exercise survives, and pairs with a much later log. The result is a false time under tension of 20 minutes or more, exported as measured. | likely | `Services/ActiveWorkout.swift:189-192,254-264` | SESS-06 |
| LOG-11 | Holding − on a drop row can lift the context menu, which includes a destructive "Remove this row", instead of stepping. | likely | `Features/Session/ActiveWorkoutView.swift:683,842` | |
| LOG-12 | The logger rebuilds `exerciseGroups` about 2N+5 times per render. It re-renders on every HR merge and every stepper step, and the dock re-renders at 4 Hz during a rest. | likely | `Features/Session/ActiveWorkoutView.swift:128,227-328`, `Features/Session/SessionDock.swift` | |
| LOG-13 | The session summary walks the full history for records on every keystroke in its note field. | likely | `Features/Session/SessionSummaryView.swift:9-24`, `Features/Session/SessionNotes.swift:232-242` | |
| LOG-14 | Icon-only controls with lasting effects (undo a set, end the rest) have no VoiceOver label. Every `Theme` font is a fixed size, so Dynamic Type is ignored. `textTertiary` is about 3.6:1 contrast on 8-11 pt captions. | confirmed | `Features/Session/ActiveWorkoutView.swift:956-963,1557-1566`, `GymTrackShared/Theme.swift:22,37-50` | XC-13 |
| LOG-15 | An exercise added by mistake cannot be removed from the session. `removeExercise` exists but has no caller. | confirmed | `Services/ActiveWorkout.swift:813-819` | |
| SESS-07 | The rest timer plays a late "rest over" chime when the app returns to the foreground after the rest ended in the background. A relaunch loses the rest, but its notification still fires. | confirmed | `Services/RestTimer.swift:96-117` | |
| SESS-08 | A past session deleted during a workout stays in the running workout's history, PR baseline and "last time" hints. It returns stale data; the crash was not reproduced. | confirmed | `Services/ActiveWorkout.swift:97-121,348-356` | STATS-07 |
| STATS-08 | The records card takes the date of a *later* tie. Uncapped Epley lets 60 × 30 beat 100 × 5, and the weight, the e1RM and the date on one row can come from different sets. Bodyweight "best reps" mixes loaded and unloaded sets. The trophies imply a ranking the recency sort no longer has. | confirmed | `Services/TrainingStats.swift:225-265` | |
| STATS-09 | Today shows "You're done for today" after *any* session, including an unrelated freestyle one or the tail of last night's session, and hides the scheduled day. | confirmed | `Features/Today/TodayView.swift:22,118-121` | |
| STATS-10 | "This week" is the locale's calendar week on Today and a rolling 7 days on Progress. The consistency grid is hard-coded Sunday-first. | confirmed | `Features/Today/TodayView.swift:25-30`, `Features/Progress/ProgressDashboardView.swift:99,129-133` | |
| STATS-11 | The body-weight sparkline spaces weigh-ins by index, not by date, and the change figure gives no time span. | confirmed | `Features/Progress/BodyWeightCard.swift:92-127` | |
| STATS-13 | Missing feature: a zero-tap "Lifts" card that tags each lift as moving, flat or sliding, from data already logged. It stays on screen only and is not exported. | n/a | `Features/Progress/ProgressDashboardView.swift` | |
| DATA-05 | The export has no `planDayID` on sessions and no IDs on sets, although AI_COACH requires set citations. Restore also regenerates set IDs. | confirmed | `Services/BackupService.swift:78-214` | |
| DATA-06 | Export arrays are in no defined order, so "continues the row above" and a byte-stable hash are unreliable. | likely | `Services/BackupService.swift:290-295,333` | |
| DATA-07 | The export records no time zone and no app version. Dates are UTC while plan weekdays are local. | confirmed | `Services/BackupService.swift:380-388` | |
| DATA-08 | Effort is exported as a point RPE: "Easy", meaning 3 or more reps left, is stored as `rpe: 6`. Nothing marks which scale an answer came from, and `trackRPE` is not exported, so "not answered" and "never asked" look the same. | confirmed | `GymTrackShared/SetFeel.swift:10-14`, `Services/BackupService.swift:163,347` | |
| DATA-09 | Only the load scales the user corrected are exported. The default rung per exercise is missing, so a coach cannot propose a legal load. | confirmed | `Services/BackupService.swift:270-285,371-373` | |
| DATA-10 | Session HR and energy carry no provenance. A few background samples, or pedometer energy, read as a workout measurement. | confirmed | `Services/HealthKitService.swift:350-393`, `Services/BackupService.swift:326-328` | |
| DATA-12 | "Keep screen awake while training" keeps the screen awake whenever the app is open, and it is on by default. | confirmed | `App/GymTrackApp.swift:41`, `Services/AppSettings.swift:58-63,106` | |
| DATA-13 | Changing the unit or rest auto-start mid-workout is not pushed to the watch. Only `trackRPE` is. | likely | `App/RootView.swift:82-84` | |
| DATA-14 | Export, restore and erase run on the main thread with no progress state. Erase deletes Health workouts one at a time. | likely | `Features/Settings/SettingsView.swift:239-302`, `Services/BackupService.swift:289-392,498-559` | |
| HK-06 | Deleting a session from history fires the Health delete once and never retries. It is likely to fail for a workout the watch saved, with no notice. | confirmed | `Features/Session/SessionSummaryView.swift:416-424` | |
| HK-07 | The fallback-cleanup queue retries only on a cold launch or after authorization. Entries whose workout is already gone stay forever, and each retry fetches every session. | likely | `Services/HealthKitService.swift:67-70,265-294` | |
| HK-08 | Headless wrist logging never updates the Live Activity or the widget snapshot. An abandoned session shows as running on the widgets indefinitely. | confirmed | `Services/WatchCommandCenter.swift:60-157,308-311`, `GymTrackShared/SharedStore.swift:205-233` | |
| HK-09 | Every in-session save reloads every widget kind, 2-3 reloads per set. When woken in the background, those reloads spend the daily budget. | likely | `Services/WidgetPublisher.swift:68-99` | |
| HK-10 | The Dynamic Island rest ring is always full because `restProgress` has its sign reversed. | confirmed | `GymTrackShared/WorkoutActivity.swift:64-69` | |
| HK-11 | The phone requests Health read access to resting HR, basal energy and activity summaries, and share access to energy. None of them are used, and resting HR is rejected recovery data. | confirmed | `Services/HealthKitService.swift:88-101` | |
| HK-12 | A Siri, Shortcut or Action Button start may be read before `perform()` writes its note. The workout then starts late, or not at all. | speculative | `GymTrackShared/GymTrackIntents.swift:14-56`, `App/RootView.swift:37-97` | |
| HK-13 | A session closed by the stale-recovery path is never written to Health or backfilled. | confirmed | `App/RootView.swift:476-488` | related: LINK-03 |
| LINK-06 | A Start queued while the phone is out of range has no expiry. Hours later it starts a workout, and the wrist starts recording. Add, focus and rest commands carry no session ID either. | likely | `GymTrackShared/WatchLink.swift:319-352`, `Services/WatchCommandCenter.swift:60-80` | WATCH-11 |
| LINK-07 | The headless mirror always says "no rest", and the watch treats that as "skipped on the phone", so it clears its running rest. | likely | `Services/WatchCommandCenter.swift:326-328` | |
| LINK-08 | Unpredicated fetches: every headless command fetches all sessions several times, runs `discardUntouchedOverlaps` and rebuilds per-exercise history. `RootView.watchIdle` computes the streak on every body pass. `HealthKitService` looks up sessions by ID with a full fetch. | confirmed | `Services/WatchCommandCenter.swift:313-361`, `App/RootView.swift:13,66,290-292` | XC-12 |
| LINK-09 | The headless path keeps a second, process-lifetime `ModelContext`. It may show stale rows after a save in `mainContext` on some iOS 17 and 18 builds. | speculative | `Services/WatchCommandCenter.swift:26-27` | |
| WATCH-08 | Builder and session delegate callbacks are not matched to the current builder or session. Verification downgraded this from P2. A late builder callback can refill the fields that `end()` reset, but its metrics carry no session ID, so the phone ignores them, and the stale values show only briefly at the next start. The riskier half is the session delegate: a stray state change from the old session can flip `isRunning` for the current one, which leaks a session or leaves one never ended, in a narrow window. This finishes GT-009. | confirmed (verified) | `GymTrackWatch/WatchWorkoutRecorder.swift:189-248` | |
| WATCH-12 | The rest countdown re-renders the whole watch logger at 4 Hz. A mirror whose rest ended long ago still buzzes when it arrives. | confirmed | `GymTrackWatch/WatchRestTimer.swift:42-114` | |
| WATCH-13 | A double tap on Log set logs the next set too, or lands on the effort sheet that replaced the button. | likely | `GymTrackWatch/Views/WatchLoggerView.swift:587-618` | |
| WATCH-14 | The effort question covers the whole watch logger for up to 10 s after every set, which blocks an immediate drop set or superset. This conflicts with rule 3. | confirmed | `GymTrackWatch/Views/WatchLoggerView.swift:61-99` | |
| WATCH-15 | A watch workout saved because the phone finished has no metadata and no `HKMetadataKeyExternalUUID`. | confirmed | `GymTrackWatch/Views/WatchRootView.swift:111`, `GymTrackWatch/WatchWorkoutRecorder.swift:138-148` | |
| LIB-05 | Search aliases hide results while a word is being typed. "calv", "fli", "quadr" and "abdo" return nothing, "ham" hides Hammer Curl, and the empty state invites adding a duplicate. | confirmed | `Models/ExerciseSearch.swift:34-130` | |
| LIB-06 | Deleting an item from a day and then adding one can give two items the same `order`, which makes the session order unstable. | likely | `Features/Plans/DayEditorView.swift:157-187` | |
| LIB-07 | After a custom exercise is deleted, its weight caption opens a blank, undismissable-looking sheet mid-workout. | confirmed | `Features/Session/ActiveWorkoutView.swift:1184-1189,1230-1233` | |
| LIB-09 | Onboarding forces a template, and the active routine cannot be deleted. The unit copy "Steps in 2.5 kg" is outdated. | confirmed | `Features/Onboarding/OnboardingView.swift:202-237`, `Features/Plans/PlansView.swift` | |
| XC-11 | Weight and rep entry silently discards Arabic-Indic digits typed on the decimal pad. | likely | `DesignSystem/Components.swift:298-304` | |
| XC-14 | Swift 6 readiness. WCSession delegate hops use one unstructured `Task` each, so their ordering is not guaranteed. `ExerciseCatalog` and `LoadScaleBook` are `@unchecked Sendable` with mutable state, and `RestTimer` is not `@MainActor`. | speculative | `Services/WatchBridge.swift:200-222`, `GymTrackWatch/WatchConnector.swift:387-397` | |

## Test gaps

No test target exists. The seven scripts compile app sources for macOS with
`swiftc`, so they run the Mac's SwiftData rather than iOS 17's. Nothing runs them
automatically. The gaps below are ordered by what they would have caught.

| ID | Gap | Would have caught |
|---|---|---|
| XC-04 | No test drives `WatchCommandCenter.applyHeadless` or the UI routing. The one headless test checks only the no-op path. Aliases: LINK-10. | GT-001 regressions, LINK-01, LINK-05 |
| WATCH-16 | The watch's save-or-discard decision and `reconcile` live in a view and a WCSession class, so they cannot be tested. | WATCH-01, WATCH-02, LINK-02 |
| XC-05 | HealthKit duplicate prevention and cleanup have no seam and no test. | GT-008 regressions, XC-02, HK-07 |
| XC-06 | The GT-012 rep reset is untested: the factory test uses only repeated slots. | STATS-02, SESS-01 |
| XC-10 | There is no field-exhaustive "unlog leaves no trace" test and no export-restore-export round-trip test. | DATA-01, DATA-03, DATA-05 |
| STATS-12 | There are no tests for `suggestion` or `streak`, and none for a non-local calendar. | STATS-01, STATS-02, STATS-05 |
| HK-15 | `GymTrackSnapshot.asOf`, activity segmentation, the cleanup queue and `restProgress` are untested. | HK-02, HK-10 |
| LIB-10 | Custom-exercise edits, `LoadScale` round trips in lb and search are untested. | LIB-03, LIB-04, LIB-05 |
| XC-08 | Every `AppSettings` stub hard-codes kg. | pound-conversion regressions |
| XC-09 | There is no runner, and the stubs have drifted: the tests run with auto-rest off, while users default to on. `WatchSessionRecovery` is stubbed to identity. Add `scripts/test-all.sh`, then a `GymTrackTests` target run on an iOS 17 simulator. | stub drift, iOS 17 SwiftData behavior |

## Missing features worth building

These fit the house rules. Each costs nothing for a user who ignores it, and the
record stays honest. The detail files give the design for each.

- **Rotation scheduling for unpinned days** (STATS-03). Lifters who run A/B/C
  without weekdays are told they are resting.
- **An in-place edit for a logged set** (LOG-03). This is the only honest way to
  fix a typo.
- **Removing an exercise added by mistake** (LOG-15). The service method already
  exists.
- **Deleting a weigh-in, and undoing a mistyped one** (STATS-04).
- **Starting onboarding from blank, and deleting a routine** (LIB-09).
- **An auto-end for an abandoned watch session**, at the last logged set, without
  prompting (WATCH-10).
- **A lift-trend card** (STATS-13).
- **Export context the coach needs**, all as optional fields: time zone and app
  version (DATA-07), `planDayID` and set IDs (DATA-05), the effort scale and
  `trackRPE` (DATA-08), default load rungs (DATA-09), and vitals provenance
  (DATA-10).
