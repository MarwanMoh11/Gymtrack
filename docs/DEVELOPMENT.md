# Developing GymTrack locally

The long-form notes for a session working on this Mac: where each piece of the
app lives, how to build and install it, and the simulator's quirks. They moved
here from `CLAUDE.md` so the cloud runs, which read `CLAUDE.md` on every run and
can neither build nor drive a simulator, don't pay for them each time.
`CLAUDE.md` still holds the rules every session follows.

## Where things live

- `Models/Entities.swift` — the SwiftData models: `Plan`, `PlanDay`, `PlanItem`,
  `WorkoutSession`, `SetLog`, `ExerciseNote`, and the derived `SessionExerciseGroup`.
- `Models/CatalogExercise.swift` — `ExerciseCatalog.shared`, ~414 bundled
  exercises from a JSON resource, plus the user's custom ones.
- `GymTrackShared/SetFeel.swift` — the four effort answers. Stored as the 6–10 number the
  progression has always read; shown as Easy / Solid / Hard / All out.
- `Services/ActiveWorkout.swift` — drives an in-progress session. Objects are
  written as you go, so a force-quit mid-workout loses nothing.
- `Services/TrainingStats.swift` — pure functions over finished sessions. Volume,
  streaks, records, and the double-progression suggestion.
- `Services/BackupService.swift` — JSON export/import. **`version` is 2 and stays
  2**; every field added since is optional so older backups still decode. Read
  the comments on `bodyMetrics` / `loadScales` / `exerciseCatalog` before adding
  one.
- `docs/AI_COACH.md` — the coach loop: the Mac-side review run in Claude Code,
  the phone↔Mac file contract, the coaching policy and the reviewer, and how we
  will know the coach helps. Read it before designing AI coach work.
- `tools/coach/` and `.claude/skills/coach-review/` — the Mac side of that loop
  (pull the export, compute stats, run the reviewer, push a proposal), driven by
  `/coach-review`. Review data lives in `~/Documents/GymTrackCoach` and never
  enters the repo.
- `Services/LoadScaleBook.swift` — what each machine is marked in and what one
  step on it is worth. Every weight the app suggests must be a rung the equipment
  actually has.
- `Services/HealthKitService.swift` — workout writing and vitals backfill.
- `Services/WatchCommandCenter.swift`, `WatchBridge.swift`,
  `GymTrackShared/WatchLink.swift` — the phone↔wrist link. Note the **headless**
  path: iOS wakes a terminated app to hand it a watch message, so commands must
  apply without a view hierarchy.
- `DesignSystem/` — `Theme`, `SessionPhase`, `gtCard`, `SectionHeader`,
  `StatTile`, `StepperField`, `GlyphTile`, `ProgressRing`, `FlowRow`. Use these.
  Do not invent colours or spacing.

## Building

```
xcodebuild -project GymTrack.xcodeproj -scheme GymTrack -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd build
xcodebuild -project GymTrack.xcodeproj -scheme GymTrackWidgets -configuration Debug \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/dd build
xcodebuild -project GymTrack.xcodeproj -scheme GymTrackWatch -configuration Debug \
  -destination 'generic/platform=watchOS Simulator' -derivedDataPath build/watch build
```

Build all three before claiming a change is done — the shared folder reaches the
watch and the widgets, and breaking them is easy to miss.

To put a build on the phone, use `sh scripts/install-phone.sh`, not Xcode's
Run button. A free Apple ID signs for seven days counted from when the
provisioning profile was made, and Xcode reuses a cached one, so a fresh
install can have two days left; the script fetches new profiles first. It also
records what was installed, and a background job (`--schedule`, installed)
re-signs and reinstalls that same source every two days. Installing another
way leaves the job unsure what is on the phone, and it stops and says so.
The app shows a line on Today three days before its signing runs out; seeing
it means the refresh has stopped reaching the phone.

If every build suddenly exits 69, Xcode's licence needs re-accepting after a
major upgrade (`sudo xcodebuild -license accept`). Only the user can run that.

## Running the tests

```
xcodebuild test -project GymTrack.xcodeproj -scheme GymTrack \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath build/dd -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
xcodebuild test -project GymTrack.xcodeproj -scheme GymTrackWatch \
  -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm)' \
  -derivedDataPath build/watch -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
sh scripts/test-all.sh
```

The first runs `GymTrackTests` and `GymTrackUITests`, the second
`GymTrackWatchTests`, the third the older `Tests/` suite (about seven minutes;
`sh scripts/test-all.sh watch` runs only the scripts with "watch" in their
name). Add `-only-testing:GymTrackTests/SuiteName` to run one suite. CI runs
all three on every pull request; see `docs/claude-pipeline.md`.

## Checking your own work

The user tests changes on the simulator themselves. Don't drive the simulator to
verify your own work, not even as a spot check, unless the user asks for it. The
checks that are yours: all three schemes build (see above), and the tests for
what you touched pass (see "Running the tests"). Say
plainly that nothing was UI-tested, and end with a short list of what the user
should try.

## Driving the simulator, when asked

When the user does ask for a simulator check, drive the real UI with
`mcp__Claude_Code_iOS_Simulator__control` rather than asserting from code. Find a
booted device with `xcrun simctl list devices booted`.

Things that will cost you an hour if you rediscover them:

- **Coordinates are 402x874 pt; screenshots come back ~919x1990 px.** Scale by
  402/919 and 874/1990.
- **The data container UUID changes on every install.** Re-resolve
  `xcrun simctl get_app_container <udid> com.marwanmohamed.gymtrack data` *after*
  installing. A path cached from before the install silently reads the old
  container.
- **A `Toggle` ignores `tap`.** Use a short horizontal `swipe` across the switch.
- **Writing to the store needs a WAL checkpoint.** Inject with `sqlite3` while
  the app is terminated, then `PRAGMA wal_checkpoint(TRUNCATE);` before
  relaunching, or the app comes up on pre-injection state and you will conclude
  your code failed when it never ran. Store lives at
  `<container>/Library/Application Support/default.store`. Core Data timestamps
  are seconds since 2001 (`Date(timeIntervalSinceReferenceDate:)`).
- **HealthKit cannot be authorised on an iPhone simulator.** The Health sheet
  accepts taps on its toggles but ignores its own Allow button, and
  `simctl privacy` has no health service. Anything behind Health read access can
  only be proven on a real phone — say so plainly rather than implying otherwise.
- **The watch simulator takes taps too.** Value tiles, the steppers and Log set
  all drive fine; this note used to say otherwise and cost an afternoon of
  working around it. Its coordinate space is 208x248 pt against a 416x496 px
  screenshot, so scale by exactly 0.5.
- **Bringing the link up takes both sims in the right order.** Boot the phone
  first and the watch second — `simctl list pairs` has to read
  `active, connected`, not `disconnected`. Then install the phone `.app` and
  install `GymTrack.app/Watch/GymTrackWatch.app` *from inside that bundle*: a
  separately built watch app leaves `WCSession` reporting `appInstalled: NO` and
  the phone refusing every push with `WCErrorCodeWatchAppNotInstalled`.
  Reinstalling the phone app does not resurrect the running session, so start a
  fresh workout rather than concluding the session was lost.
- **`simctl launch` drops app arguments unless they follow `--`**:
  `launch --terminate-running-process <udid> <bundle> -- -GTSeedSampleData`.
  That flag seeds ~9 weeks of history, but only when an active plan already
  exists and there are no sessions yet.
- `simctl io screenshot` does not composite the Dynamic Island; its contents come
  out blank.

