#!/bin/sh
# XC-09: the AppSettings stubs must start from the values a fresh install gets.
# The tests once ran with rest auto-start off while every user has it on, so
# the code path users take most was the one nothing exercised. Reads the
# defaults AppSettings registers and compares each stub's initial value; a
# stub that leaves a setting out is fine, one that disagrees is not.
set -eu
cd "$(dirname "$0")/.."
real() {
    sed -n '/register(defaults/,/\])/p' GymTrack/Services/AppSettings.swift |
        sed -n "s/.*SettingsKey\\.$1: *\\(.*\\),.*/\\1/p" | sed 's/WeightUnit\.\([a-z]*\)\.rawValue/\1/'
}
status=0
for stub in $(grep -l 'final class AppSettings' Tests/*.swift); do
    body=$(awk '/final class AppSettings/{p=1} p{print} p&&/^}/{exit}' "$stub")
    for setting in weightUnit restTimerAutoStart defaultRestSeconds trackRPE watchAutoLaunch; do
        line=$(printf '%s\n' "$body" | grep -E "^ *var $setting\b" || true)
        [ -n "$line" ] || continue
        held=$(printf '%s\n' "$line" | sed -e 's/.*= *//' -e 's/^\.//')
        want=$(real "$setting")
        [ -n "$want" ] || { echo "AppSettings registers no default for $setting"; status=1; continue; }
        if [ "$held" != "$want" ]; then
            echo "$stub: $setting starts as $held, a fresh install has $want"
            status=1
        fi
    done
done
[ "$status" -eq 0 ] && echo "Stub defaults match AppSettings"
exit "$status"
