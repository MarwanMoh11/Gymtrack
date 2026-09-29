#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/health-cleanup-queue-tests
xcrun swiftc -parse-as-library -module-cache-path build/health-cleanup-queue-tests/module-cache \
    GymTrack/Services/HealthCleanupQueue.swift Tests/HealthCleanupQueueTests.swift \
    -o build/health-cleanup-queue-tests/check
build/health-cleanup-queue-tests/check
