# AI coach: the coach loop

Status: design note for a feature under construction. Rewritten 2026-10-03,
after the owner chose a simpler design than the research draft proposed. It
records the loop, the contract between the phone and the Mac, the policy the
coach follows and how we will tell whether it helps.

## Decision

A review of the lifter's training runs as a conversation in Claude Code on the
Mac, weekly to monthly, when the lifter types `/coach-review`. The phone stays
fast, offline and deterministic. The app never touches the network; the Mac does
the reaching, over the same developer connection the install script uses.

The goal is muscle size and how the physique looks, ahead of strength. That
orders the coach's levers (see "Coaching policy") and decides what counts as
progress (see "Definitions").

The review is interactive on purpose. The coach can ask about what the data
cannot show, such as a sore shoulder that was never tagged or a week of travel,
and the lifter can push back before a change reaches the phone. That exchange is
the main quality gain over a script that emits a plan, and it costs nothing the
lifter was not already paying, since a review happens at the Mac anyway.

Three things are automated because each saves effort at every review: the app
writes its export into its own Documents folder, and the Mac pulls it and pushes
the proposal back with `devicectl`; proposals are reviewed, applied and undone
on the phone; and ratings are built into the app. Everything else the research
draft pictured is cut, each with the event that would bring it back (see
"Later, if needed").

The durable work is the contract around the model, which is replaceable: export
observations without inventing missing data, limit a proposal to six kinds of
edit the phone can apply and undo, show a before and after the phone computed,
and record what was proposed, accepted, declined, reverted and rated. GymTrack
has one lifter, and everything here is sized for that.

## How a review works

1. The lifter runs `/coach-review`. The Claude Code session that answers is
   "the coach".
2. `coach pull` copies the app's snapshot and decisions off the phone with
   `xcrun devicectl` into a new review folder. When the phone is out of reach,
   `coach pull --file` takes a manual export instead.
3. `coach stats` computes the numbers the definitions below describe. Arithmetic
   belongs to code: in Google's evaluation of LLM agents over wearable data, a
   model reasoning over numbers in text answered 22% of objective numerical
   questions correctly and an agent that ran analysis code answered 84%
   (Merrill 2026). When an exercise has too few comparable exposures to say
   anything, the stats say so, and "keep the plan" is a complete review. A review
   is a decision point, not an obligation to manufacture novelty.
4. The coach reads the stats and notes, first checking the outcome of every
   change applied since the last review (see "How we will know it helps"). It
   asks the lifter about anything the data cannot explain, may ask for this
   month's tape measurements (skippable), and drafts at most three changes plus
   any advice.
5. `coach submit` validates the draft, then hands it to the reviewer, a separate
   process (next section), for two rounds. A change still disputed after round 2
   is flagged, and the lifter decides at the Mac whether to keep it.
6. `coach push` copies the final proposal into the app's inbox on the phone.
7. On the phone the lifter reads it, accepts or declines each change, applies
   them in place, can undo, and can rate it (see "The phone side").
8. Decisions and ratings travel back in `decisions.json` with the next pull,
   which is where the next review starts.

Nothing nags: neither the app nor the Mac says a review is due. Everything for
reviews lives in `COACH_HOME` (default `~/Documents/GymTrackCoach`): `profile.md`
at its root, holding the standing context (the muscles that matter most for the
look he wants, equipment limits, old injuries, anything not to propose), and one
folder per review at `reviews/YYYY-MM-DD/` (suffix `-2`, `-3` for a second one
the same day). It holds real history, so it never enters the git repo.

## The reviewer

The reviewer is a skeptical hypertrophy coach, run by `coach submit` as a
completely separate `claude -p` process: fresh context, no tools, never shown the
coach's conversation or reasoning, and told only that "a coach" proposed the
changes. It gets the stats, the profile and the notes, and the changes as data
(what changes on which slot, the lever, the numbers cited), not the coach's
prose. It answers through files in two rounds. Round 1 is an agreement or
objection per change, with a score and a line. The coach then revises or defends
each change. Round 2 is the reviewer's final verdict. `coach submit` writes the
verdicts into each change's `review` field; the coach never does. The reviewer's
prompt lives in `tools/coach/`, not in the coach's skill, so the coach cannot
read it and write to please it.

