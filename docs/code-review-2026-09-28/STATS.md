> Detail file from the 2026-09-28 review. The index, the canonical severities and the duplicate map are in [`../CODE_REVIEW_2026-09-28.md`](../CODE_REVIEW_2026-09-28.md). Where this file disagrees with the index, the index wins. Line numbers refer to the working tree on 2026-09-28 (HEAD f5809ff plus the uncommitted GT fix pass).

# Training stats, Progress dashboard and Today screen: findings

Files read in full: GymTrack/Services/TrainingStats.swift, GymTrack/Features/Progress/ProgressDashboardView.swift, GymTrack/Features/Progress/ProgressComponents.swift, GymTrack/Features/Progress/MuscleHeatMap.swift, GymTrack/Features/Progress/BodyAnatomy.swift (logic; contour tables skimmed), GymTrack/Features/Progress/BodyWeightCard.swift, GymTrack/Features/Today/TodayView.swift

Excerpts traced: Models/Entities.swift (Plan.day, WorkoutSession, SetLog), Models/SessionClosing.swift, Models/Muscle.swift, Models/CatalogExercise.swift (canonicalID), Services/ActiveWorkout.swift (SessionFactory, recordBaseline, addExercise), App/RootView.swift, Services/WidgetPublisher.swift, Services/WatchBridge.swift, Services/WatchCommandCenter.swift, Services/HealthKitService.swift (body mass), Services/LoadScaleBook.swift, GymTrackShared/LoadScale.swift, GymTrackShared/Units.swift, Features/Plans/PlansView.swift, Features/Plans/DayEditorView.swift, Features/Session/SessionSummaryView.swift, Features/Session/ActiveWorkoutView.swift, Tests/TrainingStats*.swift.

The DST behaviour in STATS-01 was checked by running the same Foundation calls in a scratch Swift script with `TimeZone(identifier: "Africa/Cairo")` (outside the repo).

## Prior findings re-check
- GT-014: OK. `TodayView.swift:467` and `ProgressDashboardView.swift:131` now convert with `weightUnit.fromKg` before `compactVolume`. Every other volume readout in the area already went through `Metric.value` (`TrainingStats.swift:565`). The widget and watch readouts convert too.
- GT-015: OK. `sessions(in:days:)` (`TrainingStats.swift:60-67`) now covers today and the six days before it, matching the `daily` buckets. `previousWindow` (`:613-622`) starts exactly where it ends, and `TrainingStatsCalendarTests` pins both boundaries. The one exception is the DST transition day covered in STATS-01.
- GT-016 (stats side): OK. `history`, `lastPerformance`, `records`, `recordCandidates`, `recordSets` and `earlierSets` all compare `ExerciseCatalog.canonicalID`. One reader was missed: `topExercises` tallies by `set.exerciseName` (`TrainingStats.swift:700`), so a merged or renamed exercise shows up as two pills in the muscle panel. That is cosmetic.
- GT-017: OK. `records(in:)` now picks a measure per tracking mode (`TrainingStats.swift:231-254`), and `isPersonalRecord` keeps a separate baseline for each mode (`:301-315`). The presentation problems that remain are in STATS-08.
- GT-018: OK for the calendar (`TrainingStats.trainedDays` at `:71-74`, `ProgressComponents.swift:359-364`). The fix's rule, that an empty session is not a trained day, is not applied by `streak` or by the Today week strip, so these now disagree with the calendar. See STATS-05.
- GT-022: OK. `weeklySessionCounts` (`TrainingStats.swift:635-645`) ends its newest bucket at tomorrow's midnight, filters out active sessions, and lines up with `weeklyTrend`'s 7-day chunks. The DST caveat from STATS-01 applies here too.

## Findings

