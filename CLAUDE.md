# GymTrack

Native iOS 17 + watchOS 10 workout tracker: SwiftUI, SwiftData, all data on the device, no network.
A local session reads `docs/DEVELOPMENT.md` (builds, phone installs, test runs, simulator quirks)
before building or touching a simulator, and confirms all three schemes build before calling it done.

## Layout
| Path | What |
|---|---|
| `GymTrack/` | iPhone app: `App/`, `Models/`, `Services/`, `Features/`, `DesignSystem/` |
| `GymTrackWatch/` / `GymTrackWidgets/` | watchOS app / Home Screen widgets and the Live Activity |
| `GymTrackShared/` | Compiled into each target that needs it (not a module): `Theme`, `WatchLink`, `LoadScale`, `SetFeel`, `LaunchMode`, `TrainingDay` |
| `GymTrackTests/`, `GymTrackWatchTests/`, `GymTrackUITests/` | Swift Testing unit tests (helpers in `Support/`) and XCUITest flows |

Synchronised folders: a new file joins its folder's target. Never edit `project.pbxproj` to add one.

## The three data rules (not negotiable)
The JSON export (`Services/BackupService.swift`) is read later by an AI coach, so:
1. **False detail is worse than missing detail.** An inferred value is never shown as measured. A
   value with no data stores *no key*: not null, zero or a sentinel.
2. **Anything undone leaves no trace.** `SetLog.unlog()` is the single erase path;
   `ActiveWorkout.clearRating`, `undoTakenNudge` and `cancelStart` follow the same rule.
3. **Friction kills features.** Nothing may block logging, nag or need dismissing. Every optional
   feature costs zero taps when unused.
The backup's `version` stays 2; every field added since is optional.

## Architecture and test seams
- `Models/Entities.swift` holds the SwiftData models (`AppSchema.models` lists them).
  `Services/ActiveWorkout.swift` drives a live session, saving as it goes. `Services/TrainingStats.swift`
  is pure functions over finished sessions. Every suggested weight is a rung `LoadScaleBook` allows.
- Days are training days: before 04:00 is still the night before. Anything that buckets sessions by
  day or asks which day is today, on the phone, widget or watch, goes through `TrainingDay.key`.
- The watch link (`WatchCommandCenter`, `WatchBridge`, `WatchLink`) applies commands headlessly:
  iOS can wake a terminated app to deliver one.
- `LaunchMode`: a unit-test host opens an in-memory store, leaves singletons unconfigured and shows
  no `RootView` (`GymTrackApp.showsInterface`), so no launch work touches what a test set up;
  `-GTUITesting` gives UI tests a fresh install, an in-memory store, no prompts, no Live Activity.
- Seams: `TestStore`, `TestClock`, `ActiveWorkout.init(memory:)`, `RestTimer.init(notifier:)`, the
  `at:`/`now:` parameters on `TrainingStats`, and `defaults:` parameters. Prefer passing a value to a
  new protocol. UI code uses `DesignSystem/` (`Theme`, `gtCard`, ...); never invent colours or spacing.

## Tests
- Every behavior change adds or updates tests in the matching `*Tests.swift` in `GymTrackTests/`,
  `GymTrackWatchTests/` or `GymTrackUITests/`.
- `@MainActor @Suite(.serialized)`, `@Test`, `#expect`, `@Test(arguments:)` for edge cases. Dates from
  `TestClock`; `Date.now` only where the code checks its own clock; no sleeps; restore singletons in `defer`.
- A test exposing a real bug stays, in `withKnownIssue`; never weaken an assertion. UI tests find
  controls by accessibility identifier and wait with `waitForExistence`.

## Cloud runs and CI
`scripts/claude-pipeline/check.sh build` compiles all three targets and `check.sh test <Target/Suite>`
runs suites. Apart from `git` and `gh` for issues and pull requests, a cloud run may run only that, and runs
both on its change before every push.
`build-and-test` in `.github/workflows/pr-check.yml` runs every suite and gates merging. Every pull
request ends with the test checklist `.github/claude-test-checklist.md` describes. Any change
to the pipeline (workflows, `scripts/claude-pipeline/`, repo settings, the ruleset) updates
`docs/claude-pipeline.md` in the same PR.

## House style
- Comments explain *why* in plain prose, usually naming the failure they prevent; they never narrate
  the next line. Doc comments on types and non-obvious properties. No emoji. In view builders,
  prefer a named computed property to a long inline expression; the type checker gives up.
- Commit subjects are descriptive sentences (see `git log`), never `feat:` prefixes; bodies say why.