**Why it is separate.** By the time the coach drafts a change it has spent a
conversation absorbing the lifter's answers and its own reasoning, and a reviewer
inside that context would inherit both. A fresh context cannot be talked into
reasoning it never receives.

**What it will not do.** It is the same model, so it is not an independent second
opinion. When two models are both wrong they pick the same wrong answer about 60%
of the time against 33% by chance, and more accurate models are more alike in
their mistakes (Kim 2025; Goel 2025). Models also favour their own writing
(Panickssery 2024), which is why the reviewer gets data, not prose. A shared
misconception about training, such as how much volume a muscle tolerates, would
pass both. The defences sit elsewhere: a written policy, small reversible
changes, and the lifter's rating.

**What it is for.** Catching slips in reading this lifter's data: a pain note the
coach missed, noise read as a trend, a cited number that is not in the stats, a
change that contradicts the profile. A fresh session does that well. Its
agreeing is not evidence a change is right; the lifter's rating stays the final
word, because only results show whether a change worked. A reviewer from a
different model family was considered and dropped as micromanaging for one lifter
(see "Later, if needed").

## The phone side

A lifter who never runs a review pays nothing for any of this: an inbox nobody
fills, a snapshot file, and one row in Settings.

- **Today.** When a proposal is waiting, one quiet line. No badge, no
  notification, nothing when a review falls due.
- **Review screen.** The summary, then one card per change: the slot before and
  after as the phone computes it, the reason, and the reviewer's line (verdict, score, note, and a mark when the change is
  disputed and was kept anyway). Each change is accepted or declined on its own;
  advice is text with no button. Refused while a workout is running, as a restore
  is.
- **Stale changes.** The phone checks every change against the live plan. One
  whose `expect` values no longer match its slot is marked stale: shown, never
  applicable. There is no rebase; the answer is the next review. Sessions logged
  since the export do not make a change stale, but a `pain` tag logged on that
  slot since is shown on its card.
- **Applying.** One save, editing the existing plan items in place. Day and item
  IDs survive, so the rotation, Today and the widgets carry on; copying the plan
  would mint new day IDs, and `Plan.nextInRotation` keys on them, so the rotation
  would restart at day one.
- **Undo is not revert.** Undo on the screen where the change was applied, before
  leaving it, is a mis-tap: the plan is restored and the decision record erased,
  as if nothing happened (house rule 2). Revert later, from Settings, abandons a
  change that was trained on, which is information, so it restores the plan and
  stamps `revertedAt`. Revert refuses, and says why, when the touched slots no
  longer hold the applied values because the lifter edited them since.
### Ratings

A rating is a score and an optional note on a decision, with the time given. It
costs zero taps when unused. The lifter mostly rates himself, usually twice: when
deciding, on whether the change looks reasonable, and again after weeks of
training under it, on whether it worked. The second carries the evidence.

Sometimes the phone is handed to someone else, a friend who trains or a coach at
the gym. The app records who rated, `self` or `other` with an optional name, and
a rating by someone else is never filed as the lifter's, because false detail is
worse than missing detail. In hand-off mode the reviewer's verdict is hidden from
the other rater until they have rated. A person who sees "the reviewer agrees"
tends to go along, and the reason to ask a second person is an independent
judgement.

## Data contract

The two sides are built to this section. Neither changes it alone.

### Paths

On the phone, in the app's Documents directory:

| Path | Written by | What |
|---|---|---|
| `Documents/Coach/snapshot.json` | app | The full backup archive, the same bytes and format as Settings, "Export a backup" (`BackupService.Archive`, version 2). |
| `Documents/Coach/decisions.json` | app | Decisions and ratings (below). |
| `Documents/Coach/Inbox/proposal.json` | Mac, `coach push` | The proposal awaiting a decision. The app creates `Inbox/` at launch so the destination always exists. |
| `Documents/Coach/Inbox/ratings.json` | app | Ratings given before the proposal is decided. They move into the decision record when it is decided, and are dropped if a new proposal replaces this one undecided. |

The app writes `snapshot.json` atomically when a workout finishes, when a plan
is saved, when a proposal is applied or reverted, and at launch if the file is
missing, never on the logging path. `xcrun devicectl` reaches the container on
development-signed builds, which is all a free Apple ID makes:

```
xcrun devicectl device copy from --device <id> --domain-type appDataContainer \
  --domain-identifier com.marwanmohamed.gymtrack --source Documents/Coach/snapshot.json --destination <local>
xcrun devicectl device copy to   --device <id> --domain-type appDataContainer \
  --domain-identifier com.marwanmohamed.gymtrack --source <local> --destination Documents/Coach/Inbox/proposal.json
```

### What the export carries, and how to read it

`PlanDTO` and `DayDTO` already carried their `id`; `ItemDTO` gains an optional
one, written from the entity's existing `id`. Restore keeps it when present and
mints one when it is absent or repeated. A proposal can then name a slot without matching on exercise or
position. `version` stays 2 and older backups still decode. The comments in
`BackupService.swift` list every field; these are the ones a misreading would
turn into false detail:

- An absent key means "not measured" or "not prescribed", never zero. A squat has
  no `seconds`, a plank no `reps`, a slot with no target no target key.
- `effort` (`easy`, `solid`, `hard`, `allOut`) is the field to read. `rpe` beside
  it is a bucket code, not a point RPE: `easy` is stored as 6 though it only
  means "three or more reps left". An `rpe` with no `effort` predates 2026-09-19
  and has no word attached; neither key means not rated.
- A session with no `heartRateSource` or `energySource` has unknown origin and
  must not be read as phone-only or as low effort.
- A `loggedAfterwards: true` session counts as training, but nothing timed
  (duration, rests, density) may be worked out from it.
- Notes carry the tags `pain`, `formBreakdown`, `substitution`, `feltStrong` and
  `feltFlat`. `hiddenExercises` are exercises the lifter trimmed because the gym
  lacks them, and are never proposed. Dates are UTC; `timeZone` gives the local day.

### proposal.json

```json
{
  "format": "gymtrack-coach-proposal",
  "version": 1,
  "id": "UUID",
  "createdAt": "2026-10-03T18:20:00Z",
  "planID": "UUID of the active plan the changes target",
  "summary": "One or two plain sentences for the phone.",
  "changes": [
    {
      "id": "c1",
      "kind": "setSets",
      "dayID": "UUID",
      "itemID": "UUID",
      "expect": { "targetSets": 3 },
      "to": { "targetSets": 4 },
      "reason": "Short plain sentence shown on the phone.",
      "lever": "volume",
      "evidence": [ { "metric": "chest.weeklyFractionalSets", "value": 7.5 } ],
      "review": { "verdict": "agree", "score": 4, "note": "One line.", "disputed": false }
    }
  ],
  "advice": [ "Not plan edits, such as ending the last set of each lift nearer failure." ]
}
```

Both validators (`coach submit`, and the phone against its live plan) enforce:

- At most three changes, one per `itemID`, with unique change IDs. `planID` is the
  active plan and every `dayID` and `itemID` exists in it.
- `expect` matches the item's current values exactly. That is the whole
  staleness test; there is no plan fingerprint.
- `reason`, `lever` and `evidence` are required. `evidence` pairs name keys from
  `stats.json`, which the reviewer checks. `lever` is one of `effort`, `volume`,
  `priority`, `exerciseChoice`, `pain`, `repRange`, `rest`.
- `review` is written by `coach submit` and may be absent, in which case the phone
  shows no reviewer line. `disputed: true` means the reviewer still objects after
  round 2 and the lifter chose to keep the change.
- `advice` is optional. Unknown keys are ignored. A key with no value is omitted,
  never `null`.

Six kinds, and nothing else is accepted:

| kind | needs | expect | to | limits |
|---|---|---|---|---|
| `setSets` | dayID, itemID | `targetSets` | `targetSets` | exactly one more or one fewer; result 1 to 10 |
| `setRepRange` | dayID, itemID | `targetRepsLow`, `targetRepsHigh` | same keys | 1 <= low <= high <= 30 |
| `setRest` | dayID, itemID | `restSeconds` | `restSeconds` | 30 to 600 |
| `substitute` | dayID, itemID | `catalogID` | `catalogID`, `name` | target is in the exported catalog and not timed; sets, reps and rest carry over; no load is set |
| `addSlot` | dayID | `{}` | `catalogID`, `name`, `targetSets`, `targetRepsLow`, `targetRepsHigh`, `restSeconds`, optional `afterItemID` (absent means end of day) | same limits; not a rest day; not timed |
| `removeSlot` | dayID, itemID | `catalogID` | `{}` | the day keeps at least one item |