### STATS-01: The streak and every daily chart break on midnight DST transitions (Africa/Cairo)
- Severity: P2
- Category: bug
- Confidence: confirmed (the same Foundation calls were run with `Africa/Cairo`)
- Location: `GymTrack/Services/TrainingStats.swift:18-41` (`streak`), `:587-600` (`daily`), `:100-111` (`dailyVolume`), `:635-645` (`weeklySessionCounts`); `GymTrack/Features/Progress/ProgressComponents.swift:247-253,316` (`ConsistencyGrid.firstDay`, grid cells); `ProgressDashboardView.swift:848-857` (`dayLabel`)
- What happens: Day keys come from `calendar.startOfDay(for:)`, but day stepping uses `calendar.date(byAdding: .day, value: -1, to: cursor)` with no re-normalisation. Egypt's spring-forward jumps from 00:00 to 01:00 on the last Friday of April, so `startOfDay` for that Friday is 01:00. Two things go wrong:
  - Stepping back one day from Friday 01:00 gives Thursday 01:00. That never equals Thursday's key (00:00), so `while days.contains(cursor)` stops.
  - `dateComponents([.day], from: Fri 01:00, to: Sat 00:00).day` is 0 (only 23 hours), so the `gap == 1` test in the longest-run loop fails.

  On the transition day itself, `today` is 01:00, so every `daily()` bucket and every grid cell is generated at 01:00 and matches nothing.
- Failure scenario: Scratch-script run in `Africa/Cairo`, the user's probable zone:
  - Sessions on 22–26 April 2026, viewed on the 26th: `streak.current == 3` and `longest == 3`, when both should be 5. Every past April transition permanently splits "Best streak".
  - On Friday 24 April 2026, with sessions on 20–23 April: `streak == 0`, so the Today flame is hidden and the widget and watch show 0. `daily()` matches 0 of 4 trained days, so the trend chart, weekly sparklines and 17-week calendar all read as untrained all day.

  The same applies to other zones that shift at midnight (Beirut, Santiago, Asuncion, Havana). Separately, every stat re-buckets stored UTC instants in the *current* zone, so travelling moves late-night sessions to neighbouring days and can split or merge streak days.
- Suggested fix: Normalise after every step. Use `calendar.startOfDay(for: calendar.date(byAdding: .day, value: -1, to: cursor)!)` in `streak`. In `daily`, `weeklySessionCounts`, `sessions(in:)`, `previousWindow` and `ConsistencyGrid`, anchor the date arithmetic on noon, or build keys from `DateComponents(year:month:day:)`. Replace the `dateComponents(.day)` gap test with "normalised next day equals this day". Delete the unused `dailyVolume`: it has the same flaw and returns kilograms where `daily(.volume)` returns display units.
- Verify by: Add a `TrainingStatsCalendarTests` case that passes a `Calendar` with `timeZone = Africa/Cairo` and `now` injected (the functions need a `now:` parameter). Assert a 5-day streak across 24 April 2026, a non-zero streak on the Friday itself, and `daily()` hits on the four prior days.

