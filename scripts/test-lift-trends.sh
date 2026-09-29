#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/lift-trends
cp GymTrack/Resources/exercises.json build/lift-trends/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/lift-trends/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift GymTrack/Models/ExerciseSearch.swift \
    GymTrack/Models/SetContinuation.swift GymTrack/Models/CatalogExercise.swift \
    GymTrack/Models/Entities.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Services/LoadScaleBook.swift GymTrack/Services/TrainingStats.swift GymTrack/Services/LiftTrends.swift \
    Tests/TrainingStatsSettingsStub.swift Tests/LiftTrendsTests.swift \
    -o build/lift-trends/check
build/lift-trends/check
