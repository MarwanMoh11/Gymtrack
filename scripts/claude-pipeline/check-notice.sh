#!/bin/sh
# Says on Claude's pull request that a check failed. Started by
# claude-check-notice.yml when PR Check fails on a claude/ branch. GitHub tells
# only whoever pushed about a failed run, and on these branches that is Claude,
# so a red check would otherwise sit unseen until someone opens the PR.
#
# It names each failed check and whether it blocks merging (the ruleset's
# required checks), quotes the failing tests from the log, and says how to get a
# fix. It never starts one itself: a check that failed by chance would send
# Claude after nothing, at the cost of a run.
#
# Env: GH_TOKEN (the workflow token), REPO, BASE (the default branch), RUN_ID,
# ATTEMPT, RUN_URL, and SHA and BRANCH (the commit and branch that were checked).

set -u

# Only the open PR whose newest commit this is: a newer push has its own run.
pr=$(gh pr list -R "$REPO" --head "$BRANCH" --state open --json number,headRefOid \
    --jq ".[] | select(.headRefOid == \"$SHA\") | .number")
if [ -z "$pr" ]; then
    echo "No open pull request has $SHA as its newest commit"
    exit 0
fi

failed=$(gh run view "$RUN_ID" -R "$REPO" --attempt "$ATTEMPT" --json jobs \
    --jq '.jobs[] | select(.conclusion == "failure" or .conclusion == "timed_out") | .name')
required=$(gh api "repos/$REPO/rules/branches/$BASE" \
    --jq '.[] | select(.type == "required_status_checks") | .parameters.required_status_checks[].context')

# The review job is Claude reading the diff (pr-check.yml). Its failing says
# nothing about the change, so it gets its own line and no request for a fix.
checks=""
fixable=""
while read -r job; do
    [ -n "$job" ] || continue
    if [ "$job" = review ]; then
        checks="$checks
- The automatic review didn't finish, so this commit has no review. That doesn't block merging."
    elif printf '%s\n' "$required" | grep -qxF "$job"; then
        fixable=yes
        checks="$checks
- \`$job\` failed. Merging waits until it passes."
    else
        fixable=yes
        checks="$checks
- \`$job\` failed. It doesn't block merging."
    fi
done << EOF
$failed
EOF
[ -n "$checks" ] || exit 0

# The checker prints only the errors and failing tests (check.sh). Anything
# else, such as a step that fails before the checker runs, gets the last lines
# of its failed step.
# Backticks go, so a line can't close the code block it is quoted in.
log=$(gh run view "$RUN_ID" -R "$REPO" --attempt "$ATTEMPT" --log-failed 2> /dev/null |
    awk -F '\t' '$1 != "review"' | cut -f 3- | sed 's/^[^ ]* //' | tr -d '\033`' |
    sed 's/\[[0-9;]*m//g' | cut -c1-250)
lines=$(printf '%s\n' "$log" | grep -E ': error: |^error: |✘ |recorded an issue|Test case .* failed|^FAILED: ' |
    awk '!seen[$0]++' | head -15)
[ -n "$lines" ] || lines=$(printf '%s\n' "$log" | grep -v '^##\[' | grep -v '^[[:space:]]*$' | tail -8)

body="**A check failed on this pull request** ([the run]($RUN_URL)).
$checks"
if [ -n "$fixable" ]; then
    [ -z "$lines" ] || body="$body

\`\`\`
$lines
\`\`\`"
    body="$body

If the failure is in something this pull request doesn't touch, it may have failed by chance: open the run and re-run its failed jobs. Otherwise reply \`@claude fix the build\`, and Claude reads the log and pushes a fix."
else
    body="$body

To get a review, open the run and re-run its failed jobs."
fi
gh api "repos/$REPO/issues/$pr/comments" -f body="$body" > /dev/null
