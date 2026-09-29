> Detail file from the 2026-09-28 review. The index, the canonical severities and the duplicate map are in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md). Where this file disagrees with the index, the index wins. Line numbers refer to the working tree on 2026-09-28 (HEAD f5809ff plus the uncommitted GT fix pass).

# Session engine and data model: findings

Files read in full: GymTrack/Models/Entities.swift, GymTrack/Models/SessionClosing.swift, GymTrack/Models/SetContinuation.swift, GymTrack/Services/ActiveWorkout.swift, GymTrack/Services/RestTimer.swift, GymTrackShared/SetFeel.swift, GymTrackShared/SetLeadIn.swift, Tests/ActiveWorkoutStructureTests.swift. Excerpts traced: RootView.swift (lifecycle, watch commands, resume), WatchCommandCenter.swift (headless paths), WatchBridge.swift (metrics, update), WatchConnector.swift (send, logSet, undoSet), WatchPendingActions.swift, ActiveWorkoutView.swift (card, SetRow, finish/discard), SessionDock.swift, SessionSummaryView.swift (delete), TrainingStats.swift (lastPerformance, suggestion, PR), HealthKitService.swift (saveWorkout), ExerciseEditorView.swift (rename), BackupService.swift (export filter).

Side check: I compiled a small SwiftData probe in the scratchpad (macOS 26 SDK). In the same context, reading attributes or relationships of a model after `delete` and `save` did not trap; it returned the old values, or `[]` for a relationship not yet loaded. So `discard()` reading `session.id` after the delete (ActiveWorkout.swift:880) is not reported as a crash. SESS-08 is reported for stale data, not for a crash.

## Prior findings re-check
- GT-011: OK. `SessionFactory.build` normalises slots (ActiveWorkout.swift:64), `addExercise` appends to an existing group (781-811), headless `.addSet` uses max+1, and `ActiveWorkout.init` normalises legacy active sessions (111-113). Mixed-slot `precedesInSession` ordering holds for finished logs. The per-slot load handling that came with the fix is its own regression (SESS-01).
- GT-012: INCOMPLETE. The rep reset is applied only for `.increaseWeight` (ActiveWorkout.swift:40-44). `.deload` and `.repeatLoad` still seed last time's short reps. Example: 60 kg × [5,5,4] with an 8-12 range, rated Hard, opens today at 57.5 × 5/5/4, while the card says "back off and rebuild" at 8. Repeated slots skip the suggestion entirely (SESS-01).
- GT-013: OK. `apply` keeps the first snapshot for the same subject (668-687), and the test covers take, re-rate, take, undo (ActiveWorkoutStructureTests.swift:98-111).
- GT-021 (session-creation side): INCOMPLETE. `SessionFactory.build` still copies `item.name` verbatim (ActiveWorkout.swift:47). The fix (ExerciseEditorView.swift:270-277) only rewrites plan items on renames made from now on. Plan items renamed before this build, and the matching headless watch start (WatchCommandCenter.swift:72), keep producing sets under the old name forever. Resolving `item.catalog?.name ?? item.name` at creation would cover both.
- GT-005 (ActiveWorkout side): OK. `adoptWatchMetrics` requires `metrics.sessionID == session.id` (890), and `.metrics` for another session returns false so RootView's late-metrics path handles it (1057-1063).
- GT-008 (ActiveWorkout side): OK, with one dead condition. In `recordToHealth` (907), `|| WatchBridge.shared.liveMetrics != nil` is always false. `finish()` has already cleared `liveMetrics`, both through `update(session: nil, …)` (WatchBridge.swift:92) and `clearMetrics()`, before `recordToHealth()` runs. The 12 s wait therefore depends on `wasWatchDriven` alone. This is harmless, because `adoptWatchMetrics` sets that flag whenever matching metrics exist, and the cleanup queue covers the rest. But the comment overstates what the check detects.

## Findings

