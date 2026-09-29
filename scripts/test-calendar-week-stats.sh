#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/calendar-week-tests
xcrun swiftc -parse-as-library -module-cache-path build/calendar-week-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift GymTrack/Models/ExerciseSearch.swift \
    GymTrack/Models/SetContinuation.swift GymTrack/Models/CatalogExercise.swift \
    GymTrack/Models/Entities.swift GymTrack/Services/SetHeartRate.swift \
    GymTrack/Services/LoadScaleBook.swift GymTrack/Services/TrainingStats.swift \
    Tests/TrainingStatsSettingsStub.swift Tests/CalendarWeekStatsTests.swift \
    -o build/calendar-week-tests/check
build/calendar-week-tests/check
