#!/bin/sh
# Tape measurements: what typing into a field stores, the card's latest-and-change
# arithmetic, and that a deleted check-in leaves nothing behind.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/body-measurement-tests
xcrun swiftc -parse-as-library -module-cache-path build/body-measurement-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift GymTrack/Models/ExerciseSearch.swift \
    GymTrack/Models/SetContinuation.swift GymTrack/Models/CatalogExercise.swift \
    GymTrack/Models/Entities.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Features/Progress/MeasurementTrend.swift \
    Tests/TrainingStatsSettingsStub.swift Tests/BodyMeasurementTests.swift \
    -o build/body-measurement-tests/check
build/body-measurement-tests/check
