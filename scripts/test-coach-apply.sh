#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/coach-apply-tests
cp GymTrack/Resources/exercises.json build/coach-apply-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/coach-apply-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/LoadScaleBook.swift \
    GymTrack/Services/ExerciseVisibility.swift GymTrack/Services/BackupService.swift \
    GymTrack/Services/Coach/CoachModels.swift GymTrack/Services/Coach/CoachStore.swift \
    GymTrack/Services/Coach/CoachValidator.swift GymTrack/Services/Coach/CoachApplier.swift \
    GymTrack/Services/Coach/CoachSnapshot.swift GymTrack/Services/Coach/CoachInbox.swift \
    Tests/BackupServiceStubs.swift Tests/CoachTestSupport.swift Tests/CoachApplyTests.swift \
    -o build/coach-apply-tests/check
build/coach-apply-tests/check
