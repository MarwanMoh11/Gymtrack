#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/today-mirror-tests
xcrun swiftc -parse-as-library -module-cache-path build/today-mirror-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift GymTrackShared/LoadScale.swift \
    GymTrackShared/SetFeel.swift GymTrackShared/WatchSetRating.swift \
    GymTrackShared/SetLeadIn.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/SharedStore.swift \
    Tests/TodayMirrorTests.swift \
    -o build/today-mirror-tests/check
build/today-mirror-tests/check
