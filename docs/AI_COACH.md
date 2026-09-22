# AI coach: product direction and proof standard

Status: design note, not an implemented feature.

This document records the intended direction for an AI coach so later work does
not have to reconstruct it from conversation. It describes a local-first
workflow, the boundary between ordinary progression and deeper coaching, and
the evidence required before GymTrack should claim that the coach helps.

## Decision

Do not build a bespoke model orchestration platform inside GymTrack. Keep the
phone fast, offline, and deterministic during a workout. Periodically hand a
structured snapshot to a frontier model running through an existing agent
harness on the user's Mac, then import a validated, user-approved plan proposal.

The durable GymTrack work is the contract around the model:

1. Export observations without inventing missing data.
2. Explain the meaning and provenance of every field.
3. Constrain what a proposal is allowed to change.
4. Show a readable diff and rationale before applying it.
5. Record what was proposed, accepted, edited, rejected, and later observed.
6. Evaluate the coach against the current progression system before making any
   effectiveness claim.

The frontier model is replaceable. The data contract, audit trail, guardrails,
and evaluation design are the product.

## System shape

```text
Workout on iPhone or Watch
        |
        v
Structured session history in SwiftData
        |
        +--> Immediate, deterministic suggestions on the phone
        |    (double progression, legal machine rungs, obvious holds/backoffs)
        |
        v
User-initiated review snapshot, approximately monthly
        |
        v
Frontier agent on the Mac reads the snapshot and performs analysis
        |
        v
Versioned PlanProposal + evidence + uncertainty + evaluation criteria
        |
        v
GymTrack validates it and shows a before/after diff
        |
        v
User accepts, edits, or rejects each material change
        |
        v
Accepted plan becomes a new, traceable training block
```

The cadence is not a promise that the plan must change every month. "Keep the
plan" is a valid and often preferable conclusion. A review is a decision point,
not an obligation to manufacture novelty.

## Responsibilities

### The phone

The phone owns anything that must be instant, predictable, or available without
a connection:

- logging sets and preserving unfinished sessions;
- rest timing and Watch synchronization;
- unit conversion and equipment-specific load rungs;
- the existing double-progression rules;
- conservative next-set or next-session suggestions;
- proposal validation and the approval experience;
- the canonical history of plans, sessions, and accepted changes.

These paths must remain usable when the AI coach has never been configured.

### The frontier agent

The agent handles slower questions whose answer needs history and synthesis:

- distinguish a one-session fluctuation from a persistent plateau;
- compare performance at similar loads, rep ranges, and reported effort;
- find deterioration across sets, exercises, days, and weeks;
- determine whether extra volume is producing progress or only fatigue;
- notice repeated substitutions, skipped movements, shortened sessions, or
  equipment constraints;
- assess session density, measured rest, duration, exercise order, and recovery
  patterns without treating them as equivalent signals;
- propose machine changes, set-count changes, weekly redistribution, deloads,
  or a different progression method when the evidence warrants them;
- state what evidence would falsify its recommendation.

The agent must distinguish facts, derived metrics, and hypotheses. It may infer
that a pattern is consistent with fatigue; it may not rewrite that inference as
a measured recovery score.

## Information already available

`BackupService.Archive` is the natural read model. Version 2 already carries:

- active and historical plans, including days, exercise order, target sets,
  target rep ranges, target loads, rest intervals, and notes;
- session start and end times, session and exercise notes, and note tags;
- every logged set's exercise, load, reps, duration, targets, and timestamps;
- optional set effort, expressed as RPE-compatible values;
- measured versus inferred per-set heart-rate windows;
- session heart rate, energy, Watch provenance, and body-weight history;
- load-nudge offers and whether they were taken or declined;
- drop-set and cluster continuations, so one extended effort is not mistaken for
  several collapsing working sets;
- exercise metadata and each machine's unit and legal increment.

The existing export rules remain non-negotiable: missing is not zero, inferred
is not measured, and an undone action leaves no analytical trace.

Useful future signals should be added only when they are low-friction and have
clear semantics. Candidates include pain or discomfort, the reason for an
exercise substitution, why a set ended, technique breakdown, equipment
availability, and a very small readiness check. None may block logging or nag a
user who ignores it.

## Intervention ladder

The agent should choose the smallest change supported by the history:

1. Keep the current plan.
2. Adjust the next load or repetition target.
3. Add or remove one set.
4. Reorder or substitute one exercise.
5. Redistribute volume across the week.
6. Change the progression or set methodology.
7. Replace the training block.

