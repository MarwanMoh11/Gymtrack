> Detail file from the 2026-09-28 review. The index, the canonical severities and the duplicate map are in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md). Where this file disagrees with the index, the index wins. Line numbers refer to the working tree on 2026-09-28 (HEAD f5809ff plus the uncommitted GT fix pass).

# HealthKit, per-set heart rate, widgets, Live Activity and App Intents: findings

Files read in full: GymTrack/Services/HealthKitService.swift, GymTrack/Services/SetHeartRate.swift, GymTrack/Services/WorkoutLiveActivity.swift, GymTrack/Services/WidgetPublisher.swift, GymTrack/Services/GymTrackShortcuts.swift, GymTrackShared/SharedStore.swift, GymTrackShared/WorkoutActivity.swift, GymTrackShared/GymTrackIntents.swift, GymTrackWidgets/WorkoutLiveActivityWidget.swift, GymTrackWidgets/TodayWidget.swift, GymTrackWidgets/StreakWidget.swift, GymTrackWidgets/SnapshotProvider.swift, GymTrackWidgets/GymTrackWidgetsBundle.swift, GymTrackWidgets/GymTrackWidgets.entitlements, GymTrackWidgets/Info.plist.
Excerpts traced: BackupService.swift (restore, wipe, deleteStoredRecords, SessionDTO), Tests/BackupServiceTests.swift, ActiveWorkout.swift (finish, discard, recordToHealth, activityState, rest onChange), WatchCommandCenter.swift (headless finish, logSet, recordToHealth, publishWidgets), WatchBridge.swift (metric folding, notePhoneHealthWorkout), RootView.swift (task, scenePhase, resumeUnfinishedSession, applyLateMetrics, runPendingAction), SessionSummaryView.swift (backfill task, delete), Entities.swift (SetLog heart-rate fields, unlog, exerciseGroups), SessionClosing.swift, BodyWeightCard.swift, SettingsView.swift (restore, erase), WatchRootView.swift and WatchWorkoutRecorder.swift (end, metadata), project.pbxproj entitlements.

A note on HealthKit behavior that several findings rely on (Apple's documented rules, not verified on device here): an app with share permission but no read permission still sees the samples it wrote itself; data from other sources, which may include the GymTrack watch app, stays hidden. Protected Health data cannot be read while the phone is locked, but writes are accepted.

## Prior findings re-check

- GT-008: OK on the phone's Health side, with a P3 follow-up. `saveWorkout` notices a watch ID that arrived while its builder was suspended and queues its own copy (`HealthKitService.swift:231-236`). `acceptWatchWorkout` queues the fallback and relinks the session (`:249-260`). The queue lives in UserDefaults and is retried at launch (`:67-70`), after authorization (`:117`) and after each enqueue. Because an app always sees the samples it wrote, the fallback can be deleted even without read permission, so the comment's worry about a "temporary loss of read permission" does not apply to the phone's own copy. Gaps: the queue is never retried when the app returns to the foreground or when protected data becomes available, and entries for a copy that is already gone are never dropped (HK-07).
- GT-020: REGRESSION. Restoring any backup written before this uncommitted change deletes the Health workout of every session, including sessions the backup restores (`BackupService.swift:532` compares Health IDs rather than session IDs). Tests/BackupServiceTests.swift:88-95 asserts that behavior. See HK-01. Also incomplete: restore now removes real workouts from Apple Health without asking (HK-05), and deleting one session from history is still a fire-and-forget Health delete with no retry and no feedback (HK-06).

## Findings

### HK-01: Restoring a pre-linkage backup deletes every GymTrack workout from Apple Health, including those of the sessions being restored
- Severity: P1
- Category: bug
- Confidence: confirmed (traced end to end; the unit test asserts the defect)
- Location: `GymTrack/Services/BackupService.swift:532` (`restore(data:)`), `:552`, `:605`, `:719-724` (`deleteStoredRecords`); `Tests/BackupServiceTests.swift:76-95`
- What happens: Restore decides which Health workouts to delete by subtracting the archive's Health IDs from the current ones: `let replacementHealthIDs = Set(archive.sessions.compactMap(\.healthWorkoutID))`, then `deleteHealthWorkouts(oldHealthIDs.subtracting(replacementHealthIDs), ...)`. The `healthWorkoutID` key is new in this working tree (HEAD's `BackupService.swift` has no such field), so every backup the user holds today decodes with `healthWorkoutID == nil`. The replacement set is therefore empty, every current link is deleted from Health, and the restored sessions come back with `healthWorkoutID = nil` even though they are the same sessions with the same `id`.
- Failure scenario: A user exports a backup with the current App Store or TestFlight build, updates to this build, then restores the file, for example to recover a deleted routine. `oldHealthIDs` holds every linked workout, including watch-recorded ones with measured heart rate. None of them appear in the archive, so all of them are deleted from Apple Health, and the restored sessions lose their link. That removes Move-ring and Fitness history irreversibly. The test at `BackupServiceTests.swift:88-92` restores the same session from a legacy file and expects `deleted == [healthID]`, with the comment "Removing a linked session must remove its old Health workout", although no session was removed.
- Suggested fix: Key the cleanup on session identity. Before `deleteStoredRecords`, capture `[sessionID: healthWorkoutID]` for the current sessions. In `insertArchive`, when a DTO has no `healthWorkoutID` and the same session ID had one locally, carry the local link over. Delete only links whose session ID is absent from the archive, and see HK-05 on whether even those should be deleted. Invert the legacy test's expectation.
- Verify by: Change `BackupServiceTests` so that restoring `legacy` (same session ID, no key) leaves `deleted` empty and the restored session keeps `healthWorkoutID == healthID`. Add a case where a session is truly absent from the archive.

