#!/bin/sh
# Builds and tests GymTrack the way CI does, and prints only what went wrong.
#
#   check.sh build                         all three targets and all three test bundles
#   check.sh test GymTrackTests/UnitsTests  the named suites (rebuilding first if needed)
#   check.sh test                          every suite, UI tests included (about 15 minutes)
#
# This is the one command a Claude run in GitHub Actions may execute (see
# .github/workflows/claude.yml). Without it the run writes Swift it has never
# compiled, and the first compiler to see it is CI, a round trip later. The
# output is filtered because every line printed is read by the model: a raw
# xcodebuild log is thousands of lines and would cost more than the fix.
# Full logs stay in build/claude-check/ for anyone who needs the context.
#
# It works on any Mac with Xcode, so a local session can use it too.

set -u

# The script starts over with a bare environment before doing anything else.
# The cloud run can write any file in the checkout, so anything read from there
# may turn out to be code: a script phase in the project, a module Python finds
# in the current directory, a cached file. With nothing secret in the
# environment, none of it can reach the Claude token.
if [ -z "${CHECK_SCRUBBED:-}" ]; then
    root=${GITHUB_WORKSPACE:-$(git rev-parse --show-toplevel)} || exit 2
    exec env -i PATH="$PATH" HOME="$HOME" USER="${USER:-runner}" TMPDIR="${TMPDIR:-/tmp}" \
        LANG=en_US.UTF-8 ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} \
        CHECK_SCRUBBED=1 CHECK_ROOT="$root" /bin/sh "$0" "$@"
fi

cd "$CHECK_ROOT" || exit 2
OUT=build/claude-check
mkdir -p "$OUT"

