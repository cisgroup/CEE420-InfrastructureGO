#!/usr/bin/env bash
# Run the app's tests in the simulator and say how many ran. A run that executed fewer tests than the number kept
# in expected_tests.txt does not count as a success, because a scheme that lost its tests would otherwise look green.
set -uo pipefail
cd "$(dirname "$0")/.."
device="${IGO_SIM:-iPhone 18 Pro}"
bundle="../build/test.xcresult"
rm -rf "$bundle"
xcodebuild test -project InfrastructureGO.xcodeproj -scheme InfrastructureGO \
  -destination "platform=iOS Simulator,name=$device" -derivedDataPath ../build/dd -resultBundlePath "$bundle" -quiet
code=$?
summary=$(xcrun xcresulttool get test-results summary --path "$bundle" 2>/dev/null)
read -r passed failed skipped <<<"$(printf '%s' "$summary" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("passedTests", 0), d.get("failedTests", 0), d.get("skippedTests", 0))
except Exception:
    print("0 0 0")
')"
expected=$(cat scripts/expected_tests.txt 2>/dev/null || echo 1)
echo "app tests on $device: $passed passed, $failed failed, $skipped skipped, at least $expected expected, xcodebuild exit code $code"
if [ "$code" -ne 0 ] || [ "$failed" -ne 0 ] || [ "$passed" -lt "$expected" ]; then
  exit 1
fi
