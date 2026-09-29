#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/body-weight-tests
xcrun swiftc -parse-as-library -module-cache-path build/body-weight-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift GymTrack/Models/ExerciseSearch.swift \
    GymTrack/Models/SetContinuation.swift GymTrack/Models/CatalogExercise.swift \
    GymTrack/Models/Entities.swift GymTrack/Services/SetHeartRate.swift \
    Tests/TrainingStatsSettingsStub.swift Tests/BodyWeightCorrectionTests.swift \
    -o build/body-weight-tests/check
build/body-weight-tests/check
