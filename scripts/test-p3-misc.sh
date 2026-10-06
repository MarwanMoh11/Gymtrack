#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/p3-misc
xcrun swiftc -parse-as-library -module-cache-path build/p3-misc/module-cache \
    GymTrackShared/Units.swift GymTrack/Services/AppSettings.swift \
    GymTrack/Services/RestTimer.swift Tests/RestTimerHapticsStub.swift GymTrackShared/LaunchMode.swift \
    GymTrackShared/SharedStore.swift GymTrackShared/GymTrackIntents.swift \
    Tests/P3MiscTests.swift -o build/p3-misc/check
build/p3-misc/check
