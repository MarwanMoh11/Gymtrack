> Verification pass from the 2026-09-28 review. The index is in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md).

# Verification of LINK-01/WATCH-02, WATCH-01, WATCH-06, WATCH-08, LINK-02

This was a read-only trace of the working tree. Nothing was built or run.

---

## Claim A (LINK-01 / WATCH-02): phone Finish loses wrist logs still queued in transferUserInfo

**Verdict: CONFIRMED.** One step in the reviewer's path is wrong; the corrected path is below.

Evidence:
- The phone's Finish closes the session with nothing from the wrist. `ActiveWorkout.finish()` (GymTrack/Services/ActiveWorkout.swift:855-870) calls `session.close(in:)` and then `WatchBridge.update(session: nil, ended: ...finished)`. It sends no request to the watch. No phone-to-watch command asks for a batch; phone-to-watch traffic is mirrors only (WatchBridge.swift:106-139). No "outstanding transfers" guard exists anywhere (a grep for outstanding/pendingWatch/awaitWatch finds nothing).
- `close` deletes the rows (GymTrack/Models/SessionClosing.swift:65-67):
  `for set in sets where !set.isCompleted { context.delete(set) }`
- A late `.logSet` is dropped. After Finish, `RootView.finishSession` → `closeSession()` sets `activeWorkout = nil` (RootView.swift:201-214). The command then reaches RootView's `default: return false` (RootView.swift:380-381) and goes to headless, where WatchCommandCenter.swift:85 drops it:
  `guard let set = setLog(id: id, in: context), set.session?.isActive == true else { return }`
- The watch discards its only other copy. Receiving the ended mirror calls `reconcile(with: nil)` → `pending.clear()` (GymTrackWatch/WatchConnector.swift:307-316). Only the ratings are re-sent first. The pending logs are not sent.
- The watch sends nothing when `endedSession` arrives. `syncRecorder`'s nil branch (WatchRootView.swift:102-113) only ends the recorder and sends `.metrics`. `finishBatch` is built only by the wrist's own `end()` (WatchRootView.swift:121).
- On reconnect, the watch's `requestMirror` gets a mirror that still shows the sets undone. `reconcile` keeps them in `pending.logs` because `guard set.isCompleted else { return true }`, but never resends them.

Corrected scenario: `ActiveWorkout.apply` (~990, `return true` for an unknown id) is only the path when a new ActiveWorkout is already live. In that case it swallows the command without a headless fallback. In the common case `activeWorkout` is nil and the drop happens at WatchCommandCenter.swift:85. The result is the same either way.

Trigger: the wrist logs while the phone is out of range, or a live `sendMessage` fails and falls back to `transferUserInfo` (WatchConnector.swift:182-186). The lifter then taps Finish on the phone before the queue drains. The transport does not lose the commands; the phone rejects them on arrival.

Severity: high under house rule 1. Real lifts disappear from the record, and the exercise and its notes can be pruned with them, because `pruneNotesForClosing` keys on completed sets.

---

## Claim B (WATCH-01): no local "S ended" marker, so a re-launched watch re-records S and a second Health workout follows

**Verdict: CONFIRMED, narrower than stated.** It needs a watch process relaunch (a fresh WCSession activation). A requestMirror reply overtaking the finish does not restart the recorder in a process that stays alive.

Evidence:
- Nothing marks S as ended locally. The wrist `end()` (WatchRootView.swift:119-135) ends the recorder and sends `.finishSession`. It does not touch `mirror`, `pending` or any flag. `WatchConnector.session` keeps returning `mirror.session` (WatchConnector.swift:73-74) until a non-nil-session mirror is replaced.
- Why the live process is safe: the recorder only restarts when `.task(id: recorderSyncKey)` re-fires (WatchRootView.swift:67-69). The key is `{session?.sessionID, healthEnabled, endedSession}`. A requestMirror reply that still carries S leaves the key unchanged, so `syncRecorder` does not run again in the same process.
- Relaunch while the phone is unreachable: activation receives the cached context, which still holds S, with `waitingForFreshMirror = session.isReachable`, i.e. false (WatchConnector.swift:365-371). `session` becomes S, the key changes from nil to S, and `recorder.startIfNeeded(for: S)` runs (WatchRootView.swift:97). It then backdates to S's start (WatchWorkoutRecorder.swift:107-109):
  `let start = min(snapshot.startedAt, .now)` ... `try await builder.beginCollection(at: start)`
- Relaunch while the phone is reachable: `waitingForFreshMirror = true`, and `requestMirror` goes out by `sendMessage`. The finish is still in the `transferUserInfo` queue, and WatchConnectivity does not order the two. If the reply is built before the finish lands, S comes back, the key changes from nil to S, and recording restarts. This is the reviewer's "overtaking" case; it only bites after a relaunch.
- How the second workout gets saved: the phone adopts W1 from the finish metrics (`adoptWatchMetrics`, ActiveWorkout.swift:889-899), so it writes no fallback and `phoneHealthWorkoutID` stays nil. When the nil mirror arrives, `shouldSave` (WatchRootView.swift:107-110) is true, and `recorder.end(discardingSamples: false, title: nil)` saves W2 with no metadata, running from `S.startedAt` to now. `.metrics(W2)` → `applyLateMetrics` → `acceptWatchWorkout` (HealthKitService.swift:249-259) queues **W1** for deletion and links W2. It also overwrites the session's avg/max HR and energy with W2's figures (RootView.swift:422-428).

Severity note: whichever way HealthKit rules on deletion, the result is wrong.
- If the phone app cannot delete a sample saved by the watch app, both workouts stay in Health and W1 sits on the cleanup list for good.
- If deletion succeeds, the accurate W1 (with title, sets and volume, ending at the real finish) is replaced by W2, which has no metadata and an inflated duration and energy.