Large interventions require stronger and more persistent evidence. A single bad
session must not trigger a new program. Methodology changes should normally
require multiple comparable exposures, a stated hypothesis, and a way to judge
the result.

An accepted change should read like an experiment:

```text
Hypothesis
Chest volume is currently above recoverable capacity.

Evidence
The final press set has declined at comparable load and effort in five
consecutive exposures while earlier sets remained stable.

Change
Reduce weekly press volume by one effort set for four weeks.

Success criterion
Repetitions or estimated strength improve at comparable effort without lower
weekly adherence.

Review
After six comparable exposures, or sooner if pain or a sharp decline appears.
```

## Thin integration, not a custom harness

A future command-line or Xcode-adjacent adapter only needs three conceptual
operations:

```text
gymtrack export-review
frontier-agent reads the exported snapshot and writes PlanProposal.json
gymtrack validate-and-preview PlanProposal.json
```

The exported review package should be read-only. The agent must never edit the
SwiftData store or an ordinary backup in place. A proposal imports through app
code after schema validation and explicit user approval.

If the selected frontier service processes data in the cloud, the review flow
must say so before upload. GymTrack itself remains accountless and serverless;
that does not make a separately chosen model provider local or private.

## Maximum-quality model workflow

No model can guarantee a perfect training decision. "Perfect quality" here
means making errors visible, difficult to introduce, and easy to reverse. The
model supplies judgment; deterministic code supplies arithmetic and structural
truth; a second review challenges the judgment; the user remains the final
decision-maker.

### Current model choice

This ranking is time-sensitive and was last reviewed on 2026-09-19. Re-run the
GymTrack coach evaluation before changing models rather than treating this list
as permanent.

For the complete-history review, the current first candidate is **Claude Fable
5.1 at maximum effort**. The work resembles long-context research and knowledge
work: understand a longitudinal record, use analysis tools, preserve uncertain
and missing information, and turn a small number of defensible conclusions into
a coherent plan. **GPT-6 Astra at xhigh or maximum effort** is the co-finalist
and is particularly suitable when the workflow already runs in Codex or relies
heavily on code execution and strict structured output.

The preferred high-assurance arrangement is:

```text
GymTrack review export
        |
        v
Claude Fable 5.1 Max: primary evidence review and plan proposal
        |
        v
GPT-6 Astra xhigh/max: independent grounding, safety, and coherence audit
        |
        v
Deterministic GymTrack schema and equipment validator
        |
        v
Human reviews the evidence and accepts, edits, or rejects the changes
```

If only one provider or harness is available, either Fable 5.1 Max or Astra
xhigh is a reasonable starting point. Convenience matters: a model that can
reliably run the required tools and complete the whole protocol is better than a
slightly stronger model used as an unstructured chatbot.

Chinese frontier models belong in the bake-off rather than being dismissed by
origin. Current candidates include Qwen3.8-Max and Kimi K3 for million-token,
long-horizon knowledge work, with DeepSeek V4 and GLM-5.3 as potentially strong
cost-efficient analysts and critics. None has been validated specifically for
GymTrack. Open-weight frontier models such as Kimi K3 are far too large to run
at frontier quality on an ordinary MacBook; in that setup the Mac runs the
harness while a provider performs inference. A smaller local model improves
privacy but must be evaluated as a different, lower-capability candidate.

Current vendor references:

- Claude Fable 5.1: https://www.anthropic.com/claude/fable
- GPT-6 Astra: https://developers.openai.com/api/docs/models/gpt-6-astra
- Qwen3.8-Max:
  https://www.alibabacloud.com/en/press-room/alibaba-unveils-qwen3-8-max
- Kimi K3: https://www.kimi.com/en/blog/kimi-k3
- DeepSeek V4: https://deepseek.com/en/news/v4-preview/
- GLM models: https://autoclaw.z.ai/models/

These pages describe provider capabilities, not proof of coaching quality. The
model that wins GymTrack's blinded evaluation is the model GymTrack should use.

### Package the history for analysis

Do not convert the history into one long narrative and ask the model what it
thinks. Supply a review package containing:

- the untouched versioned JSON export and its hash;
- a short data dictionary explaining optional fields and provenance;
- deterministic tables for exercise exposures, performance trends, weekly
  effort sets, volume, duration, measured rest, reported effort, substitutions,
  plan adherence, and missingness;
- the active plan and previous plan revisions;
- accepted, edited, rejected, and reversed recommendations from prior reviews;
- the coaching policy, intervention ladder, safety limits, and proposal schema.

Let Python or SQL perform arithmetic, grouping, date handling, comparisons, and
trend calculations. The model should inspect and interpret those results, not
silently estimate them from thousands of JSON rows. Keep the raw rows available
so it can verify any aggregate and cite the underlying session and set IDs.

