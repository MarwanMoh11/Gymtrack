#!/bin/sh
# XC-08: the backup keeps every measured weight in kilograms when the phone
# shows pounds, and restoring it brings the unit label back.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/pound-backup-tests
cp GymTrack/Resources/exercises.json build/pound-backup-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/pound-backup-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/LoadScaleBook.swift \
    GymTrack/Services/ExerciseVisibility.swift GymTrack/Services/BackupService.swift \
    Tests/BackupServiceStubs.swift Tests/PoundBackupTests.swift \
    -o build/pound-backup-tests/check
build/pound-backup-tests/check
