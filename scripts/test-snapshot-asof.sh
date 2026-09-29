#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/snapshot-asof-tests
xcrun swiftc -parse-as-library -module-cache-path build/snapshot-asof-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift GymTrackShared/LoadScale.swift \
    GymTrackShared/SetFeel.swift GymTrackShared/WatchSetRating.swift \
    GymTrackShared/SetLeadIn.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/SharedStore.swift \
    Tests/SnapshotAsOfTests.swift \
    -o build/snapshot-asof-tests/check
build/snapshot-asof-tests/check
