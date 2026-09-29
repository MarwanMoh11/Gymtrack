#!/bin/sh
# XC-10: a field-exhaustive check that un-logging a set leaves no trace.
set -eu
cd "$(dirname "$0")/.."
ROOT="${ROOT:-.}"
mkdir -p build/unlog-no-trace
cp "$ROOT/GymTrack/Resources/exercises.json" build/unlog-no-trace/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/unlog-no-trace/module-cache \
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
    "$ROOT/GymTrack/Services/WatchCommandCenter.swift" \
    "$ROOT/GymTrack/Services/WatchSessionRecovery.swift" Tests/WorkoutModelFixesStubs.swift Tests/UnlogNoTraceTests.swift \
    -o build/unlog-no-trace/check
build/unlog-no-trace/check
