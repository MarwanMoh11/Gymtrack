> Detail file from the 2026-09-28 review. The index, the canonical severities and the duplicate map are in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md). Where this file disagrees with the index, the index wins. Line numbers refer to the working tree on 2026-09-28 (HEAD f5809ff plus the uncommitted GT fix pass).

# Active workout UI (phone logger): findings

Files read in full: GymTrack/Features/Session/ActiveWorkoutView.swift, GymTrack/Features/Session/SessionDock.swift, GymTrack/Features/Session/SessionNotes.swift, GymTrack/Features/Session/SessionSummaryView.swift, GymTrack/DesignSystem/Haptics.swift

Read in excerpts: GymTrack/Services/ActiveWorkout.swift (logging, undo, nudges, structure edits, finish/discard, watch apply), GymTrack/Models/Entities.swift (WorkoutSession derived values, SessionExerciseGroup, SetLog incl. `unlog`), GymTrack/Models/SessionClosing.swift, GymTrack/App/RootView.swift (presentation, dock, watch lifecycle, resume), GymTrack/DesignSystem/Components.swift (`StepperField`), GymTrack/Services/RestTimer.swift, GymTrackShared/SetLeadIn.swift, GymTrackShared/LoadScale.swift, GymTrack/Services/TrainingStats.swift (records, lastPerformance), GymTrack/Services/SetHeartRate.swift (window), GymTrack/Services/BackupService.swift (restore/wipe guards), GymTrackWatch/Views/WatchLoggerView.swift (GT-019 only).

## Prior findings re-check
- GT-019: OK. The weight stepper is now always shown for `.bodyweightReps`, titled "Added weight", reads "BW" at zero and steps up the exercise's ladder from zero (`ActiveWorkoutView.swift:1184-1189`); a zero-load set still logs with one tap. The watch shows the weight tile for bodyweight too (`WatchLoggerView.swift:317`). Residual presentation nit only: a logged weighted bodyweight row reads "10 kg × 8" (`ActiveWorkoutView.swift:1281`, summary chips `SessionSummaryView.swift:187`) with nothing saying the 10 kg is added load.
- GT-014: Not present in these files. The logger header volume (`ActiveWorkoutView.swift:121-126`), the summary tiles (`SessionSummaryView.swift:95-96, 123-125`) and the history tiles (`SessionSummaryView.swift:373-374`) all go through `AppSettings.weight`, which converts from kilograms before formatting.
- GT-017 (UI side in these files): INCOMPLETE. The summary's record list still prints and ranks unloaded bodyweight and duration records as load records; see LOG-07.

## Findings

### LOG-01: Reviewing a finished exercise overwrites the exercise the lifter chose, so the wrist and Lock Screen jump to a different one
- Severity: P2
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:305-308` (queue row action), `GymTrack/Services/ActiveWorkout.swift:179-192` (`currentGroup`, `focus(on:)`)
- What happens: Every queue row tap runs `workout.focus(on: group.catalogID)` before deciding whether it is a review, including taps on a complete exercise. `focus` stores that ID as `session.preferredExerciseID`, and `currentGroup` ignores a preferred group that is complete (`groups.first(where: { $0.catalogID == preferred && !$0.isComplete })`) and falls back to the first incomplete exercise in plan order. The exercise the lifter had picked out of order is lost. The view's own comments say a review must not do this: "completed exercises open for review without changing what the watch calls 'next'" (`:282-284`) and `reviewedGroupID` "is kept separate from `currentGroup`" (`:22-24`).
- Failure scenario: Plan day A, B, C. A is done. B's rack is taken, so the lifter taps C (preferred = C) and logs C set 1. During the rest they tap A to rate its last set. `focus(on: A)` sets preferred = A. A is complete, so `currentGroup` becomes B. The banner offers "Back to B", and the watch mirror, Live Activity and dock all switch to B's next set. A lifter who logs from the wrist without looking logs B's set at B's weight while actually doing C.
- Suggested fix: In the queue button, call `workout.focus(on:)` only when `!group.isComplete`. For a complete group, set `reviewedGroupID` only.
- Verify by: A structure test that focuses C, completes a set, and then runs the review path on complete A. It should assert `currentGroup?.catalogID == "C"` and `session.preferredExerciseID == "C"`. Manual check: the watch keeps showing C after reviewing A.

### LOG-02: "Remove" deletes a logged set with one unconfirmed tap
- Severity: P2
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:567-574` (Remove button), `GymTrack/Services/ActiveWorkout.swift:763-770` (`removeLastSet`)
- What happens: The button shows whenever `group.sets.count > 1`, and `removeLastSet` runs `context.delete(group.sets.last)` without checking `isCompleted`. It is documented as "the pair of `addSet`, undoing exactly what that did", but it deletes whatever row is last, logged or not. The button is 12 pt text next to "Add set", with no confirmation and no way back.
- Failure scenario: (a) The lifter opens a finished exercise to rate it (the review path) and sees "Add set / Remove". Every row there is logged, so a tap on Remove, or a slip while reaching for Add set, erases the last logged set with its reps, rating, start and heart rate. (b) Sets 1-3 are logged and set 2 is undone to fix it. The last row, set 3, is logged, so Remove deletes set 3 and leaves pending set 2 in place. Either way real work disappears from the record and the export.
- Suggested fix: Make `removeLastSet` remove the last row that is `!isCompleted` (preferring a non-continuation), and hide the button when there is none. That makes it the true pair of `addSet`. Leave erasing logged work to the undo-then-remove path.
- Verify by: Extend `Tests/ActiveWorkoutStructureTests.swift`. Complete every set of a group, call `removeLastSet`, and assert that the completed count is unchanged. Also cover the undo-middle-set case.