### SESS-01: Repeated plan slots now skip progression and history, and the per-slot loads the bypass protects are flattened on the first log
- Severity: P2
- Category: bug
- Confidence: confirmed (traced end to end; the regression test asserts the static loads)
- Location: `GymTrack/Services/ActiveWorkout.swift:21-31, 37-39` (`SessionFactory.build`), `ActiveWorkout.swift:313-323` (`carryLoadForward`), `ActiveWorkout.swift:676-685` (`apply(_ nudge:)`), `ActiveWorkout.swift:115-118` (`prescriptions`, first slot only), `GymTrack/Features/Session/ActiveWorkoutView.swift:874-877` (`suggestion`)
- What happens: when a catalog ID appears in more than one plan slot, `isRepeated` makes every row open at `item.targetWeightKg` and `targetRepsLow`, whatever the history says. The stated reason is "Repeated slots can prescribe different loads… One catalog-wide suggestion would flatten them". But `normalizeExerciseSlots` merges the slots into one group. The first `complete()` then runs `carryLoadForward`, which writes the logged weight onto every later unlogged, non-continuation row of that catalog ID, including the second slot's rows. A taken nudge also moves both slots. Meanwhile the card's suggestion is computed from the first slot and the merged history, so it names a different load from the rows.
- Failure scenario: plan day with Bench 2×6 @30 kg, Row, then Bench 3×10 @45 kg (the exact fixture in ActiveWorkoutStructureTests.swift:29-31, with last session 60×12). The session opens at [30,30,45,45,45] while the card says "Go to 62.5 kg". The lifter dials set 1 to 62.5 and logs it, and all four remaining rows become 62.5 kg, the back-off slot included. Next week it opens at 30/45 again, because progression never reaches repeated slots. A plan item added through DayEditorView has `targetWeightKg` 0, so a user who repeats an exercise without typing targets gets 0 kg on every row, every session.
- Suggested fix: pick one model and apply it everywhere. (a) Keep slots distinct: store a slot key (for example the `PlanItem.id`, or the first `setIndex` of the slot) and limit `carryLoadForward`, `nudge(after:)`/`apply` and the prescriptions lookup to that slot. Seed each slot from the same position in last session's merged sets rather than from a static target. (b) Merge fully: drop the `isRepeated` bypass and seed from `last[setIndex]` and the suggestion like any other exercise. Either way, the card's suggestion and the opening loads must agree.
- Verify by: extending ActiveWorkoutStructureTests to log set 0 of the fixture and asserting what the second slot's rows hold. Also assert that a second session built from the same plan after a logged session changes the opening load.