### STATS-02: The progression reads a partial or off-plan last session as a full working session and re-prescribes the load from it
- Severity: P2
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Services/TrainingStats.swift:411-413,443-474` (`suggestion`), `:182-196` (`lastPerformance`); `GymTrack/Services/ActiveWorkout.swift:22-31,36-43` (`SessionFactory.build`)
- What happens: `lastPerformance` returns the logged effort sets of the most recent session that contains the exercise, whatever that session was. `close()` has already pruned the unlogged sets. `allHitTop` is `setsAtWeight.allSatisfy { $0.reps >= item.targetRepsHigh }` and never compares the number of sets with `item.targetSets`. The suggestion's weight becomes the logger's starting weight (`startingWeight = ... suggestion.weightKg`), and on `.increaseWeight` every set is prefilled with `suggestion.reps`.
- Failure scenario:
  1. The plan asks for 3×8–12 at 60 kg. Last time the lifter logged one set of 60×12 and then finished the session early. Next session the card says "You cleared 12 reps on every set. Go to 62.5 kg", and all three sets open at 62.5×8, although only one set was ever done at 60.
  2. The planned lift is 80 kg for 6–8. In between, the lifter does a light freestyle technique set of the same exercise at 40×20. `allHitTop` is true (20 ≥ 8), so the planned day opens at 42.5 kg for 6 reps, about half the working load, with a message congratulating a range that was never attempted.

  A related smaller problem: after a `.deload` suggestion the reps prefill falls through to `previous?.reps`, which is last time's short count. The message says "rebuild" at 57.5 kg, but the sets open at 57.5×5 instead of the bottom of the range.
- Suggested fix: In `suggestion`, only return `.increaseWeight` when `setsAtWeight.count >= item.targetSets`. Otherwise return `.repeatLoad` with a message that says what was logged ("Last time only 1 of 3 sets was logged. Repeat 60 kg."). Give `lastPerformance` an optional `planDayID` and have `SessionFactory.build` pass `day.id`, so the most recent session of the same plan day is preferred and any session is the fallback. In `SessionFactory`, use `suggestion.reps` for `.deload` as it already does for `.increaseWeight`.
- Verify by: Unit tests on `TrainingStats.suggestion` with (a) one logged set at the top of the range against `targetSets = 3`, which should give `.repeatLoad`; (b) a freestyle 40×20 newer than a planned 80×7, which should prescribe off 80; (c) the deload reps prefill.

### STATS-03: Today never suggests a session for plan days that are not pinned to a weekday, which is the default for days the user adds
- Severity: P2
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Models/Entities.swift:36-43` (`Plan.day(for:)`, `day(onWeekday:)`); `GymTrack/Features/Plans/PlansView.swift:232` (`PlanDay(name: "New Day", order:)` with `weekday` nil); `GymTrack/Features/Today/TodayView.swift:17,120-124,381-406`; `GymTrack/App/RootView.swift:244-247`; `GymTrack/Services/WatchCommandCenter.swift:69-76`
- What happens: `scheduledDay` is `activePlan?.day(for: .now)`, and that only matches a `PlanDay` whose `weekday` equals today's. "Add day" creates days with `weekday == nil`, and `DayEditorView` treats "none" as a valid choice. A routine built by hand without assigning weekdays (for example a Push/Pull/Legs rotation) is never "scheduled", so the hero falls through to `restDayCard`.
- Failure scenario: The user builds "Push", "Pull" and "Legs" and leaves the weekday picker alone. Every day, Today says "Rest day. Nothing scheduled. Recovery is part of the plan", and the week strip shows no dashed scheduled days. Siri, the widget's "start today" and the watch's Start Today all start a freestyle session (`startScheduledSession` falls to `startFreestyle`), so the double-progression prefill never runs. The app states "Rest day" as fact when the plan says nothing of the kind, and every workout costs the extra "Pick a session" taps.
- Suggested fix: Add `Plan.nextDay(after sessions:)`. When no pinned day matches today and the plan has unpinned training days, return the unpinned day that follows, in `orderedDays`, the `planDayID` of the most recent finished session, wrapping around, or the first unpinned day. Use it in `TodayView.scheduledDay`, `RootView.startScheduledSession`, `WatchCommandCenter` `.startToday`, `WidgetPublisher` and `WatchBridge`. Title the card "Next up" rather than "Today's session". Only show "Rest day" when every training day is pinned.
- Verify by: With a plan of three unpinned days and a finished "Push" session, Today shows "Pull". Start Today from the widget, Siri or the watch builds "Pull" with its prefilled loads. A fully pinned plan behaves as it does now.

