# Setup prompt: phone → PR pipeline + test suite (any stack)

Paste everything below the line into Claude Code at the root of the repo you want to set up. It is the
stack-agnostic version of the prompt that built GymTrack's pipeline. The working template is
https://github.com/MarwanMoh11/Gymtrack, and its reference document is
[`docs/claude-pipeline.md`](https://github.com/MarwanMoh11/Gymtrack/blob/main/docs/claude-pipeline.md).

---

# Phone → PR pipeline + test suite

You're at the root of one of my repos. Set up everything below from start to finish. Work on your
own and stop only at the single ⏸ checkpoint. Track the phases in your task list.

The template is https://github.com/MarwanMoh11/Gymtrack. Read its `docs/claude-pipeline.md`,
`.github/workflows/claude.yml`, `.github/workflows/pr-check.yml` and `scripts/claude-pipeline/`
(fetch them with `gh api repos/MarwanMoh11/Gymtrack/contents/<path>`) before Phase 5, and copy
them rather than writing them from scratch.

## What we're building

1. **Issue → PR from my phone.** I open a GitHub issue with `@claude` in it. The Claude Code GitHub
   Action (in the cloud, on Opus) implements it on a branch, adds tests, and opens a PR that closes
   the issue.
2. **Every PR gets checked automatically:**
   - a **build-and-test** check that must pass before merging;
   - a **Claude review** comment (Opus) with a verdict, risk level, test status and what I should
     test by hand.
3. **One-tap merging.** I read the review on my phone and tap Squash and merge. Several PRs can be
   merged one after another without update or rebase friction.
4. **A solid test suite**, built now and expanded by every future PR.
5. **Reference documentation in the repo**, so this repo can be a template too.

**Decisions already made. Don't ask about these again:**
- Both cloud workflows use the current Opus model at `xhigh` effort (`CLAUDE_CODE_EFFORT_LEVEL: xhigh`
  on the action step). Look up the model's exact ID before using it.
- Auth uses my **Claude subscription token**.
- Merges are **squash only**.
- If the build needs macOS (Xcode), the repo should be **public** so GitHub's macOS minutes are
  free. If it's private, tell me the minute cost in Phase 1 before going on.

## Ground rules

- Never ask me to paste a token or secret into this chat, and never print one. Secrets go straight
  from my terminal into `gh secret set`.
- Don't change signing settings, app or bundle IDs, credentials or deployment configuration.
- Keep app-code changes small and behavior-preserving. List every one of them in the final report.
- If something in this prompt doesn't fit this repo, adapt it and tell me what you changed. Don't
  force it.
- If you aren't allowed to change repo settings yourself, write the script and give me the command
  to run. Don't look for a way around the block.

## Phase 1: Recon (no changes)

Report in 10 lines or fewer:
- Git state: remotes, default branch, whether a GitHub repo exists and its visibility.
- The stack: languages, frameworks and package managers. The exact **build command** and **test
  command**, and whether they need macOS, a simulator, a browser or a service.
- Existing tests: frameworks, where they live, how they run, how long a full run takes, and
  whether CI exists already.
- How new source files get into the build (e.g. Xcode synchronized folders, a manifest, globbing).
- Tooling: the toolchain versions, and whether `gh` is installed and authenticated.
- The app itself: main features, how it stores data, and its external dependencies.

## Phase 2: Make it safe to go public (skip the visibility part if it stays private)

1. Add or fix a `.gitignore` for the stack (build output, dependency folders, IDE state, `.env`).
2. Scan the **entire git history** for secrets: run `brew install gitleaks`, then
   `gitleaks detect --source . --log-opts="--all"`. Also check by hand for `.env` files, key files
   (`*.pem`, `*.p8`, `*.p12`, `*.key`), service config files, and keys hard-coded in source.
3. **If you find anything real, stop and show me** the file, the commit and the kind of secret.
   Rotating keys or rewriting history is my decision.
4. If it's clean: create the repo if needed (`gh repo create <name> --public --source=. --push`) or
   change its visibility, and make sure the default branch is `main`.

## ⏸ Checkpoint: my manual steps

Give me one short checklist, then wait until I say "done":

1. Install the Claude GitHub App on this repo: https://github.com/apps/claude
2. In **Terminal.app** (not an embedded terminal pane: the sign-in needs a code pasted back), run
   `claude setup-token`. If `claude` isn't on my PATH, find the CLI bundled with the Claude desktop
   app and give me its full path. Then run `gh secret set CLAUDE_CODE_OAUTH_TOKEN --repo <owner/repo>`
   and paste the token at its hidden prompt.
3. **Only if the project needs IDE-managed test targets** (e.g. Xcode), give me exact click-by-click
   steps to add them: unit tests (prefer the modern framework, e.g. Swift Testing) and UI or
   end-to-end tests. Include setting each target's minimum OS to match the app. Don't hand-edit
   project files to add targets.

Also list any deviations from this prompt you plan to make, so I can object when I say "done".

After I say "done":
- Confirm the secret exists with `gh secret list` (names only).
- Confirm the test setup builds (e.g. `xcodebuild build-for-testing`, `npm test -- --listTests`).

## Phase 3: Build a very solid test suite, using subagents

1. **Plan.** Spawn a read-only subagent to map the codebase and propose a test plan split into 4–6
   independent areas, such as domain logic and calculations, persistence, state and view-model
   logic, sync or networking, and critical UI or end-to-end flows. For each area it lists:
   - the behaviors that matter and the edge cases;
   - the test files it will own;
   - which code needs a seam (a protocol and a fake, or an injected clock or store) to be testable;
   - hazards when the app runs as a test host: real databases, permission prompts, network calls,
     singletons.
   It also lists any existing tests, so the new suite fills gaps instead of duplicating them.
2. **Prepare for testing.** Do the testability refactors yourself, before tests are written:
   - extract logic out of views and controllers;
   - put system frameworks and I/O behind small seams;
   - make a test host use an in-memory store and skip prompts;
   - add stable test IDs for UI tests.
   Keep these minimal and behavior-preserving, and put them in their own commit. Add shared test
   helpers (an in-memory store and a fixed clock) in the same commit.
3. **Write tests in parallel.** Spawn one subagent per area, each in its own git worktree, each
   owning its own files. Give every subagent a shared brief file with:
   - a hard context and tool-call budget;
   - its exact owned files;
   - a lock for heavy jobs: wrap every build or test run in `lockf -k <lockfile> <command>` so only
     one runs at a time;
   - these rules:
     - Test behavior through public interfaces, not implementation details.
     - Use parameterized tests for edge cases.
     - No sleeps. Use deterministic clocks and dates, and in-memory stores.
     - Cover the unhappy paths: empty data, boundary values, invalid input, unit conversions, dates
       across midnight and time zones, and network or sync failures.
     - If a test exposes a real bug, keep the test, mark it as a known issue (`withKnownIssue`,
       `test.fails`, `xfail`), and report the bug. Never weaken an assertion to make a test pass.
4. **Integrate and run.** Merge the subagents' branches, run the full suite until it's green, then
   run it a second time to catch flaky tests.
5. **Audit test quality.** Spawn a **fresh** subagent that wrote none of the tests. It picks 5
   important functions and, one at a time, introduces a deliberate bug, confirms that at least one
   test fails, and reverts the bug. Fill any gaps it finds.
6. **Track bugs.** For each real bug found, open a GitHub issue with no `@claude` in it, so I can
   trigger the fix later from my phone.

## Phase 4: CLAUDE.md

Write a concise `CLAUDE.md` at the repo root, 60 lines or fewer, because cloud runs read it on
every run. If one already exists and is longer, keep its rules and move long-form local-only notes
into `docs/DEVELOPMENT.md`. Include:
- what the app is;
- a folder map;
- the architecture and the test seams;
- code style;
- how new files get into the build;
- **test conventions**: every behavior change adds or updates tests in the matching test file,
  following the Phase 3 patterns;
- how a cloud run checks its work: the checker command (see Phase 5), or that CI does;
- a rule: any change to the pipeline (workflows, scripts, repo settings, ruleset) must update
  `docs/claude-pipeline.md` in the same PR.

## Phase 5: Workflows

Copy the template's `claude.yml`, `pr-check.yml`, `claude-retry.yml` and `claude-check-notice.yml`, its issue forms in `.github/ISSUE_TEMPLATE/`
(Bug report and Feature request, whose last question adds `@claude` only on "Yes", or asks for a
plan first) and `.github/claude-planning.md` (how a run splits a big issue into sub-issues, on
request or, with the repository variable `CLAUDE_AUTO_SPLIT=true`, on its own), and
`.github/claude-test-checklist.md` (the **Test before you merge** section every PR ends with;
rewrite its "About the owner" part for me and this app). Keep the workflows' structure and action
inputs; on a macOS runner, Claude opens its PR with `gh`, since the action's create-PR tool needs
Docker. Copy `scripts/claude-pipeline/save-work.sh`, `wait-for-reset.sh` and `check-notice.sh` unchanged:
with the workflows they save a run's unfinished work to a `claude/rescue-*` branch for the next run
to carry on from, give `@claude stop` / `@claude continue`, wait out a usage limit on Linux before
re-running, and comment on Claude's PR when a check fails there. `claude.yml` also lets a run merge `main` into its PR (`@claude fix the conflicts`).
Keep `run-name` quoted: those features find runs by it. Then:
- Check the current major versions of `actions/checkout`, `actions/upload-artifact` and
  `anthropics/claude-code-action` (`gh api repos/<owner>/<repo>/releases/latest`), and check the
  Opus model ID.
- Replace the `build-and-test` steps with this stack's build and test commands. Keep the job name
  `build-and-test`. Resolve devices or versions at runtime rather than hard-coding them. If UI or
  end-to-end tests push the job past about 15 minutes, move them to a separate job that isn't
  required.
- If building needs a particular OS or toolchain (Xcode needs macOS), run `claude.yml` on a runner
  that has it and give Claude one checker command, like the template's
  `scripts/claude-pipeline/check.sh`, that builds and runs named suites and prints only errors.
  Copy it, and `save-work.sh`, outside the checkout before Claude starts, and allow only the
  checker's path. Reword the checker sentence in the system prompt for this stack, and keep the
  model `wait-for-reset.sh` asks the same as `--model`. On a private repo, tell me what the extra
  runner minutes cost first.
- Rewrite the review prompt's description of the app.
- Validate the four workflows with `actionlint` (`brew install actionlint`), and the scripts with
  `shellcheck`.

## Phase 6: Repo settings

Copy the template's `scripts/claude-pipeline/apply-repo-settings.sh` and `ruleset-main.json`, and run
the script with this repo and the exact required check name. It sets:
- **Merging:** squash only; delete head branches after merge; allow auto-merge; always suggest
  updating PR branches.
- **Actions:** default `GITHUB_TOKEN` permissions read-only; approval required for workflow runs
  from all outside collaborators.
- **A ruleset on `main`:** require `build-and-test`; don't require branches to be up to date;
  block force-pushes and deletion; let admins bypass, so I can still push to `main`.

On a private repo, rulesets need GitHub Pro or Team. Say so if the call fails.

## Phase 7: Document the pipeline

Write `docs/claude-pipeline.md` using the template's document as the model. Link to the real files
rather than copying them, explain every non-obvious line, and describe what was **actually** built,
including every deviation from this prompt. Keep the template's sections:
1. Overview with a Mermaid flowchart
2. Daily use from a phone: a good issue, timings, verdicts, merging, follow-up commands
3. How it's implemented: one row per component, generic or repo-specific
4. Design decisions and why
5. Security model
6. Costs and limits
7. Troubleshooting
8. Porting to another repo

Also add a short **Development workflow** section to `README.md` that links to it.

## Phase 8: Verify end to end

1. Push the four workflow files to `main` first. The review job refuses to run from a workflow
   file that differs from the default branch's copy, so a PR that adds them can never review
   itself, and comment- and `workflow_run`-triggered workflows only run from the default branch.
2. Put the rest of the work from Phases 3–7 on a branch named `setup/claude-pipeline` and open a PR.
3. Watch the PR:
   - `build-and-test` must pass;
   - the Claude review comment must appear in the right format.
   Fix anything that fails. A fix to `pr-check.yml` has to go to `main` as well.
4. Update `docs/claude-pipeline.md` with what you learned: the real check name, fixes, and timings
   observed. Do this before merging.
5. Squash-merge the PR.
6. Don't open a test issue. I'll do that from my phone.

## Final report (keep it short)

- What's set up, plus any deviations from this prompt.
- Links to `docs/claude-pipeline.md` on GitHub.
- Tests: the count per area, and what the bug-injection audit showed.
- Every app-code change you made.
- Bugs found, with issue links.
- Anything I still need to do by hand.
- One example issue I can paste into the GitHub app for my first phone test.
