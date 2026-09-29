#!/bin/sh
# XC-10: export, restore into a fresh container, export again, compare.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/backup-round-trip-tests
cp GymTrack/Resources/exercises.json build/backup-round-trip-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/backup-round-trip-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/LoadScaleBook.swift \
    GymTrack/Services/ExerciseVisibility.swift GymTrack/Services/BackupService.swift \
    Tests/BackupServiceStubs.swift Tests/BackupRoundTripTests.swift \
    -o build/backup-round-trip-tests/check
build/backup-round-trip-tests/check
