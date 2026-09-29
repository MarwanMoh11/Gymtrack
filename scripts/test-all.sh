#!/bin/sh
# Runs every scripts/test-*.sh, one after another, and says which failed.
#
#   sh scripts/test-all.sh            all of them
#   sh scripts/test-all.sh backup     only scripts whose name contains "backup"
#
# Each script's output goes to build/test-logs/<name>.log rather than the
# terminal, because fifty compiles interleaved would bury the one line that
# matters. A script that hangs is killed after TEST_TIMEOUT seconds (default
# 240) and counts as failed, so one stuck compile can't hold up the rest. They
# run in sequence because several share build directories and module caches.
set -u
cd "$(dirname "$0")/.."
FILTER="${1:-}"
TIMEOUT="${TEST_TIMEOUT:-240}"
LOGS=build/test-logs
mkdir -p "$LOGS"

total=0
failed=""
failures=0
begin=$(date +%s)
for s in scripts/test-*.sh; do
    file=$(basename "$s")
    [ "$file" = "test-all.sh" ] && continue
    case "$file" in *"$FILTER"*) ;; *) continue ;; esac
    name=${file%.sh}
    total=$((total + 1))
    started=$(date +%s)
    if perl -e 'alarm shift; exec @ARGV' "$TIMEOUT" sh "$s" > "$LOGS/$name.log" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    seconds=$(($(date +%s) - started))
    note=""
    if [ "$rc" -ne 0 ]; then
        failures=$((failures + 1))
        failed="$failed $name"
        note="  FAIL"
        # SIGALRM is signal 14, which the shell reports as 128 + 14.
        [ "$rc" -eq 142 ] && note="  FAIL (timed out after ${TIMEOUT}s)"
    fi
    printf 'rc=%-3d %4ds  %s%s\n' "$rc" "$seconds" "$name" "$note"
done

elapsed=$(($(date +%s) - begin))
if [ "$total" -eq 0 ]; then
    echo "No scripts match \"$FILTER\"."
    exit 1
fi
echo "$((total - failures)) passed, $failures failed, $total scripts in ${elapsed}s (logs in $LOGS)"
if [ "$failures" -ne 0 ]; then
    echo "Failed:$failed"
    exit 1
fi
