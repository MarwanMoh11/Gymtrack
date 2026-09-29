#!/bin/sh
# Compiles the real WidgetPublisher.swift against a two-type stub of its
# neighbours, so the widgets' done-card rule is the shipping code.
set -eu
cd "$(dirname "$0")/.."
ROOT="${ROOT:-.}"
mkdir -p build/widget-snapshot-tests
cp "$ROOT/GymTrack/Resources/exercises.json" build/widget-snapshot-tests/exercises.json
xcrun swiftc -parse-as-library -module-cache-path build/widget-snapshot-tests/module-cache \
    "$ROOT/GymTrackShared/Theme.swift" "$ROOT/GymTrackShared/Units.swift" \
    "$ROOT/GymTrackShared/LoadScale.swift" "$ROOT/GymTrackShared/SetFeel.swift" \
    "$ROOT/GymTrackShared/SharedStore.swift" "$ROOT/GymTrackShared/RestProgress.swift" \
    "$ROOT/GymTrack/Models/Muscle.swift" "$ROOT/GymTrack/Models/NoteTag.swift" \
    "$ROOT/GymTrack/Models/ExerciseSearch.swift" "$ROOT/GymTrack/Models/SetContinuation.swift" \
    "$ROOT/GymTrack/Models/CatalogExercise.swift" "$ROOT/GymTrack/Models/Entities.swift" \
    "$ROOT/GymTrack/Services/SetHeartRate.swift" "$ROOT/GymTrack/Services/LoadScaleBook.swift" \
    "$ROOT/GymTrack/Services/TrainingStats.swift" "$ROOT/GymTrack/Services/SessionPosition.swift" \
    "$ROOT/GymTrack/Services/WidgetPublisher.swift" \
    Tests/TrainingStatsSettingsStub.swift Tests/WidgetSnapshotStubs.swift Tests/WidgetSnapshotTests.swift \
    -o build/widget-snapshot-tests/check
build/widget-snapshot-tests/check
