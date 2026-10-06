# Coaching policy

The scripts compute the numbers below; you do not redo or redefine them in a
review. Citations are the evidence the policy rests on, kept so a rule can be
questioned by its source rather than by taste.

## Definitions

**Working set.** A completed set with its continuations folded in: a drop or
cluster row belongs to the set before it and never counts as a separate effort.
Warm-ups are not working sets.

**Comparable exposure.** One session's working sets of one exercise where the
exercise, its tracking and its load (for reps and timed series) are unchanged,
and the session carries no `substitution` tag for it. A machine change starts a
new series; it is not a regression.

**Performance.** For a reps set of twelve reps or fewer, the Epley estimate the
app uses, capped at twelve: prediction equations are reasonably accurate up to
about ten reps and drift beyond it (LeSuer 1997), and a lifter's sense of reps
left also degrades past twelve (Halperin 2022). For longer sets, reps at the
session's most-used load, compared only with exposures at that load. For a
timed set, seconds held. An exposure's performance is its best working set,
with the mean of the rest kept beside it so a collapsing back-off stays visible.

**Noise.** A change counts only if it is larger than this lifter's
session-to-session wobble on that exercise: the typical error across consecutive
exposures, from their own data, because individuals differ markedly in it
(Hecksteden 2018). Until an exercise has six comparable exposures its noise is
unknown, and nothing about it may be called a change.

**Plateau.** No improvement larger than noise in best comparable performance
across at least four exposures spanning at least three weeks, while effort
answers are not trending easier, and with no pain tag, swap, shortened session
or logged-afterwards entry in the window to explain it. One bad session is never
a plateau. The script says why whenever it answers no.

**Effort.** Four ordinal buckets, not numbers: easy ("probably three or more
left"), solid, hard, allOut. Trust them more on sets of twelve reps or fewer
and on later sets. People tend to underestimate how many reps they had left by
about one, with wide spread (Halperin 2022), so a run of `hard` may sit nearer
two reps in reserve than one. Never convert the buckets to percentages of a
one-rep max. A missing answer is not a low one: check `effortAnsweredShare`.

**Weekly volume.** Working sets per muscle per local week, counted
fractionally: one for the exercise's first listed muscle, a half for each
further one. Fractional counting predicted hypertrophy and strength best in the
largest dose-response meta-regression to date, with diminishing returns, sooner
for strength than for size (Pelland 2025). More sets is never the default
answer to a stall.

**Adherence.** For sessions started from a plan day: working sets logged
against the slots' targets and against the rep targets. For a week: plan days
trained against plan days due.

**Size.** GymTrack measures performance, not muscle. Comparable performance in
the six-to-fifteen-rep range at comparable effort is the working proxy, and only
a proxy: reps can rise from skill or from bodyweight gained as fat. Read body
weight beside it. Tape measurements come from the owner's check-ins on the
phone's Progress tab; they are noisy and weighed lightly, and the waist tells
lean gain from fat gain. A skipped month is absent, never carried forward.

## The intervention ladder

Choose the smallest change the history supports:

1. Keep the current plan.
2. Adjust a repetition target or rest.
3. Add or remove one set.
4. Reorder or substitute one exercise.
5. Redistribute volume across the week.
6. Change the progression or set methodology.
7. Replace the training block.

Rungs 2 and 3 need a pattern across at least four comparable exposures. Rungs 4
and 5 need it across more than one slot, or a stated equipment or adherence
reason. One bad session triggers nothing. Rungs 1 to 5 can be proposed as
changes; 6 and 7 are not plan edits, so they can only be argued as advice with
evidence persistent across at least two reviews, which the owner acts on by
hand if persuaded.

## What a proposal may do

Six kinds exist: `setSets`, `setRepRange`, `setRest`, `substitute`, `addSlot`,
`removeSlot`. At most three changes, one per item.

**Loads belong to the phone.** Double progression reads a slot's target weight
only the first time an exercise is logged, then works from the weight last
lifted. A change that set a load on an exercise with history would be shown,
accepted and silently ignored. So there is no load operation: you change the
rules the progression works within (rep range, set count, rest, exercise choice
and order), and the phone keeps choosing the weight. A new exercise takes its
starting load from the phone's own logic; do not name one.

**No deload reflex.** In a randomized trial, a week without training in the
middle of nine left hypertrophy unchanged and reduced some lower-body strength
measures (Coleman 2024). There is no planned-deload operation. Persistent
fatigue is answered with the smallest rung that addresses it, usually one fewer
set on the affected slot.

## The goal is size, which orders the levers

1. **Effort before anything else.** Ending sets closer to failure meaningfully
   increased hypertrophy and barely moved strength (Robinson 2024). A slot whose
   sets keep coming back easy is under-stimulated; the first answer is a rep
   target that makes the set end nearer failure, not another set.
2. **Volume where it is short, within limits.** Weekly volume has a real dose
   response for size with diminishing returns (Pelland 2025), and per session
   the benefit stops being detectable at about eleven fractional sets for a
   muscle (Remmert 2025). A muscle that is behind and below that gets a set; a
   session already past it gets work moved to another day, not piled on.
3. **The owner's priorities.** Looks are not spread evenly. The profile names the
   muscles that matter most, and spare volume goes there first.
4. **Exercise choice as a tie-breaker.** Hypertrophy was similar across heavy,
   moderate and light loads when sets went to failure (Lopez 2021), so a rep
   range is mostly about comfort and how reliable the effort answers are, which
   favours roughly six to fifteen reps. Full or long ranges of motion showed
   small advantages (Wolf 2023); lengthened partials were no better than full
   range in trained lifters (Wolf 2025). A stretch-position exercise wins a
   substitution only when everything else is equal.

**Frequency is not a lever for size.** With volume equal, only strength showed a
consistent frequency effect (Pelland 2025). Redistributing across the week is
about per-session volume and fatigue, never frequency for its own sake.
Strength is how progress is read, but no change is made to raise it.

**Pain overrides progress.** A slot whose recent exposures carry a `pain` tag may
only be reduced, removed or substituted. Do not diagnose, never reason that pain
is harmless, and suggest seeing a professional when pain repeats.

**Consistency beats cleverness.** Current guidance emphasizes consistency,
effort and individualization over unnecessary complexity (ACSM 2026). A coach
that keeps changing things may look active while damaging the behaviour that
matters most: training regularly. If adherence is the problem, the answer is
usually not a plan edit.

## Every change is an experiment

Write each `reason` and each line of `notes.md` so the change reads as one: the
hypothesis, the evidence, the change, the success criterion (comparable
performance rising at comparable effort without lower adherence) and when to
look again (after six comparable exposures, sooner if pain or a sharp decline
appears). Next time, `stats.md` reports what happened to the touched lifts.
