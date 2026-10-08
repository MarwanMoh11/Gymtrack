#!/bin/sh
# Applies the merge, Actions and branch-protection settings the Claude pipeline
# relies on. Safe to run again: every call sets a value rather than adding one,
# and the ruleset is updated in place when it already exists.
#
#   sh scripts/claude-pipeline/apply-repo-settings.sh <owner/repo> [required-check ...]
#
# The required checks default to build-and-test and ui-tests, the job names in
# .github/workflows/pr-check.yml. Each must match a check's name on a PR
# exactly, or the ruleset waits forever for a check that never reports.
# Rulesets on a private repo need GitHub Pro or a paid organisation plan.
set -eu
repo="${1:?usage: apply-repo-settings.sh <owner/repo> [required-check ...]}"
shift
checks="${*:-build-and-test ui-tests}"
here="$(cd "$(dirname "$0")" && pwd)"

echo "Merging: squash only, delete merged branches, auto-merge, suggest updates"
gh api -X PATCH "repos/$repo" --silent \
    -F allow_squash_merge=true \
    -F allow_merge_commit=false \
    -F allow_rebase_merge=false \
    -F delete_branch_on_merge=true \
    -F allow_auto_merge=true \
    -F allow_update_branch=true

echo "Actions: read-only default token, approval for every outside contributor"
gh api -X PUT "repos/$repo/actions/permissions/workflow" --silent \
    -f default_workflow_permissions=read \
    -F can_approve_pull_request_reviews=false
gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" --silent \
    -f approval_policy=all_external_contributors

echo "Ruleset on the default branch: require $checks"
# 15368 is GitHub Actions: a status that anything else posts under the same
# name doesn't count.
# shellcheck disable=SC2086 # one check per word
body=$(printf '%s\n' $checks | jq -R '{context: ., integration_id: 15368}' \
    | jq -s --slurpfile ruleset "$here/ruleset-main.json" '. as $required | $ruleset[0]
        | (.rules[] | select(.type == "required_status_checks")
           | .parameters.required_status_checks) = $required')
name=$(printf '%s' "$body" | jq -r .name)
id=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$name\") | .id")
if [ -n "$id" ]; then
    printf '%s' "$body" | gh api -X PUT "repos/$repo/rulesets/$id" --input - --silent
else
    printf '%s' "$body" | gh api -X POST "repos/$repo/rulesets" --input - --silent
fi

echo "Done. Current state:"
gh api "repos/$repo" --jq '{allow_squash_merge, allow_merge_commit, allow_rebase_merge, delete_branch_on_merge, allow_auto_merge, allow_update_branch}'
gh api "repos/$repo/actions/permissions/workflow"
gh api "repos/$repo/actions/permissions/fork-pr-contributor-approval"
gh api "repos/$repo/rulesets" --jq '.[] | {id, name, enforcement}'