### decisions.json

```json
{
  "format": "gymtrack-coach-decisions",
  "version": 1,
  "decisions": [
    {
      "proposalID": "UUID",
      "receivedAt": "ISO8601",
      "decidedAt": "ISO8601",
      "changes": [ { "id": "c1", "decision": "accepted", "note": "optional" } ],
      "appliedAt": "ISO8601, absent when nothing was applied",
      "before": [ { "dayID": "UUID", "itemID": "UUID", "item": { "...enough to restore it exactly, order included..." } } ],
      "after": [ "same shape as before: what the apply wrote, so a later revert can tell whether the slot was edited since" ],
      "revertedAt": "ISO8601, absent unless reverted later",
      "ratings": [ { "rater": "self", "score": 4, "note": "optional", "ratedAt": "ISO8601" },
                   { "rater": "other", "raterName": "optional", "score": 3, "ratedAt": "ISO8601" } ]
    }
  ]
}
```

A change's `decision` is `accepted`, `declined` or `stale`. This is a file in
Documents, not a SwiftData entity: the Mac reads it directly and it never needs
migrating with the store.

## Definitions the coach reasons with

`coach stats` computes these, and the coach does not redefine them in a review.

**Working set.** A completed set with its continuations folded in: a drop or
cluster row (`continues`) belongs to the set before it and is never a separate
effort. Sets in a `loggedAfterwards` session count, but contribute nothing timed.

**Comparable exposure.** One session's working sets of one exercise where the
exercise (`catalogID`), its load scale and its tracking are unchanged and the
session carries no `substitution` tag for it. A machine change starts a new
series; it is not a regression.

**Performance.** For a reps set of twelve reps or fewer, the Epley estimate the
app already uses, capped at twelve for the reason `TrainingStats` gives:
prediction equations are reasonably accurate up to about ten reps (LeSuer 1997),
and a lifter's sense of reps left degrades past twelve (Halperin 2022). For longer
sets, reps at the session's most-used load, compared only with exposures at that
load; for a timed set, seconds held at the same load. An exposure's performance
is its best working set, with the mean of the rest kept beside it so a collapsing
back-off stays visible.

**Noise.** A change counts only if it is larger than this lifter's
session-to-session wobble on that exercise, the typical error of performance
across consecutive stable exposures, estimated from his own data because
individuals differ markedly in it (Hecksteden 2018). Until an exercise has six
comparable exposures its noise is unknown, and nothing about it may be called a
change.

**Plateau.** No improvement larger than noise in an exercise's best comparable
performance across at least four exposures spanning at least three weeks, while
the effort answers are not trending easier, and with no pain tag, swap,
shortened session or logged-afterwards entry in the window to explain it. One bad
session is never a plateau.

**Effort.** The four answers are ordinal buckets, not numbers. Trust them more on
sets of twelve reps or fewer and on later sets of an exercise. People tend to
underestimate their reps left by about one (Halperin 2022), so a run of `hard`
may sit nearer two reps in reserve than one, and `easy` means "probably three or
more", nothing finer. Never convert the buckets to percentages of a one-rep max.

**Weekly volume.** Working sets per muscle per local week, counted fractionally:
one for the exercise's first listed muscle and a half for each further one. That
counting predicted both hypertrophy and strength best in the largest
dose-response meta-regression to date, with diminishing returns that come sooner
for strength than for size (Pelland 2025). More sets is never the default answer
to a stall.

**Adherence.** For a session started from a plan day, working sets logged
against the slots the day held and the rep targets the sets recorded. For a
week, plan days trained against plan days due.

**Size.** GymTrack measures performance, not muscle. Comparable performance in
the six-to-fifteen-rep range, at comparable effort, is the working proxy for
growth, and only a proxy: reps can rise from skill, or from bodyweight gained as
fat, so body-weight history is read beside it. A direct measure is optional and
never on the phone: the coach may ask for this month's tape measurements (arm,
chest, waist, thigh), which the lifter can skip. They stay in the review folder,
weighed lightly because a tape is noisy, and a skipped month is absent, never
carried forward. The waist tells lean gain from fat gain.

## Coaching policy

### The intervention ladder

The coach chooses the smallest change the history supports:

