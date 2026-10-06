# Planning an issue into sub-issues

Read by a Claude run (`.github/workflows/claude.yml`) when an issue or comment asks it to plan, or
when the repository variable `CLAUDE_AUTO_SPLIT` is `true` and the issue is too big for one pull
request you would be confident in. Why it works this way is in `docs/claude-pipeline.md`.

Planning replaces implementing: change no code, make no commits, open no pull request.

1. Read the issue, its comments and the code it touches, enough to know what each piece involves.
   Check for parts that already exist (`gh api repos/<owner>/<repo>/issues/<parent>/sub_issues`)
   and plan around them rather than repeating one.
2. Split it into the fewest pieces that each:
   - change one behavior, and can be built, tested and merged on their own;
   - leave the app working and every data rule in `CLAUDE.md` intact once merged;
   - depend only on pieces before them.

   Usually 2 to 6. If the issue already fits one pull request, say so in your comment and create
   nothing; the owner can then ask you to implement it.
3. For each piece, write its body to `build/plan/<n>.md` and create it:
   `gh issue create --title "Part <n> of <N>: <short title>" --label enhancement --body-file build/plan/<n>.md`.
   The number leads the title so the order shows in an issue list on a phone. The body has the feature form's sections, in this order: **Part n of N of #parent**, **What
   should change**, **What must not change** (carry the parent's over), **Done when**, and
   **Depends on** (issue numbers, or "nothing").
4. Link each one under the parent, in order. `gh api repos/<owner>/<repo>/issues/<n> --jq .id`
   gives its id, then
   `gh api repos/<owner>/<repo>/issues/<parent>/sub_issues -X POST -F sub_issue_id=<id>`.
5. Finish with a short comment: the parts in order with their numbers, a line on why the split
   falls where it does, and which part to start first.

Never write the mention that starts a run (an at sign followed by claude) in an issue or comment
you create. Each part waits until the owner starts it; a run started by you would be refused anyway.
