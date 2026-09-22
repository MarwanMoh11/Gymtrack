# GymTrack

Native iOS + watchOS workout tracker. SwiftUI, SwiftData, no account, no server,
no network — everything lives on the device. Minimum target iOS 17.

Read this before scanning the repo. It exists so you don't have to re-derive the
architecture, the conventions or the simulator's quirks on every task.

## Targets and layout

| Path | What |
|---|---|
| `GymTrack/` | The iPhone app. `App/`, `Models/`, `Services/`, `Features/`, `DesignSystem/` |
| `GymTrackWatch/` | The watchOS app |
| `GymTrackWidgets/` | Home Screen widgets and the Live Activity |
| `GymTrackShared/` | Code compiled into more than one target — `Theme`, `WatchLink`, `LoadScale`, `SharedStore` |

Schemes match the target names. The project uses file-system synchronised groups
(`objectVersion = 77`), so **new files are picked up automatically — never edit
`project.pbxproj` to add one.**

Bundle id `com.marwanmohamed.gymtrack`. The App Group
`group.com.marwanmohamed.gymtrack` is declared in **Release only**, deliberately:
Debug omits it so the app installs with a free Apple ID. The widgets read through
it; the app, watch and Live Activity never do.

## Why the data model looks like this

The logged data is being collected so that **an AI gym coach can read the
exported JSON later** (Settings → "Export a backup", `Services/BackupService.swift`).
That purpose decides arguments. Three rules follow from it, and they are not
negotiable:

1. **False detail is worse than missing detail.** A value that was inferred must
   never be presented as measured. A set with no data stores *no key* — not a
   null, not a zero, not a `"none"` sentinel. `WorkoutSession.hasHealthMetrics`
   treating a zero energy reading as "nothing recorded, not a workout that cost
   nothing" is the house standard.
2. **Anything undone leaves no trace.** A mis-tap is not data; recording it would
   mislead the reader. `SetLog.unlog()` is the single place a set is erased, and
   every undo path routes through it. `ActiveWorkout.clearRating`,
   `undoTakenNudge` and `cancelStart` follow the same rule for narrower gestures.
3. **Friction kills features here.** The logger is used mid-set with a bar in
   your hands. Nothing may block logging, nag, or need dismissing. Everything
   optional must cost zero taps when unused — a user who ignores a feature
   should not be able to tell it shipped.

## Where things live

- `Models/Entities.swift` — the SwiftData models: `Plan`, `PlanDay`, `PlanItem`,
  `WorkoutSession`, `SetLog`, `ExerciseNote`, and the derived `SessionExerciseGroup`.
- `Models/CatalogExercise.swift` — `ExerciseCatalog.shared`, ~414 bundled
  exercises from a JSON resource, plus the user's custom ones.
- `Models/SetFeel.swift` — the four effort answers. Stored as the 6–10 number the
  progression has always read; shown as Easy / Solid / Hard / All out.
- `Services/ActiveWorkout.swift` — drives an in-progress session. Objects are
  written as you go, so a force-quit mid-workout loses nothing.
- `Services/TrainingStats.swift` — pure functions over finished sessions. Volume,
  streaks, records, and the double-progression suggestion.
- `Services/BackupService.swift` — JSON export/import. **`version` is 2 and stays
  2**; every field added since is optional so older backups still decode. Read
  the comments on `bodyMetrics` / `loadScales` / `exerciseCatalog` before adding
  one.
- `docs/AI_COACH.md` — the proposed local-first AI coaching workflow, its
  intervention rules, and the experiment needed before claiming it improves
  training or the logging experience. Read it before designing AI coach work.
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

If every build suddenly exits 69, Xcode's licence needs re-accepting after a
major upgrade (`sudo xcodebuild -license accept`). Only the user can run that.

## Verifying on the simulator

Drive the real UI with `mcp__Claude_Code_iOS_Simulator__control` rather than
asserting from code. Find a booted device with `xcrun simctl list devices booted`.

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
- **The watch simulator is not granted for touch automation** on this machine.
- **`simctl launch` drops app arguments unless they follow `--`**:
  `launch --terminate-running-process <udid> <bundle> -- -GTSeedSampleData`.
  That flag seeds ~9 weeks of history, but only when an active plan already
  exists and there are no sessions yet.
- `simctl io screenshot` does not composite the Dynamic Island; its contents come
  out blank.

## House style

The prose in this codebase is deliberate. Match it.

- **Comments explain *why*, in plain prose, usually naming the failure they
  prevent.** They never narrate what the next line does. If a comment would just
  restate the code, delete it.
- Doc comments on types and on any property whose purpose isn't obvious.
- No emoji, anywhere.
- Prefer a named computed property over a clever inline expression — SwiftUI's
  type checker gives up on long chained ternaries inside a view builder, and it
  has already happened here more than once.

## Commits

Subject is a descriptive sentence, not a conventional-commit prefix. Look at
`git log`: *"Find every machine, and let the library be trimmed to your gym"*,
*"Say when a set starts, so the rest stops hiding the set inside it"*. The body
explains why in prose, not a bullet list of what changed.