1. Keep the current plan.
2. Adjust a repetition target or rest.
3. Add or remove one set.
4. Reorder or substitute one exercise.
5. Redistribute volume across the week.
6. Change the progression or set methodology.
7. Replace the training block.

Larger interventions need stronger and more persistent evidence. Rungs 2 and 3
need a pattern across at least four comparable exposures. Rungs 4 and 5 need it
across more than one slot, or a stated equipment or adherence reason. A single bad
session triggers nothing.

### What a change can apply, and what it can only advise

Rungs 1 to 5 are the six change kinds. Reordering has no kind of its own: moving
a lift is a `removeSlot` plus an `addSlot`, which spends two of the three
changes, so it needs a reason worth two. Redistributing volume is the same pair
on two days. Rungs 6 and 7 cannot be applied, since GymTrack has one progression
method and a new method or block is a design change, not a plan edit. The coach
may argue for them as `advice`, with evidence that has persisted across at least
two reviews, and the lifter acts on it by hand if persuaded. Effort mostly
travels as advice too: "end the last set nearer failure" is not a plan field.

**Loads belong to the phone.** Double progression reads a slot's `targetWeightKg`
only the first time an exercise is logged; after that it works from the weight
last lifted (`TrainingStats.suggestion`). A change that set a load on an exercise
with history would be validated, shown, accepted and then silently ignored by the
logger. So no kind carries a load, not even for a new exercise: it starts with
none, the lifter finds a weight on the first day, and the phone's rules take over.
The coach changes the rules the progression works within and the phone keeps
choosing the weight.

**Deloads are not a reflex.** In a randomized trial, a week without training in
the middle of nine left hypertrophy unchanged and reduced some lower-body
strength measures (Coleman 2024). There is no planned-deload kind. Persistent
fatigue gets the smallest rung that addresses it, usually one fewer set on the
affected slot.

**Size orders the levers.** For hypertrophy the evidence points the coach at
these, roughly in this order:

1. **Effort before anything else.** Ending sets closer to failure meaningfully
   increased hypertrophy and barely moved strength (Robinson 2024). A slot whose
   sets keep coming back `easy` is under-stimulated, and the first answer is a
   rep target that ends the set nearer failure, not another set.
2. **Volume where it is short, within limits.** Weekly volume has a real dose
   response for size, with diminishing returns (Pelland 2025), and per session
   the benefit stops being detectable at about eleven fractional sets for a
   muscle (Remmert 2025). A muscle that is behind and below that gets a set; a
   session already past it gets the work moved to another day, not piled on.
3. **The lifter's priorities.** Looks are not spread evenly. The profile names
   the muscles that matter most, and spare volume goes there first.
4. **Exercise choice as a tie-breaker.** Hypertrophy was similar across heavy,
   moderate and light loads taken to failure (Lopez 2021), so a rep range is
   mostly comfort and how reliable the effort answers are, which favours roughly
   six to fifteen reps. Full or long ranges of motion showed small advantages
   (Wolf 2023), and lengthened partials were no better than full range in
   trained lifters (Wolf 2025), so a stretch-position exercise wins a
   substitution only when all else is equal.

Frequency is not a lever of its own for size: with volume equal, only strength
showed a consistent frequency effect (Pelland 2025). Moving work across the week
is about per-session volume and fatigue. Strength remains a measure of progress,
but no change is made to raise it.

**Pain overrides progress.** A slot whose recent exposures carry a `pain` tag may
only be reduced, removed or substituted. The coach does not diagnose, does not
reason that pain is harmless, and suggests seeing a professional when it
repeats. The reviewer is asked specifically to check this, and the phone shows a
`pain` tag logged on a slot since the export.

### Every change is an experiment

The coach states each change as a hypothesis, the evidence, the change, a
success criterion (say, reps rising at comparable effort without lower
adherence) and a review point (after six comparable exposures, or sooner if
pain appears), and the next review reads it back. The proposal carries only the
evidence (for the reviewer) and the reason (for the phone), so the coach writes
the success criterion and review point in the review folder.

## How we will know it helps

One lifter and a few changes a quarter cannot show that the coach beats the
phone's own double progression, and nothing here claims it. The loop yields three
kinds of evidence, in order of weight.