### LOG-03: Fixing a number on a logged set is only possible by Undo then Log, which writes a false completion time and discards the measured start
- Severity: P2
- Category: data-rule
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:956-963` (undo on a completed row, the only edit path), `GymTrack/Services/ActiveWorkout.swift:254-305` (`complete`), `:325-340` (`uncomplete`), `GymTrack/Models/Entities.swift:789` (`unlog`)
- What happens: A completed row has no editor. To correct a mistyped weight or rep count, the lifter must undo, which runs `unlog()` and clears `completedAt`, `startedAt`, `rpe`, heart rate and the nudge outcome, then re-log. `complete` stamps `set.completedAt = moment` (now), starts a fresh rest (`restTimer.restore(endingAt: moment + rest)`) and makes it `lastLoggedSetID`. The correction becomes a new lift at a moment nobody lifted, and the measured time under tension and the rating are lost. Rule 2 is about mis-taps leaving no trace. Here a correction leaves a false trace (rule 1).
- Failure scenario: A1 10:00, A2 10:03, A3 10:06 (80 kg typed, 100 kg lifted), B1 10:20. At 10:25 the lifter undoes A3, types 100 and logs. The record now has A3 at 10:25, after B1. `gapsWithProvenance` sorts by log time, so it computes an A2→B1 gap of 17 min and a B1→A3 "rest" of 5 min that never happened, which skews `typicalRestSeconds`. The export tells the coach the lifter went back to A. A 90 s rest countdown starts that nobody is taking. The Health write then attributes A3's heart rate to a window inside B's rest. Second variant: undoing a set whose logged drop row sits below it leaves the drop logged. When the parent is re-logged it is stamped after the drop that "continues" it, and `unlinkOrphanedContinuations` only handles a parent that stays unlogged.
- Suggested fix: Add an in-place edit for logged rows, for example a long-press "Edit numbers" in `effortMenu`, reusing the steppers. It writes `weightKg`/`reps`/`seconds` and leaves `completedAt`, `startedAt` and `rpe` untouched, then calls `numbersChanged()`. A typo is a fact about the numbers, not about the moment. Separately, block undo on a set whose next row is a logged continuation, or undo both together.
- Verify by: A test that logs A3, edits its reps through the new path, and asserts `completedAt` is unchanged and `typicalRestSeconds` is identical before and after. Manual check: correcting an older set starts no rest.

### LOG-04: Discard reads the session after deleting and saving it
- Severity: P2 (P1 if it traps; unconfirmed)
- Category: bug
- Confidence: speculative
- Location: `GymTrack/Services/ActiveWorkout.swift:877-880` (`discard`, the logger's Discard button and the dock's), `GymTrack/Features/Session/SessionDock.swift:139-143` (dock clock `TimelineView`)
- What happens: `discard()` calls `context.delete(session)` and `writeThrough()`, then builds `WatchSessionEnd(sessionID: session.id, …)`. That post-delete read was added in this fix pass (HEAD sent `update(session: nil)`). Separately, when discarding from the dock, `closeSession()` removes the dock with an animated transition (`RootView.swift:145`). The dock's `TimelineView(.periodic(from: .now, by: 1))` closure reads `workout.session.duration` (`startedAt`/`endedAt`) and can tick during that transition. SwiftData is known to trap on attribute reads of a deleted, saved model; `ActiveWorkout.planItem(for:)` guards `isDeleted` for exactly this reason.
- Failure scenario: The lifter discards. If SwiftData traps on the post-save read, the app crashes on Discard, or on dock Discard when a clock tick lands inside the removal animation.
- Suggested fix: In `discard()`, capture `let id = session.id` before `context.delete`. In `SessionDockBar`, read `startedAt` into a value, as `SessionClock` already does, or skip drawing when `workout.session.isDeleted`. The same pattern exists in the headless `.discardSession` (`WatchCommandCenter.swift:213-217`).
- Verify by: Discard from the logger and from the dock context menu on the iOS 17.0 and latest simulators, with the dock visible for more than 1 s before confirming. Watch the console for SwiftData backing-data faults.

### LOG-05: Undoing any set stops the rest that is running, even when that rest belongs to a different set
- Severity: P3
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Services/ActiveWorkout.swift:337` (`uncomplete`), reached from `ActiveWorkoutView.swift:671` and the wrist's `.undoSet` (`:1017-1020`)
- What happens: `uncomplete` calls `restTimer.stop()` unconditionally, with the comment "The rest belonged to the set being taken back". Two lines above, it clears `lastLoggedSetID` only when it matches, which is the check the stop needs too.
- Failure scenario: The lifter logs B1, so a 2:00 rest runs. They open finished exercise A through the review path to undo a mis-logged A2. The B1 countdown vanishes from the phone, the Lock Screen and the wrist, and its "Rest over" notification is cancelled.
- Suggested fix: Stop the rest only when `lastLoggedSetID == set.id` (read before clearing it).
- Verify by: A test that completes B1 with auto rest, uncompletes an earlier set, and asserts `restTimer.isRunning`.