### STATS-04: A mistyped weigh-in cannot be deleted, and a correction leaves the wrong value in Health
- Severity: P2
- Category: data-rule
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Progress/BodyWeightCard.swift:172-189` (`record`), `:129-166` (`actions`); `GymTrack/Services/HealthKitService.swift:531` (`saveBodyMass`); `GymTrack/Services/BackupService.swift:293,365` (export)
- What happens: The card offers "Log weight" and "Import", and nothing else. No path in the app deletes a `BodyMetric`, except Erase All in `BackupService.wipe`. `record` writes the entry and fires `saveBodyMass` straight away. Re-logging the same day overwrites the local row, but the first, wrong sample stays in Health as its own sample. A weigh-in saved on the wrong date cannot be moved or removed at all.
- Failure scenario: The lifter types 8.2 instead of 82 (the stepper's typed-entry alert makes this easy), or saves with yesterday still selected in the date picker. The chart spikes, the "change" figure is nonsense, and the exported `bodyMetrics` hands the AI coach a body weight the lifter never had. That breaks rule 2: a mis-tap is not data. Correcting the value on the same day fixes the local row but leaves 8.2 kg in Health. Because the day already has an entry, a later import will not reconcile it either.
- Suggested fix: Make the latest entry (and ideally a short list of recent entries) swipe-to-delete, or add an "Undo" affordance right after saving. Deleting a manual entry should also delete the Health sample the app wrote. Keep the `HKQuantitySample` UUID on the `BodyMetric` when saving, and pass it to a new `HealthKitService.deleteBodyMass(id:)`. When the same day is overwritten, delete the previously written sample instead of adding a second one.
- Verify by: Log 8.2 kg, delete it, and check that the card, the export and Health all no longer contain it. Log two values on the same day and check that Health holds only the second.

### STATS-05: An empty finished session counts toward the streak, "This week" and session totals, while the calendar and Today call it untrained
- Severity: P2
- Category: data-rule
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Services/TrainingStats.swift:19` (`streak` filters only `!isActive`), `:52-56` (`finishedToday` excludes empty sessions), `:71-74` (`trainedDays` excludes them); `GymTrack/Features/Today/TodayView.swift:18,26-30,413`; `ProgressDashboardView.swift:130,149,358`; `GymTrack/Models/SessionClosing.swift:60-68`; `GymTrack/Features/Session/ActiveWorkoutView.swift:70-72,210-215`; `GymTrack/Services/WidgetPublisher.swift:44-46`
- What happens: The logger's Finish is always available. With nothing logged, `close()` deletes every row and stamps `endedAt`, which leaves a finished session with no sets. The stale-session path (`RootView.swift:478-479`) and the watch discard path delete such a session, but a manual Finish keeps it. Readers then split:
  - `finishedToday` ("An empty session is not a day trained") and the GT-018 `trainedDays` exclude it.
  - `streak` (Today flame, Progress, widget, watch), the Today week-strip checkmark (`trained` at `TodayView.swift:413`), "This week N of M planned", the Progress "Sessions" tile, the hero's "N sessions" and "Avg session" all count it.
- Failure scenario: The lifter opens a freestyle session by mistake and taps Finish, then "Finish workout" ("Every set logged. Nice work." because `totalCount` is 0). Today's week strip shows a check, the streak goes up by a day, and "This week" reads one more of the planned sessions. Progress shows a Rest cell for the same day, and Today's hero still offers the scheduled workout. A mis-tap has become adherence data.
- Suggested fix: Fix it at the source. In `ActiveWorkout.finish()` (and `WatchCommandCenter.finish`), when `session.completedSets.isEmpty`, route to `discard()` instead of `close()`, and change the alert text for that case ("Nothing was logged, so this session won't be kept."). Then remove the "empty ones included" special case from `WidgetPublisher`. If empty sessions must stay, then `streak`, `thisWeek`, the week strip and the session counts should all use `trainedDays`' predicate.
- Verify by: Start freestyle, finish with no sets, and check that the streak, the week strip, "This week" and the Progress session count are unchanged, and that no session appears in history or the export. Add a unit test for `streak` with an empty finished session.

### STATS-06: The Progress tab rebuilds every figure from every set of the history on each metric tap, window tap and first appear
- Severity: P2
- Category: performance
- Confidence: likely (the call graph is traced; the timings below are estimates, not measurements)
- Location: `GymTrack/Features/Progress/ProgressDashboardView.swift:35` (`ProgressFigures` built in `body`), `:325-365` (`init`), `:376-381` (`weeklyTrend`), `:10,86` (`barsGrown`); `GymTrack/Services/TrainingStats.swift:587-600` (`daily` walks all sessions, not the window), `:71-74`, `:215-266`, `:675-685` (`lastTrained`)
- What happens: `ProgressFigures.init` runs inside `body`. It depends on `metric`, `window`, `barsGrown` and the `@Query`, and it walks every set of the full history about seven times:
  - `daily(metric)` over all sessions (1 walk)
  - `volumeByDay` (1)
  - `trainedDays` (1)
  - `records` (1, with repeated `tracking` string parses)
  - `weeklyTrends` for three metrics (3)

  `daily()` calls `metric.value(of:)` on every finished session before bucketing, although it only keeps 7 to 119 days. Tapping Volume, Sets or Reps changes only `points`, yet it recomputes records, the calendar and the trends too. `barsGrown` flips 0.35 s after the first appear and forces a second full pass.
