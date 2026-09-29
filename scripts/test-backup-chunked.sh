#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/backup-chunked-tests
cp GymTrack/Resources/exercises.json build/backup-chunked-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/backup-chunked-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/LoadScaleBook.swift \
    GymTrack/Services/ExerciseVisibility.swift GymTrack/Services/BackupService.swift \
    Tests/BackupServiceStubs.swift Tests/BackupChunkedTests.swift \
    -o build/backup-chunked-tests/check
build/backup-chunked-tests/check