### LOG-06: Finish with nothing logged saves an empty session, and the alert says "Every set logged. Nice work."
- Severity: P3
- Category: data-rule
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:140, 210-215, 449-453`, `GymTrack/Models/SessionClosing.swift:60-68`, `GymTrack/Services/BackupService.swift:296`
- What happens: Finish is always enabled. With `totalCount == 0` (freestyle with no exercise added), `finishMessage` computes `remaining == 0` and shows "Every set logged. Nice work." `close()` deletes the unlogged rows and stamps `endedAt`, leaving a finished session with zero sets. That session appears in history, gets a summary, and is exported (`sessions.filter { !$0.isActive }`). The rest of the app treats an untouched session as nothing: stale launch recovery deletes it (`RootView.swift:478-479`), `WatchSessionRecovery` discards untouched overlaps, and the stats filter it out.
- Failure scenario: The lifter opens a freestyle session by accident, taps Finish and confirms. The export now has "Freestyle Session, 4 min, 0 sets", a workout that happened only as a mis-tap.
- Suggested fix: In `finish()` (or `ActiveWorkout.finish`), treat `completedCount == 0` as a discard: delete the session and close without a summary. Word the alert accordingly, for example "Nothing logged. This workout won't be saved."
- Verify by: Finish an empty freestyle session, then check that history and the exported JSON contain no session for it.

### LOG-07: The summary's record list prints "0 kg × 15" for bodyweight records and can show the lesser of two duration or bodyweight records
- Severity: P3
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Session/SessionSummaryView.swift:13-18` (`prs`), `:151-153` (row text), `:474-476` (`HistorySetRow`)
- What happens: `prs` keeps one record per exercise with `max { $0.estimatedOneRepMax < $1.estimatedOneRepMax }`. `estimatedOneRepMax` is 0 for duration sets and for zero-load sets (`Entities.swift:636-640`), so all of them tie. `max(by:)` then returns the first one, and `session.completedSets` has no defined order. The row prints `"\(set.weightLabel) × \(set.reps)"` for everything except duration, and `LoadScale.format(0)` is "0 kg". `setSpoken` on the same screen already handles `weightKg == 0`. GT-017 fixed the ranking in `TrainingStats` but not this display.
- Failure scenario: Previous best plank is 50 s. Today the lifter holds 60 s, then 75 s. Both are records, and the summary can list "60s" as today's record. Pull-ups at 12 then 15 reps (prior best 10) show "Pull-up 0 kg × 12" or "0 kg × 15". History rows read "0 kg × 12" for every unloaded set.
- Suggested fix: Rank per tracking mode the way `TrainingStats.isPersonalRecord` does: seconds for duration, reps for zero-load, e1RM otherwise. Format rows with the existing `setSpoken`/`valueLabel` logic ("15 reps"). Apply the same to `HistorySetRow`.
- Verify by: A summary snapshot or test with two duration records and two zero-load records. It should show the larger one and "15 reps".

