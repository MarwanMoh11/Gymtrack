#!/bin/sh
# Same file list and stubs as test-watch-command-center.sh, with its own tests.
# ROOT overrides where the app sources come from, so the checks can be run
# against another tree; the tests and stubs always come from this one.
set -eu
cd "$(dirname "$0")/.."
ROOT="${ROOT:-.}"
mkdir -p build/late-wrist-log-repairs
cp "$ROOT/GymTrack/Resources/exercises.json" build/late-wrist-log-repairs/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/late-wrist-log-repairs/module-cache \
    "$ROOT/GymTrackShared/Theme.swift" "$ROOT/GymTrackShared/Units.swift" \
    "$ROOT/GymTrackShared/LoadScale.swift" "$ROOT/GymTrackShared/SetFeel.swift" \
    "$ROOT/GymTrackShared/WatchSetRating.swift" "$ROOT/GymTrackShared/WatchLink.swift" \
    "$ROOT/GymTrackShared/SetLeadIn.swift" \
    "$ROOT/GymTrack/Models/Muscle.swift" "$ROOT/GymTrack/Models/NoteTag.swift" \
    "$ROOT/GymTrack/Models/ExerciseSearch.swift" "$ROOT/GymTrack/Models/SetContinuation.swift" \
    "$ROOT/GymTrack/Models/CatalogExercise.swift" "$ROOT/GymTrack/Models/Entities.swift" \
    "$ROOT/GymTrack/Models/SessionClosing.swift" \
    "$ROOT/GymTrack/Services/SetHeartRate.swift" "$ROOT/GymTrack/Services/LoadScaleBook.swift" \
    "$ROOT/GymTrack/Services/TrainingStats.swift" "$ROOT/GymTrack/Services/ActiveWorkout.swift" "$ROOT/GymTrack/Services/SessionPosition.swift" \
    "$ROOT/GymTrack/Services/WatchCommandCenter.swift" "$ROOT/GymTrack/Services/WatchSessionRecovery.swift" \
    Tests/WatchCommandCenterStubs.swift Tests/LateWristLogRepairTests.swift \
    -o build/late-wrist-log-repairs/check
build/late-wrist-log-repairs/check
