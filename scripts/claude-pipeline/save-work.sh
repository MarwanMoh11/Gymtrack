#!/bin/sh
# Runs after every Claude run, however it ended, so that nothing the run did is
# lost. A run that fails, is stopped, times out or has its push refused would
# otherwise take its work with the runner when it shuts down: the first run on
# #7 lost 54 minutes that way.
#
# It commits what Claude left uncommitted (unless the run finished, when the
# leftovers are scratch), pushes whatever isn't on GitHub yet to
# claude/rescue-<issue>-<run>-<attempt>, and says on the issue what happened.
# The next run on the issue merges that branch and carries on (claude.yml). If
# the run stopped on the subscription's usage limit, it leaves a note for
# claude-retry.yml, which waits for the reset and runs it again.
#
# Like the checker, it runs as a copy taken before Claude started, and git runs
# with hooks and credential helpers off: Claude may have planted either in the
# checkout, and this step holds the workflow's token.
#
# Env: GH_TOKEN (the workflow token), REPO, NUMBER, RUN_ID, RUN_ATTEMPT, RUN_URL,
# OUTCOME (the Claude step's outcome) and EXECUTION_FILE.

set -u
cd "$GITHUB_WORKSPACE" || exit 0

git_() {
    git -c core.hooksPath=/dev/null -c core.fsmonitor=false -c credential.helper= \
        -c user.name="github-actions[bot]" \
        -c user.email="41898282+github-actions[bot]@users.noreply.github.com" "$@"
}
remote="https://x-access-token:$GH_TOKEN@github.com/$REPO.git"

# Only the run's final message says whether it stopped on the usage limit. The
# rest of the file holds every file Claude read, and this repo's docs talk about
# usage limits.
limit=""
if [ -s "${EXECUTION_FILE:-}" ]; then
    final=$(jq -r '[.[] | select(.type == "result")] | last | select(.is_error == true) | .result // empty' \
        "$EXECUTION_FILE" 2>/dev/null)
    if printf '%s' "$final" | grep -qiE 'limit reached|hit your .*limit|usage limit|rate.?limit'; then
        limit=$(printf '%s' "$final" | tr '\n' ' ' | cut -c1-300)
    fi
fi

if [ "$OUTCOME" != success ]; then
    git_ add -A
    git_ diff --cached --quiet || git_ commit -q -m "Unfinished work from Claude's run $RUN_ID"
fi

# Without a fresh view of GitHub, the push below happens anyway: a spare branch
# costs nothing, lost work does.
git_ fetch -q "$remote" '+refs/heads/*:refs/remotes/origin/*'
saved=""
if [ -z "$(git_ branch -r --contains HEAD)" ]; then
    branch="claude/rescue-$NUMBER-$RUN_ID-$RUN_ATTEMPT"
    # main first: a new branch from before a workflow change on main looks as if
    # it changes that workflow, which GitHub refuses from an app's token.
    git_ merge -q --no-edit origin/main > /dev/null 2>&1 || git_ merge --abort 2> /dev/null
    if git_ push -q "$remote" "HEAD:refs/heads/$branch"; then
        saved=$branch
    else
        # The last resort: the work as a git bundle among the run's artifacts.
        git_ bundle create "$RUNNER_TEMP/unsaved-work.bundle" HEAD ^origin/main > /dev/null 2>&1
        echo "bundle=$RUNNER_TEMP/unsaved-work.bundle" >> "$GITHUB_OUTPUT"
        saved=bundle
    fi
fi

# A finished run deletes the rescue branches it carried on from, once its own
# branch holds them. Never one that is the only copy of the work.
if [ "$OUTCOME" = success ] && [ -z "$saved" ] &&
    git_ branch -r --contains HEAD | grep -qv 'origin/claude/rescue-'; then
    git_ for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/origin/claude/rescue-$NUMBER-*" |
        while read -r old; do
            if git_ merge-base --is-ancestor "origin/$old" HEAD; then
                git_ push -q "$remote" --delete "$old"
            fi
        done
fi

case $saved in
    "") where="Everything it did is already on GitHub." ;;
    bundle) where="GitHub refused a branch for its work, so the work is in the run's artifacts as unsaved-work: $RUN_URL" ;;
    *) where="Its work so far is saved on \`$saved\`." ;;
esac

if [ -n "$limit" ]; then
    mkdir -p "$RUNNER_TEMP/usage-limit"
    echo "$NUMBER" > "$RUNNER_TEMP/usage-limit/number"
    echo "limited=true" >> "$GITHUB_OUTPUT"
    body="Claude hit the usage limit (\"$limit\"). $where It starts again by itself once the limit has reset, checking every 20 minutes. Comment \`@claude stop\` to cancel that."
elif [ "$OUTCOME" = cancelled ]; then
    body="Claude was stopped. $where Comment \`@claude continue\` to pick it up."
elif [ "$OUTCOME" != success ]; then
    body="Claude's run stopped before it finished ($RUN_URL). $where Comment \`@claude continue\` to pick it up."
elif [ -n "$saved" ]; then
    body="Claude finished, but its work wasn't on GitHub. $where Comment \`@claude continue\` to open the pull request from it."
else
    exit 0
fi
gh api "repos/$REPO/issues/$NUMBER/comments" -f body="$body" > /dev/null