### LOG-08: The logger counts drop rows as sets while every other surface counts efforts
- Severity: P3
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:117` (header "x/y sets"), `:171-176` (tick bar), `:737` (card header), `:344` and `:355` (queue count and VoiceOver), `:213` (finish message); versus `SessionExerciseGroup.number(of:)`/`effortCount` (`Entities.swift:446-452`) and the summary's `effortSets` (`SessionSummaryView.swift:94`)
- What happens: The header, tick bar, card header and queue use `completedCount`/`sets.count`, which count rows, continuations included. The row badges, dock, Lock Screen and summary count efforts. The codebase calls out that mismatch as a bug it already fixed once ("one drop had the card reading SET 3 while the Lock Screen underneath it said set 4 of 4").
- Failure scenario: Three sets with one drop after set 2. The card's rows read 1, 2, drop, 3, while the card header says "4/4", the logger header "…/13 sets" and the dock "set 3 of 3". The summary then says "Sets 12" for a session the logger called 13.
- Suggested fix: Add effort-based counts on `ActiveWorkout` and `SessionExerciseGroup` (completed efforts / `effortCount`) and use them in these five places. Keep row counts only in the finish alert, where "rows dropped" is what it means.
- Verify by: Take one drop and compare the header, card, dock and summary numbers.

### LOG-09: Removing a continuation row does not bring back the rest that adding it stopped
- Severity: P3
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Services/ActiveWorkout.swift:439` (`continueSet` stops the rest), `:448-454` (`removeContinuation`), called from `ActiveWorkoutView.swift:832, 842`
- What happens: `removeContinuation` is documented as "the exact pair of `continueSet` — for a mis-tap", but `continueSet` stops the running rest and nothing records it for restoring. `cancelStart` already handles the same situation (`restCancelledByStart`), on the principle that a mis-tap "has to cost nothing at all, including the countdown you were watching".
- Failure scenario: The lifter logs set 2, and a 2:00 rest shows 1:40. A long press picks "Continue without resting" by mistake, and the rest stops. "Remove this row" deletes the row, but the countdown, the Lock Screen rest and the wrist rest stay gone.
- Suggested fix: Keep a `restCancelledByContinuation` (setID, endsAt, total) in `continueSet` and restore it in `removeContinuation` when it matches, as `cancelStart` does.
- Verify by: A test that runs continue then remove during a rest and asserts `restTimer.endsAt` is unchanged.

