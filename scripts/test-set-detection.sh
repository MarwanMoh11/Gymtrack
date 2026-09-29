#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/set-detection-tests
xcrun swiftc -parse-as-library -module-cache-path build/set-detection-tests/module-cache \
    GymTrack/Services/SetHeartRate.swift \
    Tests/SetEffortDetectionTests.swift -o build/set-detection-tests/check
build/set-detection-tests/check
