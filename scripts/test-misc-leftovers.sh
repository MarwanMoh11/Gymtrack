#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/misc-leftovers
cp GymTrack/Resources/exercises.json build/misc-leftovers/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/misc-leftovers/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift GymTrack/Models/ExerciseSearch.swift \
    GymTrack/Models/SetContinuation.swift GymTrack/Models/CatalogExercise.swift \
    GymTrack/Models/Entities.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Services/LoadScaleBook.swift GymTrack/Services/TrainingStats.swift \
    GymTrack/Services/ExerciseRename.swift GymTrack/Services/SummaryRecords.swift \
    GymTrack/Services/LiveMetricsMerge.swift \
    Tests/TrainingStatsSettingsStub.swift Tests/MiscLeftoverTests.swift \
    -o build/misc-leftovers/check
build/misc-leftovers/check