### LOG-10: An announced start survives switching to another exercise, so the set is later logged with a false "measured" time under tension
- Severity: P3
- Category: data-rule
- Confidence: likely
- Location: `GymTrack/Services/ActiveWorkout.swift:189-192` (`focus` leaves `startedAt` alone), `:254-264` (`complete` only drops a start that lies in the future), `GymTrack/Models/Entities.swift:655-658` (`timeUnderTension`), exported raw at `BackupService.swift:340`
- What happens: Tapping Start set stamps `startedAt`. If the lifter then moves to another exercise, because the bench was taken, the stamp stays on the bench set. When the bench set is finally logged, `timeUnderTension` = `completedAt − startedAt`, which can be 20+ minutes, and the export carries `startedAt` as a lifter-announced moment. The rest gap (`Entities.swift:277`) and the heart-rate window (`SetHeartRate.swift:356-359`) both refuse a start that precedes another set's log. `complete` and `timeUnderTension` lack that guard.
- Failure scenario: The lifter taps Start set on Bench set 3 at 10:20 and walks to rows instead. They log rows sets at 10:30 and 10:40, return and log bench at 10:45 without noticing the "WORKING 25:00" strip. The row shows a 25:00 tension badge, and the export tells the coach bench set 3 took 25 minutes.
- Suggested fix: In `complete`, drop `set.startedAt` when any other set in the session has `completedAt` between it and `moment`, the same rule the gap and window code already apply. Optionally, `focus(on:)` could cancel an announced start on the set it moves away from.
- Verify by: A test that announces a start on one set, completes a set of another exercise, then completes the first set, and asserts `startedAt == nil`.

### LOG-11: Holding − on a drop row can open the context menu instead of stepping the weight
- Severity: P3
- Category: bug
- Confidence: likely
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:683` (`.contextMenu { effortMenu(for: set) }` on the whole row, expanded included), `:842` ("Remove this row" for a pending continuation), `GymTrack/DesignSystem/Components.swift:358` (`.buttonRepeatBehavior(.enabled)`)
- What happens: The context menu is attached to the expanded row, which contains the steppers. For a pending continuation row, the menu is non-empty ("Remove this row"). The long press that drives the steppers' hold-to-repeat is the same gesture that lifts a context menu. A drop row opens at the weight just lifted, and dialling it down several rungs is the one job the row has ("the lifter's only job is to dial one of them").
- Failure scenario: After continuing set 3 at 60 kg, the lifter holds − to go to 40 kg. About 0.5 s in, the whole card lifts into a menu offering a destructive "Remove this row". The menu has to be dismissed with a bar in hand, and the weight has moved one rung at most.
- Suggested fix: Attach `.contextMenu` only to completed rows and put "Remove this row" as a small inline control on a pending continuation. Alternatively, attach the menu to the row's header and badge rather than the whole expanded card.
- Verify by: On a device, create a drop row and hold − on its weight. It should keep stepping with no menu.

### LOG-12: The logger rebuilds `exerciseGroups` dozens of times per render, and renders again on every heart-rate update and every stepper step; the dock re-renders four times a second during a rest
- Severity: P3
- Category: performance
- Confidence: likely
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:128` (reads `watch.liveMetrics` in the root body), `:227-231, 273-279, 293, 300, 328` (`displayedGroup`/`currentGroup`/`groups` re-derived per queue row), `:405` (`targetLabel` reads `weightKg`); `GymTrack/Features/Session/SessionDock.swift:59, 96, 122, 134, 147-157`; `GymTrack/Services/RestTimer.swift:94-100` (0.25 s ticker writing `remaining`)
- What happens: `workout.groups` is a computed `session.exerciseGroups` (group by ID, sort each group, sort groups). The logger body calls it about 2N+5 times per pass for N exercises, because each queue row evaluates `displayedGroup`, which calls `currentGroup`, which calls `groups` up to twice. The pass re-runs whenever the watch merges metrics (every ~5 s, `WatchWorkoutRecorder.swift:214`, since the header pill is read in the root body) and on every stepper step, because `queueDetail` reads the pending set's weight. In the dock, `remaining` and `progress` are read in the body, so `statusText` runs twice per pass (label and `accessibilityValue`) at 4 Hz. Each run is five or more `currentGroup` evaluations.
- Failure scenario: A 7-exercise, 28-set session: holding + on the weight rebuilds and sorts the session's groups about 20 times per step at several steps a second, on the thread that draws the stepper. A minimised session in rest does about 40 group rebuilds a second for as long as the phone is on screen.
- Suggested fix: Take `let groups = workout.groups` and `let current = workout.currentGroup` once per body and pass them to the queue. Move `LiveHeartRatePill` behind a small view that reads `WatchBridge.shared.liveMetrics` itself, as `SessionClock` does for time. In the dock, move the ring and clock into child views that read `restTimer`, compute `statusText` once, and consider a 1 s ticker, or a `TimelineView` off `endsAt`.
- Verify by: Profile with Instruments' SwiftUI template while holding + on a 7-exercise session, and while minimised during a rest. Compare body evaluation counts before and after.

