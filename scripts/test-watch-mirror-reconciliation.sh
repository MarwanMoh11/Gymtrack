#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-mirror-reconciliation
xcrun swiftc -parse-as-library -module-cache-path build/watch-mirror-reconciliation/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackShared/WatchSessionTombstone.swift GymTrackShared/SharedStore.swift GymTrackShared/WatchPendingActions.swift \
    GymTrackShared/WatchRatingOutbox.swift \
    GymTrackWatch/WatchRecordingRules.swift GymTrackWatch/WatchMirrorReconciliation.swift \
    Tests/WatchMirrorReconciliationTests.swift -o build/watch-mirror-reconciliation/check
build/watch-mirror-reconciliation/check
