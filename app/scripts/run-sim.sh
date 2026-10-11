#!/usr/bin/env bash
# Build the app, put it on the simulator and start it there. Whatever follows the script's name is handed to the
# app, which in a debug build understands a few words for showing one screen at once, for example
#
#     app/scripts/run-sim.sh -igo.stand in1375            the player stands at that drain
#     app/scripts/run-sim.sh -igo.encounter in1375        the catch at that drain opens at once
#     app/scripts/run-sim.sh -igo.tab guide -igo.fill 40  the field guide after forty made up catches
#     app/scripts/run-sim.sh -igo.reset YES               the saved catches are thrown away first
#
# IGO_SIM names another simulator, IGO_FIX another position as latitude,longitude, and IGO_NOBUILD=1 starts the
# app that was built last without building again.
set -euo pipefail
cd "$(dirname "$0")/.."
device="${IGO_SIM:-iPhone 18 Pro}"
bundle="edu.princeton.cee420.infrastructurego"
products="../build/dd/Build/Products/Debug-iphonesimulator"

if [ -z "${IGO_NOBUILD:-}" ]; then
  xcodebuild build -project InfrastructureGO.xcodeproj -scheme InfrastructureGO \
    -destination "platform=iOS Simulator,name=$device" -derivedDataPath ../build/dd -quiet
fi
xcrun simctl boot "$device" 2>/dev/null || true
xcrun simctl bootstatus "$device" >/dev/null
xcrun simctl terminate "$device" "$bundle" 2>/dev/null || true
xcrun simctl install "$device" "$products/InfrastructureGO.app"
xcrun simctl privacy "$device" grant location "$bundle"
xcrun simctl location "$device" set "${IGO_FIX:-40.356792,-74.672675}"
xcrun simctl launch "$device" "$bundle" "$@" >/dev/null
echo "InfrastructureGO is running on $device, commit $(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
