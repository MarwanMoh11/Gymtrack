#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/session-rules
cp GymTrack/Resources/exercises.json build/session-rules/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/session-rules/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift GymTrackShared/SharedStore.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/WatchPendingActions.swift GymTrackShared/SetLeadIn.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift \
    GymTrack/Models/SessionClosing.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Services/LoadScaleBook.swift Tests/TrainingStatsSettingsStub.swift \
    Tests/SessionRulesTests.swift \
    -o build/session-rules/check
build/session-rules/check
