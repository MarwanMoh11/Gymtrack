> Detail file from the 2026-09-28 review. The index, the canonical severities and the duplicate map are in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md). Where this file disagrees with the index, the index wins. Line numbers refer to the working tree on 2026-09-28 (HEAD f5809ff plus the uncommitted GT fix pass).

# watchOS app: findings

Files read in full: GymTrackWatch/GymTrackWatchApp.swift, GymTrackWatch/WatchConnector.swift, GymTrackWatch/WatchWorkoutRecorder.swift, GymTrackWatch/WatchRestTimer.swift, GymTrackWatch/WatchHaptics.swift, GymTrackWatch/Views/WatchComponents.swift, GymTrackWatch/Views/WatchControlsView.swift, GymTrackWatch/Views/WatchIdleView.swift, GymTrackWatch/Views/WatchLoggerView.swift, GymTrackWatch/Views/WatchMetricsView.swift, GymTrackWatch/Views/WatchRootView.swift, GymTrackWatch/Views/WatchSetFeelView.swift, GymTrackWatch/Info.plist, GymTrackWatch/GymTrackWatch.entitlements, GymTrackShared/WatchLink.swift, GymTrackShared/WatchPendingActions.swift, GymTrackShared/WatchRatingOutbox.swift, GymTrackShared/WatchSetRating.swift.
Read in excerpts: GymTrack/Services/WatchCommandCenter.swift, GymTrack/Services/WatchBridge.swift, GymTrack/Services/ActiveWorkout.swift, GymTrack/App/RootView.swift, GymTrack/Models/SessionClosing.swift, GymTrack/Models/Entities.swift (grouping), GymTrack/Services/HealthKitService.swift, GymTrackShared/SetLeadIn.swift, Tests/WatchCommandReliabilityTests.swift.

Availability: `WATCHOS_DEPLOYMENT_TARGET = 10.0`. Every API the watch target uses (`@Observable`, `containerBackground(_:for:)`, `buttonRepeatBehavior`, `NavigationStack`, `Task.sleep(for:)`, async HealthKit calls) exists on watchOS 10. No availability finding.

## Prior findings re-check
- GT-002 (watch side): OK. `finishBatch(for:)` snapshots the unconfirmed logs, undos, starts, cancels and ratings before the recorder closes (`WatchRootView.swift:121`, `WatchPendingActions.swift:24-32`) and travels inside `.finishSession`. Queued logs that land later are refused by `set.session?.isActive == true` (`WatchCommandCenter.swift:85`). The opposite order, where the phone finishes before the queued wrist logs land, is still open (WATCH-02).
- GT-006: REGRESSION. The watch now honors `healthEnabled` (`WatchRootView.swift:96-102`), but it does so by never starting an HKWorkoutSession. That also removes background runtime, the rest-over haptic with the wrist down, and heart rate (WATCH-07).
- GT-007: OK. A nil session is saved only when `endedSession` names the recorder's session with reason `.finished` and there is no phone workout (`WatchRootView.swift:106-111`). Both phone discard paths push `.discarded` (`ActiveWorkout.swift:880`, `WatchCommandCenter.swift:217`).
- GT-008 (watch side): OK for the race it describes. `phoneHealthWorkoutID` makes a late watch discard its samples (`WatchRootView.swift:109`, `WatchBridge.swift:98-103`). A separate duplicate path exists after a wrist Finish (WATCH-01), and a watch save caused by a phone Finish carries no session identity (WATCH-15).
- GT-009: INCOMPLETE. `end()` now resets average, max, energy and `lastMetricsSentAt` (`WatchWorkoutRecorder.swift:158-167`). The builder and session delegate callbacks are not checked against the current builder, so a late callback from the ended workout fills those fields again (WATCH-08).
- GT-010: OK. `pending` and `ratings` persist on every change (`WatchConnector.swift:30-45`), are reloaded in `init` (`48-58`), and a cached context never reconciles them (`304`). Caveat: a nil mirror discards the persisted logs outright (WATCH-02).

## Findings

