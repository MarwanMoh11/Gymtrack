#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/health-write-tests
xcrun swiftc -parse-as-library -module-cache-path build/health-write-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift GymTrack/Models/ExerciseSearch.swift \
    GymTrack/Models/SetContinuation.swift GymTrack/Models/CatalogExercise.swift \
    GymTrack/Models/Entities.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Services/LoadScaleBook.swift \
    Tests/TrainingStatsSettingsStub.swift Tests/HealthWriteTests.swift \
    -o build/health-write-tests/check
build/health-write-tests/check
