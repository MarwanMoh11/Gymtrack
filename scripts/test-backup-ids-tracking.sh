#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/backup-ids-tracking-tests
cp GymTrack/Resources/exercises.json build/backup-ids-tracking-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/backup-ids-tracking-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/LoadScaleBook.swift \
    GymTrack/Services/ExerciseVisibility.swift GymTrack/Services/BackupService.swift \
    Tests/BackupServiceStubs.swift Tests/BackupIDsTrackingTests.swift \
    -o build/backup-ids-tracking-tests/check
build/backup-ids-tracking-tests/check
