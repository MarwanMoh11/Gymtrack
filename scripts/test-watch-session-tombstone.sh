#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-session-tombstone
xcrun swiftc -parse-as-library -module-cache-path build/watch-session-tombstone/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/WatchSessionTombstone.swift GymTrackShared/SharedStore.swift \
    Tests/WatchSessionTombstoneTests.swift -o build/watch-session-tombstone/check
build/watch-session-tombstone/check