### LOG-13: The session summary re-walks the whole training history for records on every keystroke in its note
- Severity: P3
- Category: performance
- Confidence: likely
- Location: `GymTrack/Features/Session/SessionSummaryView.swift:9` (`@Query` over every session, no predicate), `:13-18, 24` (`prs` → `TrainingStats.recordSets`), `GymTrack/Features/Session/SessionNotes.swift:232-235, 240-242` (save per keystroke)
- What happens: `SessionNoteCard` writes `session.notes` and calls `context.save()` on every character. That refreshes the unscoped `@Query` and re-runs the summary body, which builds `recordCandidates` over every set of every session. The code comment acknowledges it ("every save redraws this screen, and each read of `prs` walks the history") and reduces it to once per pass rather than removing it. The history cannot change while the summary is open.
- Failure scenario: A year of training (~200 sessions × ~25 sets) means about 5,000 `canonicalID` lookups and a full re-fetch per keystroke in the note field. That is the one field on the payoff screen, and a laggy keyboard teaches people not to write in it.
- Suggested fix: Compute `prs` once into `@State` in `.task`/`onAppear`, using a `FetchDescriptor` for finished sessions older than this one. Drop the `@Query`.
- Verify by: Type in the summary note with seeded history (`-GTSeedSampleData`) under Instruments and confirm there are no `recordSets` calls per keystroke.

### LOG-14: Icon-only controls with lasting effects have no VoiceOver label, and the logger ignores Dynamic Type
- Severity: P3
- Category: bug
- Confidence: confirmed in code (the exact VoiceOver readout is likely, not checked)
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:956-963` (undo on a logged row), `:1557-1566` (rest bar ✕), `:741-746` (info); all text via `Theme.rounded`/`Theme.number`/`Theme.eyebrow`/`microCaps` (`GymTrackShared/Theme.swift:37-50`, fixed `.system(size:)`); `SessionDock.swift:203-204`
- What happens: The undo button, which un-logs the set and erases its rating, start and heart rate, falls back to the symbol's generic name. So does the rest bar's ✕, which ends the rest ("Close" at best). Every row's undo reads the same, with no set named. All logger text uses fixed point sizes (8-26 pt), so Larger Text has no effect. The dock's comment says its height is measured "because Dynamic Type changes it", but it cannot.
- Failure scenario: A VoiceOver user hears "Back, button" on each logged row and un-logs set 2 while trying to navigate. A user with Larger Text on gets 9-11 pt captions ("Times this set", effort details, "Rate") at the same size as everyone else.
- Suggested fix: `.accessibilityLabel("Undo set \(label)")` with a hint that it clears the log; "End rest" on the ✕; "About \(group.name)" on info. Longer term, make the `Theme` font helpers scale, for example `.system(size:)` with `relativeTo:` via `@ScaledMetric` or custom text styles, and fix the dock comment.
- Verify by: Run the logger with VoiceOver and the Accessibility Inspector at the largest text size.

### LOG-15: An exercise added by mistake cannot be taken out of the session; `removeExercise` has no caller
- Severity: P3
- Category: missing-feature
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Services/ActiveWorkout.swift:813-819` (`removeExercise`, which also drops the note), `GymTrack/Features/Session/ActiveWorkoutView.swift:559-577` (only Add set / Remove, floor of one set)
- What happens: The picker adds three sets per tap, and "Remove" stops at one set, so a wrong pick stays in the queue for the whole session. If it is the first incomplete exercise, it becomes "current" on the phone, the Lock Screen and the wrist. `close()` does drop it at the end, so the record is clean. The cost is friction mid-workout.
- Failure scenario: In a freestyle session the lifter picks "Incline Barbell Bench" instead of "Incline Dumbbell Press". The wrong exercise becomes current everywhere, and the wrist offers its set until the lifter re-focuses by hand every time an exercise completes.
- Suggested fix: Offer "Remove exercise" (destructive) in a context menu on the queue row when the group has no logged sets, calling the existing `removeExercise`. If `removeExercise` is not wanted, delete it.
- Verify by: Add a wrong exercise, remove it from the queue, and confirm that the watch mirror and Live Activity move on.