- Failure scenario: With 300 sessions × 25 sets (7,500 `SetLog`s), one pass is about 52,000 set visits and roughly 150–200k SwiftData attribute reads (`isCompleted`, `continuesPreviousSet`, `trackingRaw`, `weightKg`, `reps`, `catalogID`). All of them run on the main thread and are all registered for observation, because they happen inside `body`. At around 1 µs per observed read, that is about 0.15–0.3 s per tap on a pill, paid twice on first open, and more on the first fault from SQLite. Only a few percent of that work feeds what is on screen. `HeatMapCard` also calls `lastTrained` from its `body`. That re-sorts the already-sorted sessions, and for a muscle never trained it walks all 7,500 sets with a catalog lookup, on every flip or selection. Speculative: if `@Query` refreshes while a workout is logged and the Progress tab is alive under the logger overlay, the same pass runs on *Log set*.
- Suggested fix: Build one lightweight `SessionDigest` per finished session in a single walk: `day`, `volumeKg`, `effortSets`, `reps`, `hasCompletedSets`, `duration`, per-muscle credits. Cache it in `@State` keyed on the query's session IDs and `endedAt`s (recompute `.onChange`), and derive `daily`, `weeklyTrend`, `trainedDays`, `sessions(in:)` and the ratios from digests. Pre-filter to the widest window needed (`max(2 × window, 119)` days) before any set is read. Keep `records` in the same cache so metric and window taps never recompute it. Split the metric-dependent `points` and `rolling` out of the figures.
- Verify by: Seed 300 × 25 with `-GTSeedSampleData` (extended). In Instruments (Time Profiler, SwiftUI), a Volume/Sets/Reps tap should take a few milliseconds of main-thread time instead of about 100 ms or more, and `ProgressFigures.init` should not appear on the `barsGrown` transaction.

