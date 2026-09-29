#!/bin/sh
# ROOT overrides where the app sources come from, so the checks can be run
# against another tree; the tests and stubs always come from this one.
set -eu
cd "$(dirname "$0")/.."
ROOT="${ROOT:-.}"
mkdir -p build/workout-model-fixes
cp "$ROOT/GymTrack/Resources/exercises.json" build/workout-model-fixes/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/workout-model-fixes/module-cache \
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
    "$ROOT/GymTrack/Services/WatchSessionRecovery.swift" Tests/WorkoutModelFixesStubs.swift Tests/WorkoutModelFixesTests.swift \
    -o build/workout-model-fixes/check
build/workout-model-fixes/check
