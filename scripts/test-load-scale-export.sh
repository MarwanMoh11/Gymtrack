#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/load-scale-export-tests
cp GymTrack/Resources/exercises.json build/load-scale-export-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/load-scale-export-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/LoadScaleBook.swift \
    GymTrack/Services/ExerciseVisibility.swift GymTrack/Services/BackupService.swift \
    Tests/BackupServiceStubs.swift Tests/LoadScaleExportTests.swift \
    -o build/load-scale-export-tests/check
build/load-scale-export-tests/check