**The owner's ratings.** He rates each proposal when deciding and again after
training under it. The second rating is the result: did the change, in his
judgement and with the numbers in front of him, work. Other raters are a sample,
not a panel, and are recorded as such.

**Reviewer against owner, over time.** Each review shows whether the reviewer is
useful: how often it objected in round 1 (a reviewer that never objects does no
work), how often the lifter accepted a change it endorsed, and how disputed
changes turned out. One that agrees with the coach nearly always, or whose
objections the lifter never upholds, is the signal to try a different model.

**The outcome check at each review.** Before drafting, the coach looks at every
change applied since the last review: still in place, overridden (the slot no
longer holds the applied values) or reverted; whether comparable performance on
the slot moved by more than noise; whether effort answers, adherence and pain
tags moved with it. This is a record, not an
experiment: there is no control, and season, sleep and bodyweight move at the
same time. It tells the coach whether its last advice led anywhere before it
gives more, and it tells the lifter whether to keep trusting it.

Effectiveness is read from what normal logging produces: planned sessions and
working sets completed, comparable performance rising by more than noise,
progress sustained past the first weeks, and the guardrails (pain, excess
all-out effort). Raw tonnage is not a success metric, since a coach raises it by
prescribing more work, and app opens are not either. Satisfaction is secondary
evidence: a polished explanation can feel intelligent and produce nothing.

## Later, if needed

Each was considered and cut for the owner's current use. Each names the event
that would bring it back.

- **Unattended runs** (a headless `claude -p` on a schedule, or launchd): if
  remembering to review becomes the problem.
- **Managed Agents, or a relay on the Mac**: only if the app is ever allowed a
  network.
- **A reviewer from a different model family**: if the reviewer agrees with the
  coach suspiciously often, or shared misses show up.
- **A physio-brief second reviewer**, told only to look for pain and injury risk:
  if pain calls slip through.
- **A synthetic exam** (generated histories with a planted answer): if a change
  to the skill, policy or reviewer's prompt needs a regression check and the real
  history is too thin to supply one.
- **Blind rating** with decoys made by simple rules, and agreement statistics: if
  the owner's ratings start to look like a rubber stamp.
- **Friends' Strong or Hevy logs as replay cases**: if his own history is too
  short to test a changed coach against.
- **A formal single-case trial**: if the owner wants to claim a change worked, not
  just keep a record. Single-subject designs suit a treatment that cannot be
  withdrawn (Kinugasa 2004); micro-randomized trials suit nudges, not plan
  changes, whose effects carry over (Qian 2022).
- **A load kind**, a one-shot reset of a slot's weight: if reviews show the need.
  It needs a logger change first (see "Loads belong to the phone").

## Decisions and open questions

Decided on 2026-10-03, by the owner:

- Size and appearance come before strength. Reviews are weekly to monthly.
- Reviews are interactive in Claude Code on the Mac. No headless runs, launchd,
  Managed Agents or relay. The app stays offline, and the paid developer program
  is not being taken; the install script keeps the app signed.
- The reviewer is a skeptical hypertrophy-coach persona in a separate `claude -p`
  session, two rounds, still-disputed changes to the lifter. A different-model
  reviewer was dropped for now.
- Six change kinds, staleness by `expect` values, decisions in a JSON file, one
  quiet Today line, and a mis-tap undo that erases while a later revert stamps.
- The lifter rates, the rater is always recorded, and in hand-off mode the
  reviewer's verdict is hidden until the other rater has rated.
- Readiness checks, sleep, HRV, resting heart rate and bodyweight at session time
  were rejected earlier: they assume the watch is always worn and ask for daily
  discipline. Do not propose them again.

Still open:

- Sending the export (training history, body weight, notes) to the model provider
  is implied by choosing Claude Code and has not been said outright. The reviewer
  runs through the same provider, so it adds no new recipient.
- Whether hand-off mode should hide the lifter's own rating from the other rater
  too, since it anchors the same way the reviewer's verdict does.

## Where the code lives

- `tools/coach/`: the Mac side, Python 3 standard library only. Pull, stats,
  validate, the reviewer's rounds and prompt, push, and the profile template. Its
  tests use synthetic fixtures; real training history never enters the repo.
- `.claude/skills/coach-review/`: the coach's procedure and the policy above, run
  by `/coach-review`. It never contains the reviewer's prompt.