### WATCH-01: A wrist Finish or Discard with the phone out of range leaves the session live on the watch, and a relaunch restarts recording for it, which produces a duplicate Health workout
- Severity: P1
- Category: bug
- Confidence: likely (the code path is traced end to end; the trigger needs a watch relaunch, or a mirror reply that overtakes the queued Finish, before the phone processes it)
- Location: `GymTrackWatch/Views/WatchRootView.swift:119-147` (`end`, `discard`), `:93-97` (`syncRecorder`), `GymTrackWatch/WatchConnector.swift:72-96` (`session`), `:358-376` (activation), `GymTrackWatch/WatchWorkoutRecorder.swift:107` (backdated start), `GymTrack/Services/HealthKitService.swift:249-260` (`acceptWatchWorkout`)
- What happens: Nothing on the watch records that it ended session S. `end()` saves Health workout W1, queues `.finishSession` and sets `isEnding = false`. `mirror.session` and `pending` still hold S, so `connector.session` still returns S until the phone's nil mirror arrives. On relaunch, the cached application context still describes S. If the phone is unreachable, it is shown at once (`waitingForFreshMirror = session.isReachable`). If the phone is reachable, the `requestMirror` reply can overtake the queued Finish, because `sendMessage` and `transferUserInfo` are not ordered. `syncRecorder` then calls `startIfNeeded(for: S)`, and the recorder begins a new HKWorkoutSession backdated to `S.startedAt` (`min(snapshot.startedAt, .now)`).
- Failure scenario: The phone is in a locker. The lifter taps Finish on the wrist, and W1 is saved with its metadata. The watch app is suspended and then terminated on the walk back. When the lifter raises the wrist near the phone, the relaunched app shows S and starts W2. The queued Finish lands, and the phone closes S with W1's ID. The phone pushes `endedSession(S, .finished, phoneHealthWorkoutID: nil)`, so `shouldSave` is true and W2 is saved, covering S.startedAt up to now. The watch then sends `.metrics(W2)`. `acceptWatchWorkout` queues cleanup of W1, the correct record, and keeps W2, which has no metadata and the wrong end time. `apply`/`applyLateMetrics` overwrite S's average HR, max HR and energy with W2's values. While W2 runs, it also sends `.metrics` for S every 5 s, and each one overwrites the finished session again. An offline wrist Discard has the same effect: the relaunched watch shows the discarded session as live and records it until the queued discard lands.
- Suggested fix: Persist a local tombstone in `WatchConnector` (for example `endedLocally: UUID?`, set in `WatchRootView.end`/`discard` before the recorder closes). Make `session` return nil while `mirror.session?.sessionID` matches it, and clear the tombstone when a mirror arrives without that session. Make `WatchWorkoutRecorder.startIfNeeded` refuse the tombstoned ID. On the phone, `acceptWatchWorkout` should not replace an existing watch-provided ID with a later one for the same session.
- Verify by: A shared-logic test that runs a tombstone plus a cached mirror of S and expects no session and no recorder start. On devices: finish on the wrist out of range, force-quit the watch app, relaunch, bring the phone back, and confirm Health holds exactly one workout for S.

### WATCH-02: Sets logged on the wrist out of range are erased when the phone finishes before the queued logs land
- Severity: P1
- Category: bug
- Confidence: likely (traced; needs the phone Finish to beat the `transferUserInfo` drain after reconnection)
- Location: `GymTrackWatch/WatchConnector.swift:309-316` (`reconcile(with: nil)`), `GymTrack/Models/SessionClosing.swift:60-69` (`close`), `GymTrack/Services/WatchCommandCenter.swift:85` (`.logSet` guard), `GymTrack/Services/ActiveWorkout.swift:990`
- What happens: The phone's `close` deletes every uncompleted row. When the finish mirror reaches the watch, `reconcile(with: nil)` calls `pending.clear()` unconditionally, which throws away the persisted wrist logs that GT-010 kept. The queued `.logSet` commands then land on deleted rows. The headless path returns early because `setLog(id:)` finds no active session. The UI path's `guard let set = session.sets.first(...) else { return true }` swallows them silently.
- Failure scenario: The phone is in a locker. The lifter logs their last three sets on the watch; they are queued, and the watch shows them done with "Sets waiting for your phone". At the locker they open the phone before WatchConnectivity has drained the queue. The phone shows those sets as unlogged, and Finish warns that 3 unlogged sets will be dropped. The lifter reads this as leftover plan sets and finishes. The three rows are deleted, the watch clears its record of them, and the queued logs land on nothing. Three sets that were done are gone from the export.
- Suggested fix: Make late wrist work attach to its finished session. When a nil mirror arrives with `endedSession?.sessionID == pending.sessionID` and `pending.logs` is not empty, send a new `WatchCommand.lateLogs(sessionID:, rows:)` before clearing. Each row carries what the phone needs to recreate it, taken from the last snapshot: catalogID, name, order, index, tracking, weight, reps, seconds, startedAt and completedAt. The phone inserts rows only into that finished session and only for set IDs it no longer has. Alternatively, have the phone's Finish ask a reachable watch for its `finishBatch` before `close`.
- Verify by: A SwiftData harness in the style of `Tests/WatchCommandReliabilityTests.swift`: close a session with an untouched row, apply the late-log command for that row's ID, and expect a completed row with the wrist timestamp. On devices: log out of range, then finish on the phone immediately on reconnect.

