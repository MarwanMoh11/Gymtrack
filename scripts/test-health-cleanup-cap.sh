#!/bin/sh
# Health cleanup cap: a withdrawn write permission costs no attempt, and an entry whose relink never succeeds is given up.
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/health-cleanup-cap-tests
xcrun swiftc -parse-as-library -module-cache-path build/health-cleanup-cap-tests/module-cache \
    GymTrack/Services/SetHeartRate.swift GymTrack/Services/HealthCleanupQueue.swift \
    Tests/HealthCleanupCapTests.swift \
    -o build/health-cleanup-cap-tests/check
build/health-cleanup-cap-tests/check