### SESS-02: Logging any set records a standing load offer as "declined", including for other exercises, drop rows and a manually taken rung, and undoing the log leaves the decline behind
- Severity: P2
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrack/Services/ActiveWorkout.swift:274-276` (`complete`), `ActiveWorkout.swift:325-340` (`uncomplete`), export at `BackupService.swift` (`loadNudge(of:)`, ~415)
- What happens: `if let standing = pendingNudge { subject(of: standing)?.recordLoadNudge(.declined, toKg: standing.toKg) }` runs for whatever set is logged. It does not check that the logged set is one the offer would move (same `catalogID`, not a continuation, `setIndex > fromIndex`), or that it was lifted at the old weight. `uncomplete` neither clears that record nor restores `pendingNudge`. The outcome is exported, and it is described as the autoregulation signal a coach reads.
- Failure scenario: (1) Superset: Bench set 1 is rated Easy at the top of the range, and the app offers bench 102.5 kg for the 2 remaining sets. The lifter logs a row set, and bench set 1 is filed `declined → 102.5` although no bench set has been lifted. The offer vanishes. (2) Drop: set 2 of 3 is rated Easy, the lifter continues it (`continueSet`) and logs the drop row, and set 3's offer is filed as declined. (3) The lifter dials set 2 to 102.5 by hand and logs it, and the record says "declined 102.5" next to a set lifted at 102.5. (4) A mis-tapped Log on set 2 followed by Undo leaves `declined` on set 1, and the offer cannot be brought back. That breaks rule 2.
- Suggested fix: in `complete`, settle the standing offer only when `set` is one of its targets. Record `.declined` only if `set.weightKg != standing.toKg`. When the weight equals the offered rung, record `.taken` or nothing. Otherwise leave `pendingNudge` standing. Keep an in-memory `implicitDecline: (loggedSetID, LoadNudge)`, so that `uncomplete(loggedSet)` calls `clearLoadNudge()` on the subject and restores `pendingNudge`.
- Verify by: a harness case with rate Easy, log a set of another exercise, and assert `loadNudgeOutcome == nil` and the offer still pending. A second case with rate Easy, log set 2, undo set 2, and assert no outcome and the offer restored.

### SESS-03: Duplicate watch set commands are re-applied; a repeated `.logSet` reverts a taken nudge and files a decline, and a repeated `.undoSet` can erase a re-log
- Severity: P2
- Category: bug
- Confidence: likely (the code path is confirmed; how often duplicates arrive depends on WatchConnectivity, and the codebase already says they happen: RootView.swift:389-391 "A live message can also be queued after its send fails, then arrive twice", and WatchConnector.swift:183-188 re-queues on any send error)
- Location: `GymTrack/Services/ActiveWorkout.swift:989-997` (`.logSet`), `1017-1020` (`.undoSet`), `1039-1043` (`.addSet`). The headless twin is in `WatchCommandCenter.swift` (`.logSet`, ~84-105, no `!isCompleted` guard).
- What happens: `.logSet` has no idempotence guard. A second copy for an already-logged set calls `complete()` again. Line 274 files any standing offer as declined, line 276 drops the undo for a taken nudge, `carryLoadForward` (280) rewrites later unlogged rows back to this set's weight, 279 and 300 restart a rest that an announced start had ended, and the PR check and haptic run again. `.undoSet` carries no stamp, so a delayed copy cannot tell which completion it meant. `.addSet` has no identity, so a duplicate adds a second row.
- Failure scenario: the wrist logs set 1 at 100 kg, the live send reports failure but was delivered, and a copy is queued. On the wrist the lifter rates Easy and takes the offer, so sets 2 and 3 go to 102.5 and `.taken` is recorded. The queued copy lands: sets 2 and 3 return to 100, `takenNudge` is gone, and the record still says `taken → 102.5`, so the lifter lifts 100 under a record claiming 102.5. Variant: undo set 2 on the wrist (duplicated), re-log it, and the late duplicate undo erases the re-logged set, which is then deleted at Finish.
- Suggested fix: make `.logSet` a no-op, apart from `pushToWatch()`, when `set.isCompleted` and `set.completedAt` matches `loggedMoment(loggedAt)` (reuse the 1 ms tolerance in `WatchSetRating.matches`). Add the completion stamp being undone to `.undoSet`, and unlog only when it matches `set.completedAt`. Give `.addSet` a wrist-generated set UUID, and ignore it if a row with that ID exists. Apply the same guards on the headless path.
- Verify by: a WatchCommandReliabilityTests case that applies `.logSet` twice through `ActiveWorkout.apply`, with a rating and a taken nudge in between, and asserts weights and `loadNudgeOutcome` unchanged. A second case sends undo, re-log, then the stale undo, and asserts the set stays logged.

### SESS-04: Correcting a logged set restamps it as logged now, rewriting when it happened
- Severity: P2
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrack/Features/Session/ActiveWorkoutView.swift:956` (a completed row offers only Undo), `GymTrack/Services/ActiveWorkout.swift:325-340` (`uncomplete` also stops whatever rest is running), `ActiveWorkout.swift:254-256` (`complete` stamps `.now`), `GymTrack/Models/Entities.swift:255-282` (gaps sorted by `completedAt`)
- What happens: a completed row has no way to fix a typo in its weight or reps. The only path is Undo, which calls `unlog()` and clears `completedAt`, `startedAt`, rating and heart rate, followed by Log, which stamps `completedAt = .now`. So the corrected set is recorded as performed at the moment of the fix. `uncomplete` also stops the running rest, even when that rest belongs to a later set. `lastLoggedSetID` moves to the old set too, and `carryLoadForward` runs again from it.
- Failure scenario: sets 1-3 are logged at 10:00, 10:03 and 10:06, and a rest is running. At 10:07 the lifter notices set 1 says 8 reps instead of 10, then undoes, fixes and re-logs it. The record now has set 1 at 10:07, after set 3. `setGaps` loses set 2's rest and gains a 1-minute "rest" from set 3 to the correction, the export shows set 1 as the last lift, and set 1's heart-rate window is the correction minute. The rest the lifter was watching is gone, and the effort question jumps back to set 1. Everything the coach reads from the timing is wrong, and it looks measured.
- Suggested fix: add an in-place edit for a completed row: tap the value, adjust with the keypad, write `weightKg`/`reps`/`seconds`, re-run the PR check and `save()`. Keep Undo for "I didn't do this set". In `uncomplete`, stop the rest only when `set.id == lastLoggedSetID`.
- Verify by: a harness case that logs three sets, edits set 1's reps through the new path, and asserts `completedAt` is unchanged and `setGaps` is identical. A manual check that the rest keeps running.