### WATCH-03: A wrist Finish carries no timestamp, so the phone records the session as ending when it heard about it
- Severity: P2
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrackShared/WatchLink.swift:308-315` (`WatchFinishBatch` has no end moment), `GymTrackWatch/Views/WatchRootView.swift:119-135`, `GymTrack/Services/WatchCommandCenter.swift:249-253` (`finish` calls `session.close(in: context)`), `GymTrack/App/RootView.swift:330-336` then `ActiveWorkout.swift:860`, `GymTrack/Models/SessionClosing.swift:60` (`close(at moment: Date = .now, …)`)
- What happens: The protocol stamps `logSet` and `announceStart` with the wrist's clock so that a command waiting in the queue does not describe the walk back (see the long comment at `WatchLink.swift:322-334`). Finish does not get the same treatment. Both phone paths close with `.now`, which is the moment the queued command arrived.
- Failure scenario: The lifter finishes on the wrist at 18:40 with the phone in a locker, showers, and returns to the phone at 19:05. The session's `endedAt` is 19:05. The export shows a workout 25 minutes longer than it was, and so do TrainingStats durations. If the watch did not save to Health (save failed, or recording disabled), the phone's fallback `saveWorkout` uses `startedAt…endedAt` (`HealthKitService.swift:162-163`) and writes the inflated interval to Health. The watch's own W1 ends at 18:40, so the app and Health also disagree.
- Suggested fix: Add `endedAt: Date?` to `WatchFinishBatch` (optional so queued old payloads decode) and stamp it in `WatchRootView.end()` at the tap. On the phone, close at `max(WatchCommand.loggedMoment(batch.endedAt), last completedAt)` in both `WatchCommandCenter.finish` and the RootView path (give `ActiveWorkout.finish` a moment parameter).
- Verify by: Extend `WatchCommandReliabilityTests`: apply a batch with `endedAt` 20 minutes ago and assert `session.endedAt` equals it, and that a missing stamp falls back to now.

### WATCH-04: Live heart-rate metrics are queued through `transferUserInfo` when out of range; hundreds pile up, and if they land after Finish they overwrite the session's final HR and energy
- Severity: P2
- Category: bug
- Confidence: likely (the queueing is confirmed; the overwrite depends on cross-channel delivery order)
- Location: `GymTrackWatch/WatchWorkoutRecorder.swift:213-217` (`sendMetricsIfDue`), `GymTrackWatch/WatchConnector.swift:168-192` (`send`, fallback at 187 and 190), `GymTrack/Services/WatchCommandCenter.swift:226-232` and `262-274` (`apply`), `GymTrack/App/RootView.swift:417-431` (`applyLateMetrics`)
- What happens: Each builder callback sends `.metrics(currentMetrics)` at most every 5 s. `send` falls back to `transferUserInfo` whenever the phone is unreachable, and again when a live message fails. An hour with the phone in a locker queues about 720 "live" snapshots. They all drain on reconnection, and each one wakes the phone and on the headless path runs a full unpredicated session fetch plus a save. On the phone, a `.metrics` for a finished session is treated as a hand-over: `averageHeartRate`, `maxHeartRate` and `activeEnergyKcal` are assigned, not merged.
- Failure scenario: Out of range for the middle of the workout, back in range for the last set. The wrist Finish goes out as a live message and lands first, and the phone stores avg 131, max 174, 410 kcal. The backlog drains afterwards, and the last queued snapshot, from before reconnection, wins: avg 127, max 168, 352 kcal. The coach export now reports numbers from partway through the workout as the session's measured totals.
- Suggested fix: Never queue live metrics. In `WatchConnector.send`, drop `.metrics` without a `healthWorkoutID` when unreachable, and don't requeue them on `sendMessage` failure; only the final hand-over needs guaranteed delivery. On the phone, have `apply`/`applyLateMetrics` accept metrics for a closed session only when `healthWorkoutID != nil`.
- Verify by: A unit test on the phone's apply rule (a partial metric after close leaves the fields unchanged). On devices: watch `WCSession.outstandingUserInfoTransfers.count` stay flat during an out-of-range workout.

### WATCH-05: Log and undo take two unordered channels, so an undo can be overtaken by its own log, or a stale undo can erase a re-log
- Severity: P2
- Category: data-rule
- Confidence: likely
- Location: `GymTrackWatch/WatchConnector.swift:168-192` (`send`), `:233-246` (`undoSet`), `:323-331` (reconcile keeps the overlay but never resends), `GymTrackShared/WatchLink.swift:335` (`undoSet` carries no completion identity), `GymTrack/Services/WatchCommandCenter.swift:147-157`
- What happens: A command goes by `sendMessage` if the phone is reachable at that instant, otherwise by `transferUserInfo`. WatchConnectivity orders only within the userInfo queue. At the edge of range, a later command can reach the phone before an earlier one. `.undoSet(id:)` unlogs whatever completion the row currently has, because unlike `WatchSetRating` it carries no `completedAt`.
- Failure scenario: (a) Out of range, the lifter mis-taps Log set on set 4 (queued) and taps Undo just as the phone comes back (live). The undo lands first and does nothing, then the queued log arrives and completes set 4. The watch keeps `undos = {4}` because the phone shows it completed, so the two screens disagree and "Sets waiting for your phone" never clears. If the session is finished on the phone, the mis-tap is in the record, violating rule 2. (b) Out of range the lifter undoes set 4 (queued) and re-logs it with corrected reps as the phone returns (live). The log lands, then the stale undo erases it. The watch keeps its pending log forever, and a phone-side Finish deletes the row.
- Suggested fix: Keep one order per session. In `send`, use `sendMessage` only when `WCSession.default.outstandingUserInfoTransfers.isEmpty`; otherwise queue behind the backlog with `transferUserInfo` (WATCH-04 keeps that backlog short). Add the completion moment being taken back to `undoSet`, and have the phone ignore an undo whose moment doesn't match `set.completedAt`, the same way `rateSet` does.
- Verify by: A harness test that applies `undoSet(4, completedAt: t1)` after a log stamped t2 and expects set 4 to stay completed. Also a connector test that a command sent with outstanding transfers goes through `transferUserInfo`.

### WATCH-06: A session that ends while the recorder is still starting leaves an orphaned HKWorkoutSession running until the next workout
- Severity: P2
- Category: bug
- Confidence: likely
- Location: `GymTrackWatch/WatchWorkoutRecorder.swift:79-120` (`startIfNeeded`, awaits at 92 and 109, state assigned at 111-115), `:127-169` (`end`, no reentrancy guard), `GymTrackWatch/Views/WatchRootView.swift:69-71`, `:103`
- What happens: `isRunning`, `session` and `sessionID` are assigned only after `requestAuthorization()` and `beginCollection` return. When the mirror drops the session mid-start, `.task(id:)` cancels the old task and runs `syncRecorder` again. That run sees `recorder.isRunning == false` and does nothing. The cancelled `startIfNeeded` never checks cancellation, so it completes and sets `isRunning = true` for a session that no longer exists, and no future key change stops it until another session starts. `requestAuthorization` can suspend for as long as the first-use Health sheet stays unanswered. Separately, two overlapping `end()` calls (a second key change during an `end`) can race `discardWorkout()` against `finishWorkout()`.
- Failure scenario: A first-time user starts a workout on the phone, and the watch shows the Health permission sheet, which they leave. They train and finish on the phone. Later they tap Allow. The watch starts recording S (already finished) and keeps the HR sensor and workout runtime on for the rest of the day. Every 5 s it sends `.metrics` for S, and `applyLateMetrics`/`apply` overwrite S's average and max HR with the day's readings and its energy with a growing all-day total. The same happens with a mis-tapped phone Start discarded within about a second while the watch is still starting.
- Suggested fix: Make the start conditional on what is still wanted. `syncRecorder` sets `recorder.wantedSessionID` (nil in the end branch, and when Health is off), and after each `await` `startIfNeeded` checks `wantedSessionID == snapshot.sessionID && !Task.isCancelled`; if not, it calls `session.end()` and `builder.discardWorkout()` on what it built. Add an `isEnding` guard in `end()` so a second call waits for, or returns, the first call's result.
- Verify by: A recorder test with an injectable store stub: start, clear the wanted ID during the await, and expect no running session. On devices: start then discard within one second and confirm the watch shows no workout indicator.

### WATCH-07: With "Save workouts to Health" off, the watch loses its workout runtime, so the rest-over tap, staying on screen between sets, and heart rate all stop
- Severity: P2
- Category: bug
- Confidence: likely (the code path is confirmed; the runtime consequences are documented watchOS behavior and need a device)
- Location: `GymTrackWatch/Views/WatchRootView.swift:96-103`, `GymTrackWatch/Info.plist` (`WKBackgroundModes` = `workout-processing` only), `GymTrackWatch/WatchRestTimer.swift:98-114`, `GymTrackWatch/Views/WatchMetricsView.swift:86-88`
- What happens: The GT-006 fix skips `startIfNeeded` entirely when `healthEnabled` is false. The HKWorkoutSession was the watch's only background execution. Without it, the app is suspended when the wrist drops: the 0.25 s ticker stops, `WatchHaptics.restOver()` is never played, and the app returns to the clock after the system timeout, so each wrist raise shows the watch face rather than the logger. No heart rate is collected, so the phone gets no session HR and per-set HR has only background samples. Because the end branch is gated on `recorder.isRunning` (line 103), a phone Finish also no longer stops the watch's local rest. The rest then buzzes after the workout is over. The metrics page says "Heart rate starts when the workout session does," which is never true in this mode.
- Failure scenario: A user turns off Save workouts to Health but keeps Heart rate & energy on. They log a set on the wrist and lower their arm for a 2-minute rest. No tap comes at the end of the rest. When they raise the wrist, the watch face is showing, and the session has no average or max HR.
- Suggested fix: Keep the workout session and drop only the save. When `healthEnabled` is false, still call `startIfNeeded`, and end every path with `discardingSamples: true` (the end branch already computes `shouldSave`, and `end()` passes `!healthEnabled`). Drop the `else if recorder.isRunning` discard on line 98 so the runtime survives a toggle. Confirm on a device what `discardWorkout()` leaves in Health. Separately, stop the rest in the end branch whether or not the recorder is running.
- Verify by: A physical watch with the setting off: rest-over haptic with the wrist down, app still frontmost on raise, no workout in Health, HR present on the phone session.

### WATCH-08: Delegate callbacks are not matched to the current builder, so a late callback from the ended workout carries its HR into the next one (GT-009 incomplete)
- Severity: P2
- Category: data-rule
- Confidence: likely (the missing identity check is confirmed; whether HealthKit delivers after `session.end()` needs a device, and the discard path has no `await` between `session.end()` and the reset)
- Location: `GymTrackWatch/WatchWorkoutRecorder.swift:245-248` (`didCollectDataOf`), `:189-208` (`update`), `:224-238` (session state delegate), `GymTrackShared/WatchLink.swift:288` (`max` merge), `GymTrack/Services/ActiveWorkout.swift:889-898` (`adoptWatchMetrics`)
- What happens: Every callback hops to the MainActor and applies `workoutBuilder`'s statistics without checking `workoutBuilder === self.builder`. The state delegate sets `isRunning` from any session's transition. A callback from workout A that runs after `end()` resets the fields puts A's heart rate, average, max and energy back. They then survive until B's builder reports each type. The next `sendMetricsIfDue` tags them with B's `sessionID`, and the phone's `merging` keeps `max(maxHeartRate)`, so A's max sticks.
- Failure scenario: The handover in `startIfNeeded` (`end(discardingSamples: true)` then start B), or A ending shortly before B begins. B's first callback is energy only, so the payload `{sessionID: B, avg: A's 142, max: A's 181}` goes to the phone. A phone-side Finish of B writes max HR 181 through `adoptWatchMetrics` for a session that peaked at 160. A stray `.ended` from A can also set `isRunning = false` while B runs, which hides B from every `recorder.isRunning` gate in `syncRecorder`.
- Suggested fix: In both delegate extensions, ignore any callback whose `workoutBuilder`/`workoutSession` is not identical to `self.builder`/`self.session`, captured before the MainActor hop. Also have the phone's live merge replace `maxHeartRate` rather than max it across what should be a single session.
- Verify by: A test that calls `update` with a builder that is not the current one and expects the fields unchanged. On devices: two workouts in one process, checking the phone's max HR for the second.

### WATCH-09: The watch has no app delegate, so a crash mid-workout is never recovered and a phone auto-launch is never given its workout configuration
- Severity: P2
- Category: bug
- Confidence: likely (absence confirmed with `grep`; the HealthKit consequences are speculative until tested on a device)
- Location: `GymTrackWatch/GymTrackWatchApp.swift:3-19` (no `@WKApplicationDelegateAdaptor`), `GymTrackWatch/WatchWorkoutRecorder.swift:32` (`sessionID` held only in memory), `GymTrack/Services/HealthKitService.swift:131-142` (`startWatchApp`)
- What happens: `handleActiveWorkoutRecovery()` and `handle(_ workoutConfiguration:)` are not implemented anywhere. After a crash during a workout, watchOS relaunches the app to recover the running session. Here nothing calls `recoverActiveWorkoutSession`. The recorder builds a fresh session when the mirror arrives, and the collected builder of the crashed session is never finished. When the phone calls `startWatchApp(with:)`, the app is launched, but recording waits for WatchConnectivity activation, the fresh-mirror reply and a SwiftUI `.task`, which may never run in a background launch. That defeats the "recorded from the first set" intent at `ActiveWorkout.swift:969-975`.
- Failure scenario: The watch app crashes 40 minutes into a session. On relaunch it records a new session backdated to `startedAt`. Health ends up with either no record of the first 40 minutes of heart rate, or a failed start if the system still holds the old session. Auto-launch from the phone leaves the watch app suspended until the wrist is raised, so the first sets have no dense HR.
- Suggested fix: Add a `WKApplicationDelegate` via `@WKApplicationDelegateAdaptor`. `handleActiveWorkoutRecovery` calls `store.recoverActiveWorkoutSession`, re-attaches the delegates, and restores `sessionID` from a value the recorder persists at start. `handle(_ workoutConfiguration:)` starts the recorder immediately and adopts the GymTrack session ID when the mirror arrives.
- Verify by: On a device, kill the watch app from Xcode mid-workout, relaunch, finish, and check Health holds one continuous workout. Start on the phone with the watch wrist-down and check for HR samples from the first set.

### WATCH-10: A session nobody finishes keeps the watch recording for up to 12 hours, then the whole recording is thrown away
- Severity: P2
- Category: missing-feature
- Confidence: confirmed
- Location: `GymTrackWatch/WatchConnector.swift:79` (12-hour guard), `GymTrackWatch/Views/WatchRootView.swift:103-111` (a nil `endedSession` means discard), `GymTrack/App/RootView.swift:476-489` (the phone closes a stale session at next launch with no Health write and no end push), `GymTrackWatch/WatchWorkoutRecorder.swift` (no inactivity handling)
- What happens: The recorder runs for as long as the phone keeps the session active. Nothing on either device ends a session left open. At the 12-hour mark, the next re-render of the watch hides the session. `endedSession` is nil, so `shouldSave` is false and the entire beat-by-beat recording is discarded. The phone, on its next launch, closes the session at the last logged set, but it writes no Health workout and pushes no end. While the phone still holds the stale session, the wrist cannot start a new one: `.startToday` answers with the stale session, the watch hides it, and the Start button spins for 8 s and resets.
- Failure scenario: The lifter logs 18 sets and leaves without tapping Finish. The watch stays in workout mode, with the high-rate HR sensor and the app pinned, and drains the battery overnight. The next morning the recording is discarded, and the real workout never reaches Health. If the lifter instead notices at 21:00 and finishes, the session and the Health workout both claim three hours.
- Suggested fix: With zero taps, and without prompting (rule 3): when no set has been logged or started for a threshold (for example 45 minutes), end the watch's builder at the last completed set's time and save it, as a normal finish would. Tell the phone through a new command so it can close at the same moment. The phone's stale-close path should push `endedSession(.finished)` and run `recordToHealth`.
- Verify by: A test of the idle decision with an injected clock. On devices: leave a session open past the threshold and check that one Health workout ends at the last set.

### WATCH-11: Start, rest, add-set and focus commands carry no session or time, and act on whatever the phone holds when they finally land
- Severity: P3
- Category: bug
- Confidence: confirmed
- Location: `GymTrackShared/WatchLink.swift:319-352`, `GymTrackWatch/Views/WatchIdleView.swift:156-159`, `GymTrack/Services/WatchCommandCenter.swift:60-80`, `GymTrack/Services/ActiveWorkout.swift:1035-1055`
- What happens: Offline, `.startToday`/`.startFreestyle` wait in the userInfo queue with no expiry. The idle screen promises "It starts the session as soon as it's back". `.startRest`, `.extendRest` and `.stopRest` are applied by the UI path to the current rest. `.addSet` and `.focusExercise` apply to whichever session is active. Each wrist raise while offline also queues a `.requestMirror` (`WatchRootView.swift:86-88`), and each of those forces a push when it lands.
- Failure scenario: The phone is left at home. The lifter taps Start, gives up after 8 s, and trains without logging. When they get home, the phone builds a session stamped "now", and the next time the watch app runs it starts an HKWorkoutSession for it. An old queued "Start rest" delivered on reconnection starts a phantom rest on the phone, and the watch mirrors it and buzzes at its end.
- Suggested fix: Stamp start commands with the tap time and have the phone refuse any older than a few minutes. Add `sessionID` to `addSet`/`focusExercise`/rest commands and reject mismatches. Don't queue rest or `requestMirror` commands when unreachable; the wrist owns the rest in that case.
- Verify by: A harness test that feeds a start stamped 2 hours ago and expects no session.

### WATCH-12: The rest countdown re-renders the whole logger four times a second, and a rest that had already ended buzzes when it arrives in a mirror
- Severity: P3
- Category: performance
- Confidence: confirmed
- Location: `GymTrackWatch/WatchRestTimer.swift:98-114`, `:42-50`, `GymTrackWatch/Views/WatchLoggerView.swift:220-230`, `GymTrackWatch/Views/WatchRootView.swift:95`
- What happens: A 0.25 s `Timer` writes `remaining`. `restCentrepiece` reads it inside `WatchLoggerView.body`, so the whole logger (including the `lastCompletedSet` and `effortSet` scans over every set) is re-evaluated 4 times a second for every rest, and with the wrist down under the workout session. `sync(endsAt:)` accepts an `endsAt` that is already in the past; `refresh()` then clears the rest and plays `.notification`.
- Failure scenario: The watch app relaunches from a cached context whose `restEndsAt` ended 10 minutes ago. `syncRecorder` calls `rest.sync`, and the wrist gets a rest-over tap for a rest that ended long ago. During every rest, the logger body re-renders about 360 times in 90 s.
- Suggested fix: Draw the countdown in a small subview with `Text(timerInterval:)` or `TimelineView(.periodic(from:by: 1))`, and fire the haptic from one one-shot timer scheduled at `endsAt`. In `sync`, treat a past `endsAt` as no rest and clear silently.
- Verify by: Instruments, SwiftUI body counts during a rest. A unit test that `sync(endsAt: .now - 60)` leaves `isRunning == false` and plays nothing.

### WATCH-13: A double tap on Log set logs the next set too, or lands on the effort sheet that replaced the button
- Severity: P3
- Category: data-rule
- Confidence: likely (there is no guard; where the second tap lands depends on layout)
- Location: `GymTrackWatch/Views/WatchLoggerView.swift:587-618` (`logButton`, `log`), `:61-79`
- What happens: `connector.logSet` updates the overlay synchronously, so on the next frame the same button is bound to the next set. With the effort question on (the default, `trackRPE: true`), the logger is instead replaced by `WatchSetFeelView`, whose answer grid and "Undo set" sit where the thumb is.
- Failure scenario: A sweaty double tap logs set 3 and set 4 with the same numbers. Or, with effort on, the second tap records "All out", or undoes the set just logged. That is a mis-tap written into the record.
- Suggested fix: Ignore a second Log set within about 0.6 s. Give `WatchSetFeelView` a short hit-testing delay on appearance.
- Verify by: On the watch simulator: two taps 150 ms apart, and check only one set is logged.

### WATCH-14: The effort question takes over the logger for ten seconds after every set, blocking an immediate drop set or superset
- Severity: P3
- Category: missing-feature
- Confidence: confirmed
- Location: `GymTrackWatch/Views/WatchLoggerView.swift:61-79`, `:93-99`, `:608-611`
- What happens: After each log with effort enabled, the entire logger, including Log set and the rest countdown, is replaced by `WatchSetFeelView` until the lifter answers, taps Skip, or waits 10 s. That is a blocking step on the one path rule 3 protects.
- Failure scenario: A drop set: the next row is a continuation to be logged within seconds, but the lifter must first tap Skip. A superset: the lifter cannot see the rest or the next load for 10 s.
- Suggested fix: Skip the question when the next set is a continuation or already has a start announced. Better, render the question as a compact row within the logger or the rest card, so Log set is never covered.
- Verify by: On the watch simulator: log a set followed by a continuation row and confirm the next Log set is one tap away.

### WATCH-15: A watch workout saved because the phone finished carries no GymTrack metadata or session UUID
- Severity: P3
- Category: bug
- Confidence: confirmed
- Location: `GymTrackWatch/Views/WatchRootView.swift:111` (`title: nil`), `GymTrackWatch/WatchWorkoutRecorder.swift:138-148` (metadata only `if let title`)
- What happens: The phone-finish path, likely the most common way a session ends, saves with `title: nil`. The workout gets no brand, session name, sets, volume, indoor flag or `HKMetadataKeyExternalUUID`, while a wrist Finish of the same session would have all of them. The external UUID is the only link from a Health workout back to its session if the `.metrics` hand-over is lost.
- Failure scenario: Finish on the phone. Health shows an unnamed strength workout with no GymTrack metadata, and any later dedup keyed on session identity cannot match it.
- Suggested fix: Always add `HKMetadataKeyExternalUUID` from `sessionID`. Keep the last session snapshot in `WatchConnector` (or add title, sets and volume to `WatchSessionEnd`) and pass it to `end`.
- Verify by: On a device: finish on the phone and inspect the workout's metadata in Health.

### WATCH-16: The watch's save-or-discard decision and its overlay reconciliation have no tests
- Severity: P3
- Category: test-gap
- Confidence: confirmed
- Location: `GymTrackWatch/Views/WatchRootView.swift:93-115` (the decision lives inside a view), `GymTrackWatch/WatchConnector.swift:72-146`, `:308-351`, `Tests/WatchCommandReliabilityTests.swift` (covers codecs, `finishBatch` and `applyWatchFinish` only)
- What happens: The logic behind GT-006/007/008/010 and WATCH-01/02/05 runs only on devices. The `shouldSave` rule and `reconcile` are pure over mirror, pending and recorder state, but they are embedded in a SwiftUI view and a WCSession-bound class.
- Suggested fix: Move the recorder decision into a pure function in GymTrackShared (`RecorderAction.decide(mirror:recorderSessionID:isEnding:tombstone:)`) and move `reconcile`/`folding` into `WatchPendingActions`. Test with the existing script: a finish for another session discards; `phoneHealthWorkoutID` discards; a tombstoned session never restarts; a nil mirror with pending logs hands them off; an undo overtaken by its log.
- Verify by: `scripts/test-watch-command-reliability.sh` gains these cases and passes.