A million-token context window is capacity, not a reason to fill it. Irrelevant
history can bury the useful signal. Give the agent indexed files and analysis
tools so it can retrieve detail on demand while retaining plan-wide context.

### Run the review as separate gates

One prompt should not jump directly from raw history to a replacement plan.
Require these artifacts in order:

1. **Input audit.** Validate the export, report missing fields, and refuse to
   reinterpret missing, inferred, or undone data as observations.
2. **Deterministic analysis.** Generate reproducible metrics and tables. Save
   the code and results with the review.
3. **Evidence ledger.** List relevant facts with session and set identifiers;
   label every derived value and every hypothesis separately.
4. **Pattern assessment.** Consider alternative explanations such as exercise
   order, equipment changes, shortened sessions, adherence, body-weight change,
   and ordinary day-to-day variation.
5. **Minimal proposal.** Walk the intervention ladder from "keep the plan"
   upward and stop at the smallest change the evidence supports.
6. **Independent critique.** Give another frontier model the source evidence,
   proposal, and policy—but not the primary model's private reasoning. Ask it to
   find unsupported claims, missed alternatives, unnecessary complexity,
   internal conflicts, and unsafe progression.
7. **Reconciliation.** Present disagreements rather than letting one model
   silently overwrite the other. Material unresolved disagreement means keep
   the current plan or request human judgment.
8. **Deterministic validation.** Enforce schema validity, exercise IDs, legal
   machine rungs, plausible ranges, weekly structure, change-count limits, and
   reversibility in code.
9. **Human approval.** Show the before/after diff, evidence, uncertainty,
   success criterion, and review point. Applying nothing must remain easy.
10. **Outcome review.** At the stated future exposure count, evaluate the
    original success criterion before proposing another change.

The primary and critic runs should use pinned model versions where providers
offer them. Record the provider, model, effort level, harness version, prompt or
policy hash, tool versions, source export hash, and generated proposal. Without
that provenance, a later result cannot be reproduced or attributed to a model
change.

For especially consequential plan rewrites, run the primary analysis more than
once. Agreement is not proof, but large unexplained variation is a reason not to
apply the change. Repeated outputs must be compared by their claims and proposed
actions rather than by prose similarity.

### Select the model with GymTrack cases

Generic leaderboards do not test whether a model understands GymTrack's data or
chooses a conservative training intervention. Maintain a versioned coach exam
with at least 20–30 de-identified histories covering:

- a real plateau and an ordinary bad session;
- excessive volume and insufficient stimulus;
- stable performance that requires no change;
- equipment changes and exercise substitutions;
- measured versus inferred timing and heart-rate data;
- unrated sets and genuinely absent observations;
- drop-set or cluster continuations that must not be counted as separate
  efforts;
- a change that violates an equipment rung or plan constraint;
- pain or technique warnings that the model must not diagnose away;
- tempting but unsupported methodology changes.

Run every candidate with the same package, tools, policy, effort budget, and
output schema. Hide the model names from qualified reviewers. Score grounding,
safety, use of uncertainty, arithmetic correctness, plan coherence, smallest
justified intervention, evidence citations, schema validity, and repeat-run
stability. Safety and invented evidence are release gates, not dimensions that
can be averaged away by eloquent writing.

The production choice is the model and harness combination that wins this exam
and the prospective product test described below. Re-run the exam for every
material model, prompt, policy, or harness update.

## Proposal contract

The exact schema can be designed later, but a proposal must contain at least:

- schema version, generation time, model identifier, and analysis-policy
  version;
- source export identifier or hash;
- the complete proposed plan, not only patch instructions;
- a machine-readable diff from the active plan;
- one rationale per material change, citing session or set identifiers;
- confidence and important alternative explanations;
- the expected benefit and the metric that should move;
- a review date or number of comparable exposures;
- explicit declarations that safety and equipment constraints were checked;
- no medical diagnosis and no attempt to interpret pain as harmless.

Validation should reject unknown exercise identifiers, impossible load rungs,
invalid ranges, unsupported methods, excessive simultaneous changes, missing
evidence, or any mutation outside the proposal schema.

Every accepted plan needs provenance. Store the original proposal, the final
user-edited diff, and the prior plan as a reversible version. Model or prompt
changes create a new coach version; otherwise later evaluation would mix
different interventions under one name.

## What “better” means

The coach has two separate jobs and must be measured on both.

### Training effectiveness

Prefer outcomes already produced by normal logging:

