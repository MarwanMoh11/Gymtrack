#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-command-reliability
cp GymTrack/Resources/exercises.json build/watch-command-reliability/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/watch-command-reliability/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/WatchPendingActions.swift GymTrackShared/SetLeadIn.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift \
    GymTrack/Models/SessionClosing.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Services/LoadScaleBook.swift Tests/TrainingStatsSettingsStub.swift \
    Tests/WatchCommandReliabilityTests.swift \
    -o build/watch-command-reliability/check
build/watch-command-reliability/check
