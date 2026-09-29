#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-recording-rules
xcrun swiftc -parse-as-library -module-cache-path build/watch-recording-rules/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/WatchSessionTombstone.swift \
    GymTrackWatch/WatchRecordingRules.swift \
    Tests/WatchRecordingRulesTests.swift -o build/watch-recording-rules/check
build/watch-recording-rules/check