In the unreachable variant the watch UI also keeps showing S as in progress after the lifter finished it.

---

## Claim C (WATCH-06): a cancelled `startIfNeeded` still completes and orphans an HKWorkoutSession

**Verdict: CONFIRMED.**

Evidence:
- There is no cancellation or "still wanted" check anywhere in `startIfNeeded` (WatchWorkoutRecorder.swift:79-120). After `guard await requestAuthorization() else { return }` (:92) and `try await builder.beginCollection(at: start)` (:109), it unconditionally sets `self.session = session` (:111) … `self.isRunning = true` (:115). Neither HealthKit call is cancellation-aware; both are bridged completion-handler APIs. Cancelling `.task(id:)` therefore has no effect.
- The replacement `syncRecorder` cannot clean up:
  - If `isRunning` is still false, the nil-session branch skips entirely (`else if recorder.isRunning, !isEnding`, WatchRootView.swift:102).
  - If the session delegate has already flipped `isRunning = true` after `startActivity` (:229), `end()` hits `guard let session, let builder else { return nil }` (:128). `self.session` is not assigned until after `beginCollection`, so it is a no-op.
  - The `isStarting` guard (:86) also stops any overlapping start from taking over.
- The orphan persists until the key changes again: a new session, or a Health toggle. A running HKWorkoutSession keeps the app alive, so termination will not clear it.

Extra consequence the reviewer missed: the orphan's builder keeps calling `sendMetricsIfDue` with `sessionID = S`. If S was finished rather than discarded, the phone's `.metrics` → `applyLateMetrics` (RootView.swift:417-430) overwrites the closed session's avg/max HR and energy every ~5 s with the orphan's readings. That is false detail written into a finished record.

Severity: medium impact, rare trigger. The phone has to finish or discard during the authorization prompt or `beginCollection`, for example discarding right after a phone start that auto-launched the watch.

---

## Claim D (WATCH-08): delegate callbacks don't check for the current builder or session

**Verdict: CONFIRMED (code). Low severity for the fields the reviewer named. The session-delegate half is the more dangerous one.**

Evidence:
- `workoutBuilder(_:didCollectDataOf:)` → `Task { @MainActor in self.update(from: workoutBuilder, types: collectedTypes) }` (WatchWorkoutRecorder.swift:247). `update(from:)` reads from whichever builder it is handed, with no `workoutBuilder === self.builder` check.
- `workoutSession(_:didChangeTo:...)` → `self.isRunning = toState == .running || toState == .paused` (:229), with no `workoutSession === self.session` check. `didFailWithError` has the same gap.
- In the discard path, `end()` has no suspension: `builder.discardWorkout()` (:135) runs, then the reset follows (:163-167). A collect callback hopping to the main actor at that moment runs after the reset and repopulates `heartRate`, the averages and `activeEnergyKcal`.

Actual impact of the late builder callback:
- `sessionID` is already nil, so the metrics it sends carry no session. The phone's `merging` ignores them (WatchLink.swift:284). There is one quirk: `WatchBridge.handle`'s `nil == nil` match plus `?? .empty` can leave `liveMetrics` non-nil, which later makes `recordToHealth` wait up to 12 s (ActiveWorkout.swift:907-916). That is minor.
- `startIfNeeded` does not reset the metric fields. Stale avg/max/energy therefore show at the start of the next session, and can ride along in its first `.metrics` until that session's builder reports each type. The leak is transient.

The higher-risk variant: a late `.ended` from an old session, or a late `.running` for an orphan, can overwrite `isRunning` for the current one. If `isRunning` goes false while a session is running:
- the next `syncRecorder` will build a second HKWorkoutSession over the live one, which leaks it;
- the nil-session branch skips `end()`, so the workout is never saved or discarded.

The window is narrow in practice. In handover, the old `.ended` usually lands during the new start's `requestAuthorization` suspension, before the new session is running.

---

## Claim E (LINK-02): a fresh phone process pushes a nil/nil mirror on activation and the watch acts on it

**Verdict: CONFIRMED. The watch half has no protection.**

Evidence:
- Phone side: `activationDidCompleteWith` → `if state == .activated { self.push() }` (WatchBridge.swift:174). `activate()` runs from `WatchCommandCenter.configure` in the App init (GymTrackApp.swift:76), before RootView's `.task` restores the session and calls `connectWatch()` (RootView.swift:37-42). `sessionSnapshot` and `endedSession` are still nil, and `idle` is `.empty`. On a headless background launch, no view ever sets them.
- The watch accepts it on timestamp alone (WatchConnector.swift:298):
  `guard incoming.sentAt >= mirror.sentAt else { return }`
- Nothing on the watch filters it:
  - `waitingForFreshMirror` is set only by the watch's own activation, and this very mirror clears it (:300).
  - The pending overlay only acts when `mirror.session` is non-nil (:74, :82).
  - There is no grace period.
  - `isEnding` only covers a wrist-initiated end.
- Consequences:
  - `syncRecorder` sees session nil with `endedSession` nil, so `shouldSave` is false and the running Health recording is discarded (WatchRootView.swift:106-111).
  - `reconcile(with: nil)` → `pending.clear()` (:315) wipes the wrist's unconfirmed overlay and flushes the rating outbox.
  - When the real S mirror follows, `startIfNeeded(S)` starts a fresh builder backdated to `S.startedAt`. Samples from the discarded builder are not recovered.

Severity amplifier that ties to Claim A: once `pending` is cleared, a later wrist Finish sends a `finishBatch` without those logs. If the queued `.logSet` commands then arrive after the finish, WatchCommandCenter.swift:85 drops them. So a phone relaunch mid-session can also cause the permanent log loss described in A.