### SESS-05: "Remove" on an exercise card deletes the last row even when it is a logged set, with no confirmation or undo
- Severity: P2
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrack/Services/ActiveWorkout.swift:763-769` (`removeLastSet`), `GymTrack/Features/Session/ActiveWorkoutView.swift:567-575` (button shown whenever `group.sets.count > 1`)
- What happens: `guard group.sets.count > 1, let last = group.sets.last else { return }; context.delete(last)` ignores `isCompleted`. The button sits beside "Add set" on every card, including completed ones. The doc comment says it is "the pair of addSet, undoing exactly what that did", and `addSet` only ever adds an unlogged row.
- Failure scenario: Bench is complete (3/3 logged, card dimmed). Reaching for "Add set", the lifter taps "Remove", and logged set 3, with its rating, heart rate and nudge outcome, is deleted and saved. The card still reads "Exercise complete" and the earlier rows are collapsed, so the loss is easy to miss. Variant: set 2 was undone while set 3 stays logged, and Remove deletes logged set 3 instead of the empty set 2.
- Suggested fix: make `removeLastSet` delete the last unlogged row (`group.sets.last(where: { !$0.isCompleted })`), and hide the button when there is none. Deleting a logged lift should be a separate, confirmed action.
- Verify by: a harness case on a fully logged group, where `removeLastSet` leaves the count unchanged. A mixed group case, where the unlogged row is removed and the logged one kept.

### SESS-06: An announced start abandoned for another exercise survives and pairs with a much later log, producing a false time under tension
- Severity: P3
- Category: data-rule
- Confidence: likely
- Location: `GymTrack/Services/ActiveWorkout.swift:189-192` (`focus`), `254-264` (`complete` only checks this set's own start), `GymTrack/Models/Entities.swift:655-658` (`timeUnderTension`)
- What happens: `startedAt` on an unlogged set is cleared only by `cancelStart`, by a log inside the count-in, or by `unlog`. Moving to another exercise, or logging a different set, leaves it in place. `timeUnderTension` checks only that `completedAt > startedAt`, and the export writes `startedAt` as "the lifter said so". Rest gaps and heart-rate attribution guard against this (`begun > previous.logged`), but the set's own length and the exported stamp do not.
- Failure scenario: the lifter taps Start on bench set 2, finds the bench taken, switches to rows, logs three row sets, returns, and logs bench set 2 twelve minutes later. The row shows a 12:00 tension badge, and the export carries a start twelve minutes before the log.
- Suggested fix: in `complete(set)`, and on the headless and watch-finish paths, clear `startedAt` on every other unlogged set whose start is earlier than this log. A start that another logged set has overtaken cannot still be under way. Or clear it in `focus(on:)` when leaving that set's exercise.
- Verify by: a harness case that announces set A, logs set B of another exercise, then logs A, and asserts `A.startedAt == nil` and `timeUnderTension == nil`.

### SESS-07: The rest timer plays a stale "rest over" chime on return to the app, and a relaunch loses the rest while its notification still fires
- Severity: P3
- Category: bug
- Confidence: confirmed (chime); likely (relaunch)
- Location: `GymTrack/Services/RestTimer.swift:96-117` (`scheduleTicker`, `refresh`, `finish`), `GymTrack/Services/ActiveWorkout.swift:106-143` (`init` never restores a rest)
- What happens: the ticker is a RunLoop timer that does not fire while the app is suspended. When the lifter unlocks the phone after the rest ended in the background, which is when the "Rest over" notification was already delivered, the first tick finds `remaining <= 0` and calls `finish()`. That plays `AudioServicesPlaySystemSound(1057)` and a success haptic, possibly minutes late and mid-set. Separately, after iOS or a force-quit kills the app mid-rest, `ActiveWorkout.init` starts with no rest, but the pending `UNNotificationRequest` still fires. The wrist mirror is also re-pushed with no rest, which the watch reviewer should check.
- Suggested fix: in `refresh()`, play the sound and haptic only if the end passed within the last second or two. Otherwise stop silently. In `ActiveWorkout.init`, restore the rest from the last logged set (`completedAt + restSeconds`) through `restTimer.restore(endingAt:totalSeconds:)`, which already drops a rest that is over.
- Verify by: a manual check that a 30 s rest backgrounded for 60 s gives no chime on return. Kill the app mid-rest, relaunch, and confirm the countdown continues to the same end.

### SESS-08: A past session deleted mid-workout stays in the running logger's history, PR baseline and "last time" hints
- Severity: P3
- Category: bug
- Confidence: confirmed (stale values; the SwiftData probe shows deleted models keep returning their old values in the same context); crash on iOS 17: speculative
- Location: `GymTrack/Services/ActiveWorkout.swift:97, 104, 348-356` (`history`, `lastPerformances`, `recordBaseline` captured once), delete at `GymTrack/Features/Session/SessionSummaryView.swift:416-424` (`SessionDetailView`, reachable from Today while the workout is minimised)
- What happens: `ActiveWorkout` keeps the `history` array, per-exercise last-performance `SetLog`s and a lazily built record baseline. None of them is refreshed when a past session is deleted.
- Failure scenario: mid-workout, the lifter minimises, opens last week's session with a mistyped 500 kg bench and deletes it. Back in the logger, the "last: 500 × 5" hint remains. If a set had already been logged before the delete, the PR baseline still holds 500 kg and no bench PR can fire today. `addExercise` still walks the deleted session.
- Suggested fix: rebuild `history`, `lastPerformances` and `recordBaseline` when the session store changes. For example, give `ActiveWorkout` a `refreshHistory(_:)` that RootView calls from `.onChange(of: sessions.count)`. Or filter `isDeleted`/`modelContext == nil` rows as `planItem(for:)` already does.
- Verify by: on the simulator, log a PR candidate, delete the prior best session from Today, log again, and confirm the hint and the PR check reflect the deletion.

### SESS-09: Finishing with nothing logged keeps an empty session in history and the export, unlike the other two end paths
- Severity: P3
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrack/Services/ActiveWorkout.swift:855-871` (`finish`), `GymTrack/Models/SessionClosing.swift:60-69` (`close`), compared with `GymTrack/App/RootView.swift:478-479` (the stale-session path deletes an empty session) and `BackupService.swift:296` (export keeps every finished session)
- What happens: `close` deletes every unlogged row, stamps `endedAt` and keeps the session even when no set survives. The launch path treats the same state as "nothing happened" and deletes it, and `WatchSessionRecovery` discards untouched sessions. SessionClosing's own header warns that paths closing different amounts is how a record ends up half closed.
- Failure scenario: the lifter starts the planned day, gets interrupted, and taps Finish instead of Discard. The alert says "5 sets not logged — they'll be dropped". The export then carries a titled, timed "Push day" with zero sets, which a coach counting sessions per week will count.
- Suggested fix: in `close(at:in:)`, or in both `finish` paths, delete the session when `completedSets` is empty (after `applyWatchFinish`), and show no summary. Or have the finish alert offer Discard when nothing is logged.
- Verify by: a harness case where `close` on a session with no completed sets leaves nothing in the store. A manual check of Finish with nothing logged.

## Test gaps worth adding (covered by the findings above)
- `ActiveWorkout.apply(.logSet)` / `.undoSet` duplicate delivery (SESS-03). There is currently no test through `ActiveWorkout`.
- `complete()` settling offers across exercises and continuations, and `uncomplete` reverting the settlement (SESS-02).
- `removeLastSet` on a logged tail row (SESS-05). The existing test only removes an unlogged row.
