#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build/rest-render
xcrun swiftc -parse-as-library -module-cache-path build/rest-render/module-cache \
    GymTrack/Services/RestTimer.swift Tests/RestTimerHapticsStub.swift \
    Tests/RestTimerRenderTests.swift -o build/rest-render/check
build/rest-render/check
