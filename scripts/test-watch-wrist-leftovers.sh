#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-wrist-leftovers
xcrun swiftc -parse-as-library -module-cache-path build/watch-wrist-leftovers/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/WatchSessionTombstone.swift GymTrackShared/SharedStore.swift GymTrackShared/WatchPendingActions.swift \
    GymTrackShared/WatchRatingOutbox.swift \
    GymTrackWatch/WatchRecordingRules.swift GymTrackWatch/WatchMirrorReconciliation.swift \
    GymTrackWatch/WatchLoggerRules.swift GymTrackWatch/WatchRestTimer.swift \
    Tests/WatchHapticsStub.swift \
    Tests/WatchWristLeftoversTests.swift -o build/watch-wrist-leftovers/check
build/watch-wrist-leftovers/check
