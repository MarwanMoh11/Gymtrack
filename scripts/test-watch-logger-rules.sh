#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-logger-rules
xcrun swiftc -parse-as-library -module-cache-path build/watch-logger-rules/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackWatch/WatchLoggerRules.swift GymTrackWatch/WatchRestTimer.swift \
    Tests/WatchHapticsStub.swift \
    Tests/WatchLoggerRulesTests.swift -o build/watch-logger-rules/check
build/watch-logger-rules/check