- `GymTrack/Services/Coach/`: the phone side. Snapshot writing, inbox reading,
  validation against the live plan, the review screen, apply, undo, revert,
  `decisions.json` and ratings. It never talks to a network.
- `GymTrack/Services/BackupService.swift`: the export, with the optional `id` on
  plans, days and slots.

## What research currently supports

The evidence supports plausibility and a way to check, not a claim that a
periodic frontier-model review improves resistance training.

On AI exercise advice the findings are mostly cautionary. A 2026 systematic
review of 24 studies found factual accuracy often acceptable but comprehensiveness
poor, contraindications missed, no adjustment to feedback, and AI programmes
inferior to human experts in every head-to-head (Biology of Sport 2026). Twelve
coaching experts rated GPT-4 and Gemini hypertrophy plans as moderate, better
with detailed prompts (Havers 2024). Another panel found chatbot hypertrophy and
strength plans lacking intensity detail such as proximity to failure, unable to
tell the two goals apart, and blind to individual response (Havers 2025).
One-shot GPT-4 prescriptions were safe but unspecific (Dergaa 2024), and another
evaluation found 41.2% of gold-standard recommendation content present (Füzéki
2024). Repeated generations from one model agreed in wording and varied in
quantities, intensity above all (Lee 2026), which is why proposals are typed
fields with validator limits.

All of that was measured on older models with generic prompts and no training
history. This design supplies the history, a written policy and a way to push
back, and answers each finding on purpose: history and policy for
comprehensiveness, pain tags and the pain rule for contraindications, the loop
and the conversation for feedback, and three small reversible changes for the
experts' edge. That is the argument for the design, not a result of it.

Around the model: over 10 weeks, adherence was 88.2% with in-person supervision,
81.2% with app guidance and 52.2% with a static PDF in 79 trained adults, so app
guidance supports adherence without reproducing good coaching (Gavanda 2025). A
single-subject LLM running-coach case named its gaps as text-only data relayed
by hand, no persistent model of the athlete and no guardrails (Lee 2025); the
export, stored decisions and validator here are aimed at those. Adaptive digital
exercise has shown objective effects in populations unlike this one (Netz 2025;
Lee, PEARL 2025), and an AI label alone can raise expected performance without
improving results (von Felten 2026), so any comparison would label options
neutrally.

On the training science, the citations in "Definitions" and "Coaching policy"
carry their own claims. The 2026 American College of Sports Medicine guidance
adds one caution, emphasising consistency, effort and individualisation over
unnecessary complexity. A coach that keeps changing methods can look active while
damaging the behaviour that matters most, which is training consistently.

## References

- Biology of Sport, *The AI recommendation paradox: a systematic review of LLMs in exercise recommendation* (2026):
  https://www.termedia.pl/The-AI-recommendation-paradox-a-systematic-review-evaluating-the-promise-peril-and-path-forward-for-large-language-models-in-exercise-recommendation,78,57447,1,1.html
