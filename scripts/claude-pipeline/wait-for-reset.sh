#!/bin/sh
# Waits for the Claude subscription's usage limit to reset, then re-runs the
# Claude run that stopped on it. Started by claude-retry.yml on a Linux runner,
# which costs far less to keep waiting than a Mac and doesn't hold one of the
# five a free account may run at once.
#
# The reset time isn't read from the limit's message: its wording changes
# ("5-hour limit reached - resets 3pm", "You've hit your weekly limit - resets
# Jul 25, 9pm (America/New_York)"). Instead it asks Claude for one word every 20
# minutes, which the limit refuses at no cost, and re-runs on the first answer.
# The re-run merges the work the stopped run saved (save-work.sh).
#
# Env: GH_TOKEN (the workflow token), CLAUDE_CODE_OAUTH_TOKEN, REPO, RUN_ID,
# ATTEMPT, TITLE, and SINCE (when the wait began, empty on the first leg).

set -u

# Only a run that stopped on the limit leaves this note; any other failure is
# for the owner to look at.
dir=$RUNNER_TEMP/usage-limit
if ! gh run download "$RUN_ID" -R "$REPO" -n "claude-usage-limit-$ATTEMPT" -D "$dir" 2> /dev/null; then
    echo "Run $RUN_ID (attempt $ATTEMPT) didn't stop on the usage limit"
    exit 0
fi
number=$(tr -cd 0-9 < "$dir/number")

comment() {
    gh api "repos/$REPO/issues/$number/comments" -f body="$1" > /dev/null
}

# A run the limit keeps stopping may be failing for another reason that reads
# like a limit; don't loop on it forever.
if [ "$ATTEMPT" -ge 6 ]; then
    comment "Claude's run stopped on the usage limit $ATTEMPT times, so it isn't being retried again. Comment \`@claude continue\` to start it yourself."
    exit 1
fi

since=${SINCE:-$(date +%s)}
give_up=$((since + 8 * 86400)) # a weekly limit resets within 7 days
hand_over=$(($(date +%s) + 330 * 60)) # a job may run 6 hours at most

npm install -g --silent @anthropic-ai/claude-code > /dev/null 2>&1 || exit 1
empty=$(mktemp -d)

# Asks with the run's own model, since a limit can apply to one model and not
# another, from an empty directory so the question reads no project files.
# Returns 0 once Claude answers, 1 while the limit holds, 2 for anything else
# (an expired token, say), which waiting won't fix.
ask() {
    answer=$(cd "$empty" && claude -p "Reply with the single word ready." --model claude-opus-5-5 \
        --max-turns 1 --output-format json 2>&1)
    if printf '%s' "$answer" | jq -e '.is_error == false' > /dev/null 2>&1; then
        return 0
    fi
    printf '%s' "$answer" | grep -qiE 'limit reached|hit your .*limit|usage limit|rate.?limit' && return 1
    return 2
}

odd=0
while :; do
    sleep 1200
    ask
    case $? in
        0)
            echo "The limit has reset: re-running $RUN_ID"
            gh run rerun "$RUN_ID" -R "$REPO" --failed
            exit
            ;;
        1) odd=0 ;;
        2)
            # Three in a row, so a passing network fault or overload doesn't end the wait.
            odd=$((odd + 1))
            if [ "$odd" -ge 3 ]; then
                comment "Waiting for Claude's usage limit stopped: Claude couldn't be reached for another reason (\"$(printf '%s' "$answer" | tr '\n' ' ' | cut -c1-200)\"). Comment \`@claude continue\` once that is fixed."
                exit 1
            fi
            ;;
    esac
    now=$(date +%s)
    if [ "$now" -ge "$give_up" ]; then
        comment "Claude's usage limit still hadn't reset after 8 days, so this stopped waiting. Comment \`@claude continue\` once it has."
        exit 1
    fi
    if [ "$now" -ge "$hand_over" ]; then
        gh workflow run claude-retry.yml -R "$REPO" -f run_id="$RUN_ID" -f attempt="$ATTEMPT" \
            -f title="$TITLE" -f since="$since"
        exit 0
    fi
done