### HK-02: Exercises done out of plan order vanish from the Health workout's activity breakdown
- Severity: P2
- Category: bug
- Confidence: confirmed
- Location: `GymTrack/Services/HealthKitService.swift:179-212` (`saveWorkout`); `GymTrack/Models/Entities.swift:323-335` (`exerciseGroups`)
- What happens: Activities are built by walking `session.exerciseGroups`, which is sorted by `exerciseOrder` (plan order), not by when the sets were done. Each activity runs from `cursor` to `activityEnd = min(end, max(cursor, finished))`, and `guard activityEnd > cursor else { continue }` silently drops any group whose last set was logged before the cursor.
- Failure scenario: The plan is [Bench, Squat, Row]. The bench is taken, so the lifter squats from 0 to 20 minutes, benches from 20 to 40 and rows from 40 to 60. Bench gets an activity [0, 40] and the cursor moves to 40. Squat's last set is at 20, so `max(40, 20) = 40` is not greater than 40, and Squat is skipped. Health shows Bench for 40 minutes, no Squat at all, and Row. The same happens when one make-up set of the first exercise is logged at the end: that exercise gets an activity covering the whole workout and every other exercise is dropped. The workout-level totals stay correct, but the per-exercise record in Health is wrong.
- Suggested fix: Build activities from completed sets sorted by `completedAt`, splitting into contiguous runs of the same `catalogID`. Each run goes from the previous run's last `completedAt` (or the first set's announced `startedAt`) to its own last `completedAt`, with per-run sets, reps and volume metadata. Extract that segmentation as a pure function so it can be tested without HealthKit.
- Verify by: A pure test of the segmentation with out-of-order, superset and make-up-set sessions, asserting that every exercise appears and that intervals never overlap. On device, finish such a session and inspect the workout's activities in the Fitness app.