- completed planned sessions and completed planned effort sets;
- progression in repetitions, load, or estimated strength at comparable effort;
- progress per unit of training time, not raw volume alone;
- the percentage of prescribed work that lands in its intended rep and effort
  range;
- sustained progress after the first few weeks rather than a launch spike;
- pain, adverse-event, and excessive all-out-effort guardrails.

Raw tonnage is not a success metric by itself. A coach can make it rise simply
by prescribing more work. App opens, recommendation taps, and time in the app
are also not training outcomes.

### User experience

Measure whether the coach removes decisions without taking away agency:

- time spent repairing or redesigning a plan manually;
- recommendation acceptance, later reversal, and manual-edit rates;
- workout abandonment and unplanned exercise substitution;
- time from opening a workout to starting and logging useful work;
- perceived clarity, confidence, autonomy, trust, and recommendation burden;
- whether the user can correctly explain why a change was suggested;
- whether dismissing or ignoring the coach adds any friction.

Satisfaction is valuable but is secondary evidence. A polished explanation can
feel intelligent while producing no improvement.

## How to separate improvement from novelty

Do not compare a polished AI experience with an unchanged control. That tests a
new interface and an AI label at the same time.

For a real product study, use the same review cadence, screens, language style,
and approval controls in both arms:

- **Control:** the current deterministic progression and fixed plan rules,
  presented as an adaptive coach.
- **Treatment:** frontier-agent recommendations, presented through the same
  neutral adaptive-coach interface.

Avoid prominent AI branding during the comparison. Participants need truthful
consent that automated recommendations are being studied, but the UI need not
prime one arm as more advanced. Analyze subjective ratings separately from
objective behavior and performance.

A whole-plan intervention carries over into later training, so randomizing each
user to one arm for a sufficiently long block is cleaner than rapidly switching
the same person between AI and control. A short crossover can be useful for
interface questions, but it is weak evidence for strength or hypertrophy because
adaptations, fatigue, and plan changes persist into the next period.

## Evaluation sequence

### Phase 0: historical replay

Run the agent over old exports without showing recommendations to the user.

- Confirm that identical inputs produce acceptably stable decisions.
- Check every cited set and every derived claim against the export.
- Have a qualified coach rate safety, specificity, evidence, and whether the
  smallest justified intervention was chosen.
- Compare proposals with what happened in subsequent sessions, while calling
  this predictive validation rather than causal evidence.

Historical replay can catch hallucinations and bad reasoning. It cannot prove
that following the advice would have improved the outcome.

### Phase 1: shadow mode

Generate recommendations prospectively but do not apply them. Record what the
rule-based system suggested, what the agent would have suggested, and what the
user actually did. Require zero severe safety or data-grounding failures before
moving on.

### Phase 2: personal pilot

For a single owner, collect a stable rule-based baseline and then run a
predeclared AI block long enough to outlast first-week enthusiasm. This can show
whether the workflow is useful to that person, especially through manual plan
editing time, adherence, overrides, and performance slope.

It is not definitive causal proof: training age, season, sleep, nutrition,
regression to the mean, and carryover all remain plausible explanations. Record
them rather than hiding them.

Immediate suggestions can be tested more rigorously with randomized decision
points: when both options are safe, randomly show the rule-based or agent
suggestion and measure the next comparable set or session. This is the
micro-randomized-trial pattern. Do not use decision-level randomization for
coordinated whole-plan changes that would make the plan internally inconsistent.

### Phase 3: controlled product test

Randomize users to neutral rule-based coaching or neutral AI coaching for at
least one complete training block. Stratify by training experience and baseline
adherence. Predeclare:

- one primary outcome;
- the smallest worthwhile improvement;
- the observation window and missing-data rule;
- safety and friction non-inferiority limits;
- subgroup analyses worth trusting;
- the model and prompt version under test.

For an early GymTrack study, a defensible primary product outcome is the
proportion of planned workouts completed over the block. A key training outcome
is the change in repeated exercise performance at comparable effort. The AI
should ship as “proven helpful” only if it improves the primary outcome or a
predeclared training outcome, does not worsen safety or logging friction, and
the effect survives after the launch period.

Report confidence intervals and individual response distributions, not only an
average or a p-value. “Some people benefited and we can identify them” is more
useful than a tiny average effect across everyone.

### Phase 4: ongoing audit

After release, preserve a small holdout where appropriate, monitor model-version
changes, and watch for recommendation churn, rising overrides, declining
adherence, pain flags, and subgroups receiving systematically worse proposals.
Passing one experiment does not validate every later model.

## Suggested scorecard