- Kim et al., *Correlated Errors in Large Language Models*, ICML (2025): https://arxiv.org/abs/2506.07962
- Goel et al., *Great Models Think Alike and this Undermines AI Oversight*, ICML (2025): https://arxiv.org/abs/2502.04313
- Havers et al., *Reproducibility and quality of hypertrophy-related training plans generated by GPT-4 and Google Gemini as evaluated by coaching experts*, Biology of Sport (2024): https://pmc.ncbi.nlm.nih.gov/articles/PMC11963122/
- Havers, Jelonnek, Masur et al., *A professional assessment of training plans for muscle hypertrophy and maximal strength developed by generative artificial intelligence*, Biology of Sport (2025): https://pmc.ncbi.nlm.nih.gov/articles/PMC12492345/
- Gavanda et al., *Optimizing Resistance Training Outcomes: Comparing In-Person Supervision, Online Coaching, and Self-Guided Approaches* (2025): https://pmc.ncbi.nlm.nih.gov/articles/PMC12529976/
- Lee, *Consistency of AI-Generated Exercise Prescriptions: A Repeated Generation Study Using a Large Language Model* (2026 preprint): https://arxiv.org/abs/2604.11287
- Merrill, Paruchuri, Rezaei et al., *Transforming wearable data into personal health insights using large language model agents*, Nature Communications (2026): https://www.nature.com/articles/s41467-025-67922-y
- Lee, *Exploring Large Language Model as an Interactive Sports Coach: Lessons from a Single-Subject Half Marathon Preparation* (2025 preprint): https://arxiv.org/abs/2509.26593
- Panickssery, Bowman, Feng, *LLM Evaluators Recognize and Favor Their Own Generations*, NeurIPS (2024): https://arxiv.org/abs/2404.13076
- Netz et al., *A Smartphone Platform for Remote Motor Fitness Assessment and AI-Generated Personalized Exercise Programs for Older Adults* (2025): https://pmc.ncbi.nlm.nih.gov/articles/PMC12527324/
- Lee et al., *A Personalized Exercise Assistant using Reinforcement Learning (PEARL)* (2025 preprint): https://arxiv.org/abs/2508.10060
- Qian et al., *The Micro-Randomized Trial for Developing Digital Interventions* (2022): https://pmc.ncbi.nlm.nih.gov/articles/PMC9276848/
- Dergaa et al., *Using artificial intelligence for exercise prescription in personalised health promotion* (2024): https://pmc.ncbi.nlm.nih.gov/articles/PMC10955739/
- Füzéki et al., *Comprehensiveness, Accuracy, and Readability of Exercise Recommendations Provided by an AI-Based Chatbot* (2024): https://pmc.ncbi.nlm.nih.gov/articles/PMC10811574/
- von Felten et al., *AI Washing Inflates Expected Performance but Not Interaction Outcomes* (2026): https://arxiv.org/abs/2605.00582
- Pelland et al., *The Resistance Training Dose Response: Meta-Regressions on Weekly Volume and Frequency*, Sports Medicine (2025): https://link.springer.com/article/10.1007/s40279-025-02344-w
- Robinson et al., *Exploring the Dose-Response Relationship Between Estimated Resistance Training Proximity to Failure, Strength Gain, and Muscle Hypertrophy*, Sports Medicine (2024): https://link.springer.com/article/10.1007/s40279-024-02069-2
- Remmert, Pelland et al., *Is There Too Much of a Good Thing? Meta-Regressions of the Effect of Per-Session Volume on Hypertrophy and Strength* (2025 preprint): https://sportrxiv.org/index.php/server/preprint/view/537
- Lopez et al., *Resistance Training Load Effects on Muscle Hypertrophy and Strength Gain: Systematic Review and Network Meta-analysis*, Medicine & Science in Sports & Exercise (2021):
  https://www.ovid.com/jnls/acsm-msse/fulltext/10.1249/mss.0000000000002585~resistance-training-load-effects-on-muscle-hypertrophy-and
- Wolf et al., *Partial Vs Full Range of Motion Resistance Training: A Systematic Review and Meta-Analysis*, International Journal of Strength and Conditioning (2023): https://doi.org/10.47206/ijsc.v3i1.182
- Wolf et al., *Lengthened partial repetitions elicit similar muscular adaptations as full range of motion repetitions during resistance training in trained individuals*, PeerJ (2025): https://pmc.ncbi.nlm.nih.gov/articles/PMC11829627/
- Halperin et al., *Accuracy in Predicting Repetitions to Task Failure in Resistance Exercise*, Sports Medicine (2022): https://link.springer.com/article/10.1007/s40279-021-01559-x
- Coleman et al., *Gaining more from doing less? The effects of a one-week deload period during supervised resistance training on muscular adaptations*, PeerJ (2024): https://peerj.com/articles/16777/
- LeSuer et al., *The Accuracy of Prediction Equations for Estimating 1-RM Performance in the Bench Press, Squat, and Deadlift*, Journal of Strength and Conditioning Research (1997): https://www.unm.edu/~rrobergs/478PredictionAccuracy.pdf
- Hecksteden et al., *Repeated testing for the assessment of individual response to exercise training*, Journal of Applied Physiology (2018): https://journals.physiology.org/doi/full/10.1152/japplphysiol.00896.2017
- Kinugasa, Cerin, Hooper, *Single-Subject Research Designs and Data Analyses for Assessing Elite Athletes' Conditioning*, Sports Medicine (2004): https://link.springer.com/article/10.2165/00007256-200434150-00003
- American College of Sports Medicine, 2026 resistance-training guidance: https://acsm.org/resistance-training-guidelines-update-2026/
