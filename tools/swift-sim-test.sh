#!/usr/bin/env bash
# swift-sim-test.sh - runs TabPetUIKitTests, plus every animal-target test
# that reads no repository file, on an iOS simulator via xcodebuild.
#
# Usage: swift-sim-test.sh [device-id]
#   device-id: a simulator udid (xcrun simctl list devices), not a name and
#   not "booted". Without one, picks the first available iPhone simulator.
#
# Derived data sits outside the repository: a test host may be unable to open
# a bundle under a protected folder such as ~/Documents (open fails, errno 1).
# Override with SWIFT_SIM_DERIVED_DATA.
set -euo pipefail
cd "$(dirname "$0")/.."

DERIVED_DATA_PATH="${SWIFT_SIM_DERIVED_DATA:-${TMPDIR:-/tmp}/tabpet-swift-sim}"

DEVICE_ID="${1:-}"
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID="$(xcrun simctl list devices available --json \
    | python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
for runtime, entries in devices.items():
    if "iOS" not in runtime:
        continue
    for entry in entries:
        if "iPhone" in entry["name"]:
            print(entry["udid"])
            sys.exit(0)
')"
fi
if [ -z "$DEVICE_ID" ]; then
  echo "swift-sim-test: no available iPhone simulator found" >&2
  exit 1
fi

# SwiftPM test targets don't get their own scheme; find the package's
# "*-Package" scheme rather than guessing its name. Capture stderr too: a
# failed `-list` must not be parsed as if it had produced scheme output.
LIST_OUTPUT="$(xcodebuild -list 2>&1)" || {
  echo "swift-sim-test: xcodebuild -list failed:" >&2
  echo "$LIST_OUTPUT" >&2
  exit 1
}
SCHEME="$(echo "$LIST_OUTPUT" | awk '/-Package$/ {print $1; exit}')"
if [ -z "$SCHEME" ]; then
  echo "swift-sim-test: no *-Package scheme found via xcodebuild -list" >&2
  exit 1
fi

# TabPetAnimalsSimSafeTests reads only the app bundle it was built into
# (pixel geometry, the license file, the bundle-hash test, the locator test)
# or no file at all (the exact-attribution-string test) - none of it touches
# a repository path by absolute host location, which the simulator's
# sandboxed test process cannot open (permission denied). Selecting the
# whole class, not one method at a time, means a renamed or added test in it
# is picked up here without editing this script. Left out, and proven on
# macOS `swift test` instead (TabPetAnimalsFixtureTests): it reads
# conformance/animals.json by repository path; nothing in this target reads
# the repository's LICENSE-ART.md any more.
#
# -only-testing selects by name: if a selected class is renamed, xcodebuild
# runs zero of its tests and still exits 0. TEST_OUTPUT captures the run so
# each selection can be checked below for at least one executed test.
TEST_OUTPUT="$(mktemp "${TMPDIR:-/tmp}/swift-sim-test.XXXXXX.log")"
trap 'rm -f "$TEST_OUTPUT"' EXIT

xcodebuild test \
  -scheme "$SCHEME" \
  -only-testing:TabPetUIKitTests \
  -only-testing:TabPetCoreTests/ResourceBundleLocatorTests \
  -only-testing:TabPetAnimalsTests/TabPetAnimalsSimSafeTests \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  | tee "$TEST_OUTPUT"

# A selection with no match produces no failure of its own - xcodebuild
# still exits 0. Require xcodebuild's own "Test Suite '<name>' passed/failed"
# line, immediately followed by "Executed N tests" with N >= 1, for each
# selection - the whole target for TabPetUIKitTests (its `xctest` bundle is
# the suite name xcodebuild prints for a target-level selection, since the
# selection names no single class inside it) and the class itself for the
# other two, so a rename that makes -only-testing match nothing fails this
# script even though the xcodebuild invocation above did not.
check_suite_ran() {
  local name="$1"
  local executed
  # `|| true`: no match must reach the message below, not trip errexit here.
  executed="$(grep -A1 "Test Suite '${name}' \(passed\|failed\) at" "$TEST_OUTPUT" | grep -oE 'Executed [0-9]+ test' | head -1 | grep -oE '[0-9]+' || true)"
  if [ -z "$executed" ] || [ "$executed" -lt 1 ]; then
    echo "swift-sim-test: $name ran no test - -only-testing matched nothing (renamed or removed?)" >&2
    exit 1
  fi
}
check_suite_ran "TabPetUIKitTests.xctest"
check_suite_ran "ResourceBundleLocatorTests"
check_suite_ran "TabPetAnimalsSimSafeTests"