### STATS-07: The active workout keeps deleted sessions as its PR baseline and "last time" source (possible crash)
- Severity: P2 (P1 if the crash reproduces)
- Category: bug
- Confidence: speculative for the crash; the stale baseline is confirmed
- Location: `GymTrack/Services/ActiveWorkout.swift:97,106-121` (`history`, `lastPerformances`), `:348-356` (`recordBaseline`), `:786-789` (`addExercise`); `GymTrack/Features/Session/SessionSummaryView.swift:415-424` (`SessionDetailView` delete); `GymTrack/Features/Today/TodayView.swift:476-487,66`
- What happens: `ActiveWorkout` captures `history: [WorkoutSession]` at start. It caches `lastPerformances` and, on the first logged set, `recordBaseline`, and both hold `SetLog` model references. While the session is minimised, Today's "Recent sessions" opens `SessionDetailView`, whose trash button runs `context.delete(session); try? context.save()`. Nothing refreshes the workout's caches afterwards.
- Failure scenario: Start a workout, minimise it, open a past session from Today, delete it, return, and then either (a) log a set of an exercise that session contained (`isPersonalRecord` reads `catalogID`, `tracking` and `completedAt` on deleted `SetLog`s), or (b) add an exercise (`lastPerformance` walks `history`, reaching the deleted session's `sets` relationship). At best, the deleted session keeps acting as the record to beat and the "was 60 × 8" hint, which defeats a user who deleted a bad session to fix their records. At worst, SwiftData traps on reading a relationship of a deleted, saved model.
- Suggested fix: Hold `PersistentIdentifier`s rather than models, or rebuild `history`, `lastPerformances` and `recordBaseline` when the context saves a deletion of a `WorkoutSession`. The simplest route: observe `ModelContext.didSave` in `ActiveWorkout` and nil the caches, refetching finished sessions lazily. At minimum, filter `history` with `$0.modelContext != nil && !$0.isDeleted` before every walk.
- Verify by: On a simulator build, follow the scenario above and confirm there is no crash, that the PR trophy fires against the remaining history, and that the "last time" hint comes from the newest surviving session.

### STATS-08: The records card shows the date of a later tie, an e1RM inflated by high-rep sets, and figures from different sets on one row
- Severity: P3
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Services/TrainingStats.swift:225-265` (`records`), `:233,237,243` (`max(by:)`), `:239-240,245-248`; `GymTrack/Models/Entities.swift:636-640` (`estimatedOneRepMax`); `ProgressDashboardView.swift:219-239,252-276`
- What happens: There are four separate problems on this card:
  - **Tied records take the newest date.** `max(by:)` keeps the first maximal element, and the sets arrive newest session first. The record's `achievedAt` is therefore the most recent tie, not the day the record was set. `isPersonalRecord` uses a strict `>`, so the logger never awarded a trophy on that day, yet the card sorts by `achievedAt` and moves the exercise to the top with a trophy.
  - **High-rep sets inflate the e1RM.** Epley has no rep cap. 60 kg × 30 estimates 120 kg and beats 100 kg × 5 (116.7 kg). That gives a trophy on the logger, and a card row reading "100 kg × 5, 1RM ≈ 120 kg" dated the day of the 60 × 30 set. The heaviest set, the e1RM and the date come from different sets.
  - **"Best reps" mixes loaded and unloaded sets.** For bodyweight it counts weighted sets too (`matching` includes them), while `isPersonalRecord` keeps unloaded reps separate.
  - **The trophies suggest a ranking that no longer exists.** Trophies for the first three rows and numbers 4–8 imply a rank, but the list is now sorted by recency.
- Failure scenario: Bench 100×5 on 1 January, 100×5 again on 1 March. The card says "1 Mar" with a trophy at the top, and nothing fired on 1 March.
- Suggested fix: Break ties with the earliest `recordDate` (`max(by:)` with a date tiebreak). Exclude sets over about 12 reps from e1RM ranking in both `records` and `isPersonalRecord`, and treat them as rep records at that load instead. Take the date and the headline from the same set (show `best` set's weight × reps plus its e1RM). Split bodyweight "Best reps" into unloaded reps and "most added". Drop the numbering and trophies, or rank properly within each mode.
- Verify by: Unit tests for a tie (earliest date wins), a 30-rep light set (no record, no card change), and a bodyweight exercise with weighted sets.

### STATS-09: Today declares "You're done for today" after any session, hiding the scheduled workout
- Severity: P3
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Today/TodayView.swift:22,118-121,228-285`; `GymTrack/Services/TrainingStats.swift:52-56`
- What happens: `completedToday` is any non-empty session whose `endedAt ?? startedAt` falls today, and it takes precedence over `scheduledDay`. It does not check `session.planDayID == scheduledDay?.id`. It also uses `endedAt`, where every other stat buckets by `startedAt`.
- Failure scenario: Two variants:
  - Leg Day is scheduled today, and the lifter does a 10-minute freestyle arm pump in the morning. The hero now says "WORKOUT DONE… You're done for today", and Leg Day takes Start another workout, then the picker, then Legs.
  - A session runs from 23:10 to 00:40. The next day's hero reads "WORKOUT DONE" and hides that day's scheduled session, while the week strip puts the session on the previous day.
- Suggested fix: Show `completedCard` only when the finished session is today's scheduled day, or when nothing is scheduled. Otherwise keep `scheduledCard` with a one-line "Also done today: Arms · 6 sets". Use `startedAt` for "today", as the other readers do.
- Verify by: Scheduled day plus an unrelated finished freestyle session: the scheduled card still shows, with the note. A session that crosses midnight does not hide the next day's plan.

### STATS-10: "This week" means different things on Today and on Progress
- Severity: P3
- Category: bug
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Today/TodayView.swift:25-30` (`dateInterval(of: .weekOfYear)`, comment says "since Monday"), `:410-413`; `ProgressDashboardView.swift:99,129-133` ("THIS WEEK" is `lastWeek` = rolling 7 days); `ProgressComponents.swift:249-253` (grid is always Sunday-first)
- What happens: The labels do not match the data behind them:
  - Today, the widget and the watch count the locale's calendar week. The Egyptian locale starts it on Saturday, not the Monday the comment claims.
  - The Progress hero is also labelled "THIS WEEK", but counts the last 7 days.
  - The consistency grid hard-codes Sunday as the first row, whatever the locale.
- Failure scenario: On a Monday after training Thursday, Friday and Sunday, Today says "This week 1" (Sat–Mon) while Progress says "THIS WEEK · 3 sessions". The heat map's "weekly target" is judged on the same rolling 7 days, so the two screens can give opposite verdicts on the same week.
- Suggested fix: Label the Progress hero "LAST 7 DAYS", or make both screens use the calendar week. Start the grid on `calendar.firstWeekday` (rotate `veryShortWeekdaySymbols` and the `firstDay` offset). Fix the comment.
- Verify by: The same data seen on both screens on a mid-week day reads consistently.

### STATS-11: The body-weight trend spaces weigh-ins evenly and gives no time span for its change figure
- Severity: P3
- Category: data-rule
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Progress/BodyWeightCard.swift:92-127` (x by index at `:106-107`), `:28-31,65-69` (`change`), `:79-81`
- What happens: There are three honesty problems on this card:
  - **The chart plots by position, not by date.** x is `index / (count - 1)`. Ten weigh-ins in one week followed by one ten weeks later draw as a long wiggle and one short segment, so the shape (the card's stated purpose) misstates the rate of change.
  - **The change figure gives no period.** "+1.2 kg" is first-to-last within 84 days, but whether that is 5 days or 12 weeks is never said.
  - **The empty state claims something it cannot know.** It says "Nothing in Health to import" whenever sync is on. HealthKit hides denied read access, so the app cannot know that.
- Failure scenario: A lifter who weighs in sporadically sees a steep line for a small change spread over two months.
- Suggested fix: Put x on the date axis (Swift Charts `LineMark` with `x: date` fits in 54 pt). Caption the change ("since 12 Jul"). Change the empty text to "No weigh-ins found in Health".
- Verify by: Uneven sample data renders proportional spacing, and the change carries its start date.

### STATS-12: No regression tests for the progression, the streak or any non-local calendar
- Severity: P3
- Category: test-gap
- Confidence: confirmed (traced end to end)
- Location: `Tests/` (no test calls `TrainingStats.suggestion` or `streak(from:)`); `Tests/TrainingStatsCalendarTests.swift:15` (uses `Calendar.current`)
- What happens: The functions that decide the next load and the streak, both shown on the watch, widget and Today, have no tests. The calendar tests run only in the machine's zone, on whatever day they happen to run. STATS-01, STATS-02 and STATS-05 would all have been caught by cheap cases.
- Suggested fix: Add a `now:` parameter (default `.now`) to `streak`, `sessions(in:)`, `daily`, `previousWindow` and `weeklySessionCounts`. Add tests with `Africa/Cairo` and a fixed `now`. Add `suggestion` cases for each `feel` branch, a partial last session, a 3–5 range where `targetRepsLow - 2` makes the deload unreachable, duration, and unloaded bodyweight.
- Verify by: `scripts/test-training-stats-calendar.sh` and a new `scripts/test-progression.sh` pass, and fail on the current code for STATS-01 and STATS-02.

### STATS-13: Progress cannot say which lifts are moving and which have stalled
- Severity: P3
- Category: missing-feature
- Confidence: confirmed (traced end to end)
- Location: `GymTrack/Features/Progress/ProgressDashboardView.swift` (the cards are volume, sets, muscles and all-time records)
- What happens: Everything needed is already logged. `history(for:)` gives per-exposure e1RM, reps and seconds, and `feel` gives effort. Yet the dashboard answers "how much" and never "is it working". An all-time record board says nothing about a lift that has been flat for six weeks, and that is the first question a coach, human or AI, asks.
- Suggested fix: Add a "Lifts" card that costs zero taps. For each exercise with at least 3 exposures in 8 weeks, compare the latest exposure's best (e1RM on loads of 12 reps or fewer, reps at load for unloaded bodyweight, seconds for duration) with the median of the previous three, and tag it moving, flat or sliding. When `trackRPE` is on, also flag "same load, harder feel" (median feel up a step at an unchanged top weight), an early fatigue signal. Keep it derived and on screen only; do not add it to the export, where the coach can compute it from the raw sets.
- Verify by: Sample data with one lift progressing, one flat and one regressing shows three correct tags. A lifter who never opens the card sees no other change.
