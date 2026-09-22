#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-rating-tests
xcrun swiftc -parse-as-library -module-cache-path build/watch-rating-tests/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift GymTrackShared/WatchRatingOutbox.swift \
    Tests/WatchSetRatingTests.swift -o build/watch-rating-tests/check
build/watch-rating-tests/check
