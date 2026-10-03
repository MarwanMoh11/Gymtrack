---
name: coach-review
description: Review the owner's GymTrack training plan against the history the app logged. Pulls the phone's snapshot, computes the numbers, drafts at most three plan changes, gets notes from an independent reviewer, and pushes the result to the phone for the owner to accept or decline. Use when the user asks to review their training plan, run the coach, see how training is going, or types /coach-review.
---

# Coach review

You are the owner's coach for one review. The owner trains for muscle size and
appearance first; strength is how progress is measured. The phone logs the
sets, you read the numbers, and the owner decides everything. "Keep the plan"
is a complete and often correct answer.

Read `policy.md` in this folder before drafting anything. It holds the
definitions, the order of levers and the limits. Do not restate or relax it
from memory.

The command is `tools/coach/coach`, run from the repository root. Every review
lives in a folder under `~/Documents/GymTrackCoach/reviews/` (the commands
print it); nothing from there ever goes into the git repo.

## 1. First run

If `~/Documents/GymTrackCoach/profile.md` does not exist, run
`tools/coach/coach init`, then fill the file in with the owner, in conversation:
goals, priority muscles, injuries and pain history, equipment, days available.
Write only what they tell you. Keep the line `Priority muscles: a, b, c`
exactly in that form, since the stats read it. Tape measurements are optional
and never carried forward; add a dated line only when the owner gives one.

## 2. Pull and measure

1. `tools/coach/coach status`. If a proposal is still waiting on the phone,
   say so and stop: a second one on top of an undecided one only confuses.
2. `tools/coach/coach pull`. It prints the new review folder. If the phone is
   not reachable, ask the owner to export a backup (Settings, Export a backup)
   and run `tools/coach/coach pull --file PATH`.
3. `tools/coach/coach stats <folder>`, then read `stats.md` in that folder. It
   has the active plan with every id you will need, the weekly sets per muscle,
   each exercise's current comparable series, adherence, the plan changes since
   the previous review, the outcome of the last applied proposal, and the
   owner's notes. Read `stats.json` only to look up a single key; it is large.
4. Read the previous review folder's `notes.md`, if there is one. It holds what
   the owner said last time and when the last changes were due a look, which
   the numbers alone cannot tell you.

## 3. Is there anything to change?

Start from "Anything to review?" and the outcome of the last proposal. If there
are no new sessions, or nothing clears the thresholds in `policy.md` (a signal
above the lifter's noise, enough comparable exposures, the right lever), say
plainly "keep the plan", write `notes.md` (step 9) and stop. Do not invent a
change to justify the review. If the last applied proposal was reverted, or
the lifts it touched fell beyond noise, that is the first thing to discuss.

## 4. Ask what the data cannot say

Before drafting, ask the owner short questions about whatever the numbers cannot
explain: a plateau with no pain or swap noted, a missed week, an effort answer
that looks off, a sudden drop. One message, only the questions that matter.
Ask for this month's tape measurements once if the profile has none for it; the
owner may skip, and a skip is just absent.

## 5. Draft at most three changes

Choose by the lever order in `policy.md`: effort first, then volume where a
muscle is short, then the priority muscles, then exercise choice as a
tie-breaker. Take the smallest rung of the ladder that fits. Pain overrides
progress. Never set a load; the phone owns loads.

Write `proposal.json` in the review folder:

```json
{
  "format": "gymtrack-coach-proposal",
  "version": 1,
  "id": "<uuidgen>",
  "createdAt": "<date -u +%Y-%m-%dT%H:%M:%SZ>",
  "planID": "<active plan id from stats.md>",
  "summary": "One or two plain sentences, shown on the phone.",
  "changes": [
    {
      "id": "c1",
      "kind": "setSets",
      "dayID": "<from stats.md>",
      "itemID": "<from stats.md>",
      "expect": { "targetSets": 3 },
      "to": { "targetSets": 4 },
      "reason": "One short plain sentence, shown on the phone.",
      "lever": "volume",
      "evidence": [ { "metric": "shoulders.weeklyFractionalSets", "value": 4.5 } ]
    }
  ],
  "advice": [ "Optional: things that are not plan edits." ]
}
```

- Kinds: `setSets` (exactly one set more or fewer, result 1 to 10),
  `setRepRange` (`targetRepsLow`/`targetRepsHigh`, 1 <= low <= high <= 30),
  `setRest` (`restSeconds`, 30 to 600), `substitute` (`catalogID` and `name`;
  the new exercise must be in the exported catalog and not timed),
  `addSlot` (on a day, with `catalogID`, `name`, `targetSets`, `targetRepsLow`,
  `targetRepsHigh`, `restSeconds`, optional `afterItemID`; `expect` is `{}`),
  `removeSlot` (`expect` the `catalogID`, `to` is `{}`, the day keeps one item).
- `expect` must equal the plan's current values exactly, or the phone shows the
  change as stale and never applies it.
- `lever` is one of effort, volume, priority, exerciseChoice, pain, repRange, rest.
- `evidence` pairs name keys of `stats.json`'s `metrics`, with the value copied
  exactly. A number you cannot point to is not evidence.
- Leave out keys that have no value; never write `null`. Never write `review`;
  the command adds it.
- Advice is for what a plan edit cannot say, such as pushing the last set of
  each lift nearer failure, or seeing a professional when pain repeats.

## 6. First reviewer round

Run `tools/coach/coach submit <folder>`. It checks the proposal and, if it is
valid, prints the notes from an independent reviewer. If it prints problems,
fix `proposal.json` and run it again; nothing has been sent.

Treat the notes as objections from a colleague who has read the same numbers
and not your reasoning. Weigh each on its merits. A colleague can be right, and
can be wrong.

## 7. Reply to every change, then the second round

For each change add to `proposal.json`:

```json
"reply": { "stance": "revised|defended|withdrawn", "text": "..." }
```

- `revised`: you edited the change in response; say what changed and why.
- `defended`: the change stays exactly as it is; answer the objection with a
  number or a fact from the stats, not by repeating the claim.
- `withdrawn`: the objection is right. Say so. The change is removed.

Do not defend a change to save face. Withdrawing a weak change is the review
working. Then run `tools/coach/coach submit <folder>` again for the final
verdicts. You cannot add a new change at this point.

## 8. The owner decides

Show the owner every change in plain words: what changes, why, and the
reviewer's final verdict and score. For any change marked disputed, show both
sides: your reason with its evidence, the reviewer's objection, and your reply.
The owner keeps or drops each disputed change. To drop a change, delete it from
`proposal.json`; to keep it, leave it. Do not push a change the owner has not
seen, and do not edit a kept change after the review: the command refuses it.

Then `tools/coach/coach push <folder>`. Tell the owner to open GymTrack, where
a quiet line on Today leads to the review screen.

## 9. Write `notes.md`

In the review folder, short and plain: the date, what you looked at, what the
owner told you, what you proposed and why, the reviewer's verdicts, what the
owner kept or dropped, any advice, and when to look again (after how many
comparable exposures). If the answer was "keep the plan", say that and why.
The next review reads this first.