### HK-03: Per-set heart rate is read only within seconds of finishing, so it is usually missing or read off a partial trace, and there is no later pass
- Severity: P2
- Category: bug
- Confidence: likely (the code paths are confirmed; the size of Health's sync delay needs a device)
- Location: `GymTrack/Services/HealthKitService.swift:374-402` (`backfillVitals`), `:419-473` (`attributeHeartRate`); `GymTrack/Features/Session/SessionSummaryView.swift:42-44` (only caller in the UI); `SessionSummaryView.swift:361` (`SessionDetailView`, which has no backfill); `GymTrack/Services/ActiveWorkout.swift:904-925`; `GymTrack/Services/WatchCommandCenter.swift:288-301`
- What happens: The doc comment says the backfill runs "right after a workout ends, and again when its summary is opened, because HealthKit can take a minute to receive the watch's samples". But the summary sheet is presented at the moment of finishing (`RootView.finishSession` sets `showingSummary = session`), so both passes run between 0 and about 13 seconds after the end. `SessionDetailView`, the only way back to a past session, never calls `backfillVitals`. After a wrist finish handled headlessly with the phone locked in a bag, the reads fail outright because protected Health data can't be read while the phone is locked, and the summary sheet never appears. In addition, a first pass over a partly synced trace is permanent: `attributeHeartRate` only fills sets with `!hasHeartRate`, and `recordDetectedWindow` is written once. So a set whose samples stopped mid-climb keeps a `.detected` window that ends early, and an inferred window that caught one early sample keeps that one-sample average.
- Failure scenario: A lifter trains with the phone in a locker and finishes on the wrist. `WatchCommandCenter.finish` runs `backfillVitals` while the phone is locked, so every query returns nothing. Later the lifter opens the session from history, and no per-set heart rate, no hardest-set row and nothing for the AI coach ever arrive. In the foreground case, if the watch's last ten minutes of samples reach the phone 40 seconds after finishing, the late sets never get a reading. A set straddling the sync boundary can be written as `detected` with a window that ends where the synced data happened to end.
- Suggested fix: (1) Add `.task { await HealthKitService.shared.backfillVitals(for: session); try? context.save() }` to `SessionDetailView`. (2) On `scenePhase == .active`, backfill sessions finished within about the last 24 hours that have completed sets without heart rate. This needs no background-delivery entitlement. (3) In `attributeHeartRate` and `detectedWindows`, only read a set's gap when the fetched trace demonstrably covers it, for example when a sample exists at or after that set's `completedAt`. That way a partial sync is left for the next pass instead of being frozen.
- Verify by: A pure test of `SetHeartRateAttribution` with samples truncated mid-set, asserting that the truncated set gets nothing. On device, finish on the wrist with the phone locked, open the session from history a few minutes later, and check that per-set badges appear.

### HK-04: Correcting a weigh-in leaves the wrong body-mass sample in Apple Health
- Severity: P2
- Category: data-rule
- Confidence: confirmed
- Location: `GymTrack/Features/Progress/BodyWeightCard.swift:172-188` (`record(kg:on:)`); `GymTrack/Services/HealthKitService.swift:530-545` (`saveBodyMass`), `:549-588` (`importBodyMass`)
- What happens: Locally, a second weigh-in on the same day replaces the first (`existing.weightKg = kg`). In Health, every save calls `saveBodyMass`, which writes a new `HKQuantitySample`. Nothing removes the earlier one. The import skips days that already exist locally, so the app and Health disagree permanently. This breaks rule 2: the mis-tap is undone in the app but stays on record in Health.
- Failure scenario: A user types 850 instead of 85.0 and saves. Health receives 850 kg. They notice and log 85.0 for the same day. The app shows 85.0, while Health's weight chart and every app that reads body mass still has an 850 kg reading for that day. After Erase all data, the next import brings GymTrack's own writes back with `source = health`, so weigh-ins the user typed are relabeled as scale readings.
- Suggested fix: Store the Health sample's UUID on `BodyMetric` (an optional `healthSampleID`, also optional in the backup). On a same-day replace, delete that sample before saving the new one. Alternatively, before writing, delete GymTrack-sourced body-mass samples for that day with `store.deleteObjects(of:predicate:)`, combining the day predicate with `HKQuery.predicateForObjects(from: HKSource.default())`. When importing, skip samples whose source is GymTrack.
- Verify by: On device, log 90 and then 85 on the same day, and check that Health lists only 85.

### HK-05: Restore deletes real, watch-measured workouts from Apple Health with no confirmation, and Erase never mentions Health
- Severity: P2
- Category: bug
- Confidence: confirmed
- Location: `GymTrack/Features/Settings/SettingsView.swift:150-153` (the restore button opens the importer directly), `:247-280` (`handleImport`), `:199-203` (erase dialog text); `GymTrack/Services/BackupService.swift:552`
- What happens: Choosing a file restores immediately, and after the local swap `deleteHealthWorkouts` removes from Apple Health the workout of every session that is not in the file. A GymTrack backup cannot put those workouts back into Health, because restore never writes Health. The erase dialog says "Every routine, session and record on this device is deleted" and does not say that Apple Health workouts go too.
- Failure scenario: A user restores last month's backup to recover a routine they deleted. Every workout from the past month, including watch recordings with measured heart rate, is permanently removed from Apple Health: Move-ring history, Fitness awards and other apps' workout lists. The only prompt is the file picker. Those workouts happened, so deleting them is data loss rather than the "undone leaves no trace" cleanup that rule 2 describes.
- Suggested fix: Do not delete Health workouts on restore; re-link by session ID (HK-01) and leave the others alone. If deletion stays, put it behind a confirmation that names the count and says "from Apple Health". Add "and the workouts GymTrack saved to Apple Health" to the erase dialog, or offer a toggle there.
- Verify by: Unit test: a restore that drops a session calls `deletingHealthWorkout` zero times, or only after an explicit flag. Manually, read the erase dialog.

### HK-06: Deleting a session from history leaves its Health workout behind whenever the one-shot delete fails, with no retry and no notice
- Severity: P3
- Category: bug
- Confidence: confirmed for the missing retry; speculative for the cross-source delete
- Location: `GymTrack/Features/Session/SessionSummaryView.swift:416-424`; `GymTrack/Services/HealthKitService.swift:318-336` (`deleteWorkout`)
- What happens: `Task { await HealthKitService.shared.deleteWorkout(id: workoutID) }` ignores the Bool that the fix pass added and does not use the persisted cleanup list. The linked workout is usually the watch's, and the watch app is a different HealthKit source. With share-only authorization, the phone's query cannot see the watch's workout, so `deleteWorkout` returns false every time. It is also unverified whether the iPhone app may delete a sample whose source is `com.marwanmohamed.gymtrack.watchkitapp` at all. The same question applies to erase and restore.
- Failure scenario: A user deletes a watch-driven session from history. The local session is gone, the workout stays in Fitness, and nothing tells them. Erase reports the same failure (`SettingsView.swift:292-296`), but this path says nothing.
- Suggested fix: Put the ID on the durable list (a variant of `PendingWorkoutCleanup` with no preferred ID) instead of fire-and-forget, and show the same "remove it in Health" notice when the delete fails. On a device, confirm whether the phone can delete a workout the watch saved. If it cannot, have the phone send the watch a delete command.
- Verify by: On device, record a session on the watch, delete it from the phone's history, and check Fitness. Repeat with workout read access turned off.

### HK-07: The fallback-cleanup queue retries only on cold launch, and entries whose workout is already gone are never removed
- Severity: P3
- Category: bug
- Confidence: likely
- Location: `GymTrack/Services/HealthKitService.swift:67-70`, `:265-294` (`retryPendingWorkoutCleanup`), `:329`
- What happens: A retry happens only at `configure` (process launch), at `requestAuthorization`, and right after an enqueue. When the late watch ID arrives through the headless path while the phone is locked, the lookup fails because protected data is unavailable. The duplicate then stays in Health until the next cold launch, which for an app kept in memory can be days. Separately, `guard !workouts.isEmpty else { return false }` keeps an entry forever once the phone's own copy is already gone, for example if the user removed it in Health. An app always sees its own samples, so an empty result there does mean the copy is gone. Every retry also fetches all `WorkoutSession`s with no predicate, once per entry (`:278`).
- Failure scenario: A lifter finishes on the wrist with the phone locked. The watch ID arrives more than 12 seconds late, so the phone has already written its fallback. The retry fails while locked. Fitness shows two strength workouts for that session until iOS happens to relaunch GymTrack.
- Suggested fix: Also call `retryPendingWorkoutCleanup()` on `scenePhase == .active` and on `UIApplication.protectedDataDidBecomeAvailableNotification`. Treat an empty result for a phone-written ID, with write permission present, as done. Fetch with `#Predicate { $0.id == sessionID }`.
- Verify by: A unit test of the queue with an injected delete closure (queue, fail, foreground, retry, drained). On device, finish on the wrist with the phone locked and the watch ID arriving late, unlock, and check that Fitness shows a single workout.

### HK-08: Wrist logging handled headlessly freezes the Lock Screen card and the Home Screen widget, and an abandoned session shows as running forever
- Severity: P3
- Category: bug
- Confidence: confirmed
- Location: `GymTrack/Services/WatchCommandCenter.swift:60-80` (headless start), `:82-106` (`logSet`), `:147-157` (`undoSet`), `:308-311` (`publishWidgets`, called only on finish or discard); `GymTrackShared/SharedStore.swift:205-233` (`asOf` keeps `session`)
- What happens: When iOS has terminated the phone app mid-workout, which is common with the phone locked in a bag, watch commands are applied by `WatchCommandCenter` without an `ActiveWorkout`. That path updates the store and the watch mirror but never updates the Live Activity or the widget snapshot. A session started from the watch on this path gets no widget update either. `asOf` deliberately keeps a running session across midnight and has no age limit, while the app itself closes sessions older than 12 hours (`RootView.swift:476`).
- Failure scenario: The phone app is jettisoned after set 3. The lifter logs sets 4 to 20 on the wrist. The Lock Screen card still says "Set 3 of 4" with the old rest, and the Today widget says "3/20 sets". If the app is killed and the session is never finished, the Today widget and the Streak widget ("Session running") show a running workout until someone opens the app.
- Suggested fix: After each headless mutation, call `publishWidgets(context:)` (or an `updateSession` variant built from `WorkoutSession`). Update any running `Activity<WorkoutActivity>` whose `sessionID` matches, with a state built from the session. Factor `activityState` out of `ActiveWorkout` so both paths share it. In `asOf`, drop `session` when `startedAt` is more than 12 hours before the entry date.
- Verify by: Terminate the phone app mid-session, log two sets from the watch, and check the Lock Screen and the widget.

### HK-09: Every in-session change reloads every widget kind, which spends WidgetKit's daily budget when the app runs in the background
- Severity: P3
- Category: performance
- Confidence: likely
- Location: `GymTrack/Services/WidgetPublisher.swift:68-72`, `:87-99` (`reloadAllTimelines()`); `GymTrack/Services/ActiveWorkout.swift:131-137` (rest `onChange`), `:926-933` (`save`)
- What happens: `save()` and every rest start, extend or stop call `updateSession`, which calls `WidgetCenter.shared.reloadAllTimelines()`. That is about two to three reloads per logged set, and each one also reloads the Streak widget, whose drawing does not depend on per-set progress. Reloads are free only while the app is in the foreground. For a wrist-driven session with the phone locked, the app is woken in the background for each command, and those reloads count against the budget of roughly 40 to 70 per day.
- Failure scenario: A 25-set session logged on the wrist spends about 60 reloads on the Today widget and as many on the Streak widget. The finish reload can then be refused, and the Today card keeps showing the workout as running (the `Text(startedAt, style: .timer)` keeps counting) until the app next comes to the foreground.
- Suggested fix: Reload only `"GymTrackToday"` via `reloadTimelines(ofKind:)` for session-only changes. While `UIApplication.shared.applicationState != .active`, write the snapshot but skip the reload except for session start and finish.
- Verify by: Log reload calls during a locked-phone wrist session and confirm there is one per start and finish instead of one per set.

### HK-10: The Dynamic Island rest ring is always full because `restProgress` has its sign reversed
- Severity: P3
- Category: bug
- Confidence: confirmed
- Location: `GymTrackShared/WorkoutActivity.swift:64-69` (`restProgress`); `GymTrackWidgets/WorkoutLiveActivityWidget.swift:354-356` (`CompactRing.trim`)
- What happens: `min(1, max(0, -restEndsAt.timeIntervalSinceNow / total))`. While resting, `restEndsAt` is in the future, so the ratio is negative and clamps to 0, and `trim = 1 - 0` gives a full ring. The value is correct only after the rest has ended, when the ring is no longer drawn this way. The ring is also computed only at render time, so it cannot animate between pushes anyway.
- Failure scenario: A push arrives mid-rest, for example from a weight edit or a rest extension. The compact ring shows a full "rest remaining" regardless of how much time is left.
- Suggested fix: Use `1 - restEndsAt.timeIntervalSinceNow / total`, or better, replace the ring with `ProgressView(timerInterval: start...end, countsDown: true)` styled as a circle, which the system animates in a Live Activity.
- Verify by: A unit test of `restProgress` with a rest that is half elapsed, expecting 0.5.

### HK-11: The phone asks for Health read access to resting heart rate, basal energy and activity summaries that it never uses
- Severity: P3
- Category: code-health
- Confidence: confirmed
- Location: `GymTrack/Services/HealthKitService.swift:88-101` (`shareTypes`, `readTypes`)
- What happens: `readTypes` includes `.restingHeartRate`, `.basalEnergyBurned` and `activitySummaryType()`, and `shareTypes` includes `.activeEnergyBurned`. Nothing on the phone reads the first three or writes energy. The only matches for them in the repo are these declarations (the watch has its own request). Resting heart rate is recovery data, which the product has rejected.
- Failure scenario: The Health sheet shows toggles for data the app has decided not to use. That adds friction and review risk (App Store guideline 5.1.1), and invites a later change to quietly start using it.
- Suggested fix: Trim the phone's sets to workouts, heart rate, active energy and body mass for reading, and workouts and body mass for sharing.
- Verify by: Open the Health permission sheet from Settings and check the listed types.

### HK-12: A Siri, Shortcut or Action Button start may be read before `perform()` has written its note
- Severity: P3 (P2 if confirmed: the feature would not work)
- Category: bug
- Confidence: speculative
- Location: `GymTrackShared/GymTrackIntents.swift:14-56`; `GymTrack/App/RootView.swift:37-45`, `:86-97`, `:227-234`; `GymTrackShared/SharedStore.swift:46-67`
- What happens: With `openAppWhenRun = true`, the system brings the app to the foreground and runs `perform()` in the app process. The note is read only in `.task` (cold launch) and on `scenePhase == .active`. If the scene becomes active before `perform()` runs `SharedStore.request(...)`, `takeAction()` finds nothing, and the note waits for the next activation. If that comes within two minutes, a workout starts later than the user expects; otherwise the note is dropped. The intents are also compiled into the widget extension. If the system ever runs them there in Debug, where there is no App Group, the note is written where the app can't read it.
- Failure scenario: With GymTrack in the background, "Start my GymTrack workout" brings the app forward and nothing starts. Backgrounding and reopening the app a minute later then starts a session unprompted.
- Suggested fix: Make `perform()` `@MainActor` and, when it runs in the app process, hand the action to a shared router that `RootView` observes, keeping the note only as the cold-launch fallback. Alternatively, have `RootView` also react to a `UserDefaults` change notification. Keep the intents out of the widget target, since the widgets use links.
- Verify by: On a device (Debug and Release), run each shortcut from Shortcuts with the app cold, in the background, and in the foreground, and confirm the logger opens every time.

### HK-13: A session closed by the 12-hour stale-recovery path is never written to Health or backfilled
- Severity: P3
- Category: missing-feature
- Confidence: confirmed
- Location: `GymTrack/App/RootView.swift:476-488` (`resumeUnfinishedSession`); the only `saveWorkout` callers are `ActiveWorkout.swift:918` and `WatchCommandCenter.swift:295`
- What happens: An open session older than 12 hours is closed at its last logged set with `open.close(at: lastLogged, in: context)`, which keeps it in history, but nothing calls `saveWorkout` or `backfillVitals` for it. The same gap applies if the process dies during `recordToHealth`'s 12-second wait: no durable "owes a Health write" marker exists.
- Failure scenario: iOS kills the app mid-workout, and the lifter doesn't reopen it until the next day. The session is recovered into history, but a phone-only session never appears in Apple Health and never gets per-set heart rate.
- Suggested fix: After the stale close, run the same Health write and backfill that `WatchCommandCenter.recordToHealth` runs (the guards in `saveWorkout` already prevent a duplicate when a watch ID exists). Optionally persist a "needs Health write" flag that is cleared once `healthWorkoutID` is set or the setting is off.
- Verify by: Seed an open session started 13 hours ago with two completed sets, launch the app, and check that it gets a `healthWorkoutID`. On a device, check that it appears in Health.

### HK-14: A session deleted while its Health write is pending still gets written, and its SwiftData object is touched after deletion
- Severity: P3
- Category: bug
- Confidence: speculative (the crash depends on SwiftData's behavior for deleted models)
- Location: `GymTrack/Services/ActiveWorkout.swift:904-925` (`recordToHealth`); `GymTrack/Services/HealthKitService.swift:155-244`; `SessionSummaryView.swift:416-424`
- What happens: `recordToHealth` holds `session` across up to 12 seconds of sleeping plus the builder's awaits and never checks `session.isDeleted` or `session.modelContext`. If the session is deleted from history in that window, `healthWorkoutID` is still nil, so the delete path removes nothing from Health. `saveWorkout` then reads `completedSets` and `exerciseGroups` of a deleted model and writes a workout for a session that no longer exists.
- Failure scenario: A lifter finishes a watch-driven session, dismisses the summary, opens the session from Today and deletes it within about 10 seconds. The result is an orphan workout in Health, or a crash when faulting relationships of the deleted model.
- Suggested fix: After every `await` in `recordToHealth` and inside `saveWorkout`, bail out when `session.isDeleted || session.modelContext == nil`. If a workout was already written, queue it for deletion.
- Verify by: Temporarily lengthen the wait, then finish, delete and watch the logs and Health.

### HK-15: The riskiest pure logic in this area has no regression tests
- Severity: P3
- Category: test-gap
- Confidence: confirmed
- Location: `GymTrackShared/SharedStore.swift:205-233` (`GymTrackSnapshot.asOf`); `GymTrack/Services/HealthKitService.swift:179-212` (activity segmentation); `:265-312` (cleanup queue); `GymTrackShared/WorkoutActivity.swift:64-69`
- What happens: `Tests/` covers `SetEffortDetection` and parts of the attribution, but nothing else here. Untested: the midnight, streak and week rollover in `asOf` (including a week boundary and an entry exactly at 00:01); the segmentation behind HK-02; the enqueue, retry and drain behavior of the cleanup queue; and `restProgress`, whose bug is HK-10.
- Failure scenario: HK-02 and HK-10 both slipped through, and the only Health-cleanup test asserts the HK-01 defect.
- Suggested fix: Add `scripts/test-widget-snapshot.sh` for `asOf`. Extract the activity segmentation and the cleanup queue behind injectable closures, as `BackupService` already does with `deletingHealthWorkout`, and test them the same way.
- Verify by: The new scripts run in CI alongside the existing ones.