# The newest iPhone Pro and 46mm watch on the newest runtime, looked up because
# names change with every Xcode. Cached, because asking simctl takes seconds and
# the answer can't change within a run. Python runs isolated (-I), so it can't
# import a module planted in the checkout, and the cache is read as data: only
# a well-formed simulator ID is taken from it, never run as shell.
pick_simulators() {
    if [ ! -s "$OUT/sims.env" ]; then
        python3 -I - > "$OUT/sims.env" <<'PY' || exit 2
import json, re, subprocess, sys
devices = json.loads(subprocess.check_output(
    ["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
def pick(platform, preferred, fallback):
    best = None
    for runtime, sims in devices.items():
        m = re.search(rf"SimRuntime\.{platform}-(\d+)-(\d+)(?:-(\d+))?$", runtime)
        if not m:
            continue
        version = tuple(int(v or 0) for v in m.groups())
        for sim in sims:
            if re.match(preferred, sim["name"]):
                rank = 1
            elif sim["name"].startswith(fallback):
                rank = 0
            else:
                continue
            if best is None or (version, rank) > best[0]:
                best = ((version, rank), sim["udid"], f'{sim["name"]} ({runtime.split(".")[-1]})')
    if best is None:
        sys.exit(f"No {fallback} simulator is available")
    print(f"Using {best[2]}", file=sys.stderr)
    return best[1]
print("IPHONE_ID=" + pick("iOS", r"iPhone \d+ Pro$", "iPhone"))
print("WATCH_ID=" + pick("watchOS", r"Apple Watch Series \d+ \(46mm\)$", "Apple Watch"))
PY
    fi
    IPHONE_ID=$(sed -n 's/^IPHONE_ID=\([0-9A-F-]\{36\}\)$/\1/p' "$OUT/sims.env")
    WATCH_ID=$(sed -n 's/^WATCH_ID=\([0-9A-F-]\{36\}\)$/\1/p' "$OUT/sims.env")
    if [ -z "$IPHONE_ID" ] || [ -z "$WATCH_ID" ]; then
        rm -f "$OUT/sims.env"
        echo "Could not pick simulators; run again" >&2
        exit 2
    fi
}

# Compiler errors and test failures, each once, with the repo path trimmed so
# the lines are short, then xcodebuild's own summary of what failed. Capped: past forty, the
# first errors are the ones to fix. "exit code 0" lines are xcodebuild noise.
report() {
    grep -E ': error: |^error: |✘ |recorded an issue|Test case .* failed' "$1" \
        | grep -v 'exit code 0' | sed "s|$PWD/||g" | awk '!seen[$0]++' | head -40
    awk '/^(Failing tests|Testing failed):/ { on = 1 } on && /^$/ { on = 0 } on' "$1" \
        | sed "s|$PWD/||g" | cut -c1-300 | head -30
    echo "Full log: $1"
}

# Runs one xcodebuild, keeping its log, and reports only on failure. Builds
# are quiet, which still prints every error; tests are not, because a quiet
# test run names a failing test without saying which expectation failed.
run() {
    label=$1 log=$2 verbosity=$3
    shift 3
    # shellcheck disable=SC2086 # an empty verbosity must vanish, not become ""
    if xcodebuild "$@" $verbosity CODE_SIGNING_ALLOWED=NO > "$log" 2>&1; then
        echo "ok: $label"
        return 0
    fi
    # A simulator can refuse to launch an app it has just installed ("Unknown
    # application display identifier"). No test runs, so the failure says nothing
    # about the change, yet it turned a pull request's required check red. One
    # more try, keeping the first log. Nothing else is retried, and a launch the
    # change itself breaks fails twice, so this can't hide a failure.
    if grep -q 'Failed to install or launch the test runner' "$log"; then
        mv "$log" "${log%.log}-first-try.log"
        echo "retrying: $label (the simulator never launched the test runner)"
        # shellcheck disable=SC2086
        if xcodebuild "$@" $verbosity CODE_SIGNING_ALLOWED=NO > "$log" 2>&1; then
            echo "ok: $label"
            return 0
        fi
    fi
    echo "FAILED: $label"
    report "$log"
    return 1
}

# Boots a simulator and returns once it has finished, at once if it already has.
# Left to itself, xcodebuild boots the simulator only after building, and a
# freshly booted simulator stays slow for minutes. On PR #52 the UI test runner
# took three minutes to start and the app's first launch seventy seconds. Booted
# before `xcodebuild test` builds, it settles while the build runs: on PR #53
# those took 41 and 35 seconds. A boot that fails is left for xcodebuild to
# retry and report.
#
# `check.sh build` doesn't boot: a simulator busy settling takes the runner's
# three cores from the compiler, and on PR #53 that stretched the build from
# two minutes to eleven.
boot() {
    xcrun simctl bootstatus "$1" -b > "$OUT/boot-$1.log" 2>&1
}

build() {
    status=0
    run "iPhone app, watch app, widgets and their test bundles" "$OUT/build-iphone.log" -quiet \
        build-for-testing -project GymTrack.xcodeproj -scheme GymTrack \
        -destination "id=$IPHONE_ID" -derivedDataPath "$OUT/dd" || status=1
    run "watch test bundle" "$OUT/build-watch.log" -quiet \
        build-for-testing -project GymTrack.xcodeproj -scheme GymTrackWatch \
        -destination "id=$WATCH_ID" -derivedDataPath "$OUT/dd-watch" || status=1
    return $status
}

# Splits the named suites between the two schemes, since a watch suite only
# runs on a watch simulator. Diagnostics are off: by default a failing test
# makes xcodebuild spend minutes collecting a simulator report nobody reads.
test_suites() {
    phone="" watch=""
    for suite in "$@"; do
        case $suite in
            GymTrackWatchTests*) watch="$watch -only-testing:$suite" ;;
            *) phone="$phone -only-testing:$suite" ;;
        esac
    done
    if [ $# -eq 0 ]; then
        phone=" " watch=" "
    fi

    status=0
    if [ -n "$phone" ]; then
        boot "$IPHONE_ID"
        # shellcheck disable=SC2086 # each -only-testing is its own argument
        run "iPhone tests:$phone" "$OUT/test-iphone.log" "" \
            test -project GymTrack.xcodeproj -scheme GymTrack -destination "id=$IPHONE_ID" \
            -derivedDataPath "$OUT/dd" -parallel-testing-enabled NO -collect-test-diagnostics never \
            $phone || status=1
    fi
    if [ -n "$watch" ]; then
        # shellcheck disable=SC2086
        run "watch tests:$watch" "$OUT/test-watch.log" "" \
            test -project GymTrack.xcodeproj -scheme GymTrackWatch -destination "id=$WATCH_ID" \
            -derivedDataPath "$OUT/dd-watch" -parallel-testing-enabled NO -collect-test-diagnostics never \
            $watch || status=1
    fi
    return $status
}

command=${1:-}
[ $# -gt 0 ] && shift
case $command in
    build) pick_simulators; build ;;
    test) pick_simulators; test_suites "$@" ;;
    *)
        echo "usage: check.sh build | check.sh test [Target/Suite ...]" >&2
        exit 2
        ;;
esac
