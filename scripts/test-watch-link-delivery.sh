#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/watch-link-delivery
xcrun swiftc -parse-as-library -module-cache-path build/watch-link-delivery/module-cache \
    GymTrackShared/Theme.swift GymTrackShared/Units.swift \
    GymTrackShared/LoadScale.swift GymTrackShared/SetFeel.swift \
    GymTrackShared/WatchSetRating.swift GymTrackShared/WatchLink.swift \
    GymTrackWatch/WatchLoggerRules.swift GymTrackWatch/WatchRestTimer.swift Tests/WatchHapticsStub.swift \
    Tests/WatchLinkDeliveryTests.swift -o build/watch-link-delivery/check
build/watch-link-delivery/check
