#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/late-wrist-logs
cp GymTrack/Resources/exercises.json build/late-wrist-logs/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/late-wrist-logs/module-cache \
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
    GymTrack/Services/WatchSessionRecovery.swift Tests/ActiveWorkoutStructureStubs.swift Tests/LateWristLogTests.swift \
    -o build/late-wrist-logs/check
build/late-wrist-logs/check
