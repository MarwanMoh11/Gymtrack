#!/bin/sh
# Health leftovers: the cleanup attempt cap (HK-06) and de-duplicated wrist energy (DATA-10).
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/health-leftovers-tests
xcrun swiftc -parse-as-library -module-cache-path build/health-leftovers-tests/module-cache \
    GymTrack/Services/SetHeartRate.swift Tests/HealthLeftoversTests.swift \
    -o build/health-leftovers-tests/check
build/health-leftovers-tests/check