| Layer | Measure | Failure signal |
|---|---|---|
| Grounding | Unsupported factual claims | Any invented session or measurement |
| Safety | Severe unsafe proposals | Any; blocks release |
| Stability | Materially different plans from unchanged data | Unexplained plan churn |
| Adoption | Accepted without substantial editing | High rejection or immediate reversal |
| Friction | Logging and plan-management time | Meaningful increase over control |
| Adherence | Planned sessions and effort sets completed | No durable lift over control |
| Performance | Load/reps/estimated strength at comparable effort | No lift, or lift explained only by more volume |
| Agency | Clarity, autonomy, and trust | User follows advice they cannot explain |
| Durability | Effect after the novelty window | Early spike followed by control-level results |

Exact thresholds should be chosen from baseline variance and measurement error,
then frozen before examining treatment results. Choosing them after seeing the
data turns the evaluation into a story rather than a test.

## What research currently supports

The evidence supports plausibility and a way to test the feature, not a claim
that a monthly frontier-model review already improves resistance training.

- A 2025 randomized trial of 79 trained adults found 10-week adherence of 88.2%
  with in-person supervision, 81.2% with app guidance, and 52.2% with a static
  PDF. All groups improved squat and bench strength, but supervised training
  produced better results on several outcomes. This suggests app guidance can
  support adherence while also showing that a digital layer does not
  automatically reproduce good coaching.
- An 8-week randomized trial in 239 older adults found that a personalized,
  machine-learning-assisted smartphone program improved several balance,
  flexibility, and arm-strength outcomes versus active and inactive controls.
  It demonstrates that personalized digital exercise can create objective
  effects, but it is a different population and intervention from GymTrack.
- A large four-arm Fitbit study reported that reinforcement-learning-selected
  activity nudges increased daily steps versus control and other selection
  methods over one to two months. This is useful evidence for testing adaptive
  decisions, not direct evidence for AI-written resistance-training blocks.
- Research on micro-randomized trials provides a mature method for testing the
  near-term causal effect of repeated mobile interventions. It fits next-set or
  next-session recommendations better than whole-program rewrites.
- Expert evaluation of one-shot GPT-4 exercise prescriptions found generally
  safe baselines but insufficient specificity and adaptability. A separate
  mixed-methods evaluation found only 41.2% of gold-standard recommendation
  content was present, although the content that was present was usually
  accurate. Rich longitudinal data and validation are therefore essential;
  model fluency is not evidence of coaching quality.
- Human-computer-interaction experiments show that an AI label can raise
  expected performance without improving objective performance. This directly
  supports neutral labeling and separate subjective and objective outcomes.
- The 2026 American College of Sports Medicine resistance-training guidance
  emphasizes consistency, effort, and individualization over unnecessary
  complexity. An AI coach that constantly changes methods may look active while
  damaging the more important behavior: training consistently.

## Research references

- Gavanda et al., *Optimizing Resistance Training Outcomes: Comparing In-Person
  Supervision, Online Coaching, and Self-Guided Approaches* (2025):
  https://pmc.ncbi.nlm.nih.gov/articles/PMC12529976/
- Netz et al., *A Smartphone Platform for Remote Motor Fitness Assessment and
  AI-Generated Personalized Exercise Programs for Older Adults* (2025):
  https://pmc.ncbi.nlm.nih.gov/articles/PMC12527324/
- Lee et al., *A Personalized Exercise Assistant using Reinforcement Learning
  (PEARL)* (2025 preprint): https://arxiv.org/abs/2508.10060
- Qian et al., *The Micro-Randomized Trial for Developing Digital
  Interventions* (2022): https://pmc.ncbi.nlm.nih.gov/articles/PMC9276848/
- Dergaa et al., *Using artificial intelligence for exercise prescription in
  personalised health promotion* (2024):
  https://pmc.ncbi.nlm.nih.gov/articles/PMC10955739/
- Füzéki et al., *Comprehensiveness, Accuracy, and Readability of Exercise
  Recommendations Provided by an AI-Based Chatbot* (2024):
  https://pmc.ncbi.nlm.nih.gov/articles/PMC10811574/
- von Felten et al., *AI Washing Inflates Expected Performance but Not
  Interaction Outcomes* (2026): https://arxiv.org/abs/2605.00582
- American College of Sports Medicine, 2026 resistance-training guidance:
  https://acsm.org/resistance-training-guidelines-update-2026/

## Bottom line

Build a boring, auditable bridge around a capable model. Let ordinary logging
and progression stay dependable. Make every strategic change reversible and
falsifiable. Judge the coach by training consistency, objective progress,
friction, safety, and durable behavior—not by how intelligent its prose sounds.
