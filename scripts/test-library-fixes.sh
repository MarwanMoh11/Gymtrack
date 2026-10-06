#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
out=build/library-fixes
mkdir -p "$out"
cp GymTrack/Resources/exercises.json "$out/exercises.json"
# StepperEntry lives beside StepperField in Components.swift, which needs
# SwiftUI and iOS-only modifiers. The enum itself is Foundation-only, so it is
# lifted out on its own rather than moving it into a new app source file.
{
    echo "import Foundation"
    awk '/^enum StepperEntry /,/^}/' GymTrack/DesignSystem/Components.swift
} > "$out/StepperEntry.swift"
grep -q "static func parse" "$out/StepperEntry.swift"
xcrun swiftc -parse-as-library -module-cache-path "$out/module-cache" \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift GymTrackShared/SharedStore.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/SetLeadIn.swift \
    GymTrack/Models/Muscle.swift GymTrack/Models/NoteTag.swift \
    GymTrack/Models/ExerciseSearch.swift GymTrack/Models/SetContinuation.swift \
    GymTrack/Models/CatalogExercise.swift GymTrack/Models/Entities.swift GymTrack/Models/PlanChoice.swift \
    GymTrack/Models/SessionClosing.swift \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/LoadScaleBook.swift \
    GymTrack/Services/TrainingStats.swift GymTrack/Services/ActiveWorkout.swift GymTrack/Services/SessionPosition.swift \
    GymTrack/Services/WatchCommandCenter.swift GymTrack/Services/PlanTemplates.swift \
    "$out/StepperEntry.swift" \
    GymTrack/Services/WatchSessionRecovery.swift Tests/ActiveWorkoutStructureStubs.swift Tests/LibraryFixesTests.swift \
    -o "$out/check"
"$out/check"
