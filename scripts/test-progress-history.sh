#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/progress-history-tests
cp GymTrack/Resources/exercises.json build/progress-history-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/progress-history-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift GymTrack/Models/ExerciseSearch.swift \
    GymTrack/Models/SetContinuation.swift GymTrack/Models/CatalogExercise.swift \
    GymTrack/Models/Entities.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Services/LoadScaleBook.swift GymTrack/Services/TrainingStats.swift \
    GymTrack/Features/Progress/ProgressHistory.swift \
    Tests/TrainingStatsSettingsStub.swift Tests/ProgressHistoryTests.swift \
    -o build/progress-history-tests/check
build/progress-history-tests/check
