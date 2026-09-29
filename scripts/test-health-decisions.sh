#!/bin/sh
# Health duplicate-workout decisions (XC-05): write, outcome, relink, delete plan, retry gate.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/health-decisions-tests
xcrun swiftc -parse-as-library -module-cache-path build/health-decisions-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift GymTrack/Models/ExerciseSearch.swift \
    GymTrack/Models/SetContinuation.swift GymTrack/Models/CatalogExercise.swift \
    GymTrack/Models/Entities.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Services/LoadScaleBook.swift GymTrack/Services/HealthCleanupQueue.swift \
    Tests/TrainingStatsSettingsStub.swift Tests/HealthDecisionsTests.swift \
    -o build/health-decisions-tests/check
build/health-decisions-tests/check
