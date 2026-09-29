#!/bin/sh
# XC-08: the progression suggestion, the ladders, snapping and formatting, run in
# kilograms and in pounds.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/pound-load-tests
cp GymTrack/Resources/exercises.json build/pound-load-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/pound-load-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift GymTrackShared/SharedStore.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/SetLeadIn.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift GymTrack/Models/PlanChoice.swift \
    GymTrack/Models/SessionClosing.swift \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/LoadScaleBook.swift \
    GymTrack/Services/TrainingStats.swift GymTrack/Services/ActiveWorkout.swift GymTrack/Services/SessionPosition.swift \
    GymTrack/Services/WatchCommandCenter.swift \
    GymTrack/Services/WatchSessionRecovery.swift Tests/ActiveWorkoutStructureStubs.swift Tests/PoundLoadTests.swift \
    -o build/pound-load-tests/check
build/pound-load-tests/check
