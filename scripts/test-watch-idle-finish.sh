#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-idle-finish
xcrun swiftc -parse-as-library -module-cache-path build/watch-idle-finish/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/WatchSessionTombstone.swift GymTrackShared/SharedStore.swift \
    GymTrackWatch/WatchRecordingRules.swift \
    Tests/WatchIdleFinishTests.swift -o build/watch-idle-finish/check
build/watch-idle-finish/check
