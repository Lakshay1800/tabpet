#!/usr/bin/env bash

# swift-demo-build.sh [device-id] - builds the demo app for the simulator,
# no signing; device-id is a udid, never a name or "booted", and defaults
# to the first available iPhone, same as tools/swift-sim-test.sh.

# Derived data sits outside the repository (a protected folder such as
# ~/Documents can be unopenable to the simulator host), reusing
# tools/swift-sim-test.sh's own by default so CI builds the package once.
set -euo pipefail
cd "$(dirname "$0")/../apps/swift-demo"

DERIVED_DATA_PATH="${SWIFT_DEMO_DERIVED_DATA:-${SWIFT_SIM_DERIVED_DATA:-${TMPDIR:-/tmp}/tabpet-swift-sim}}"

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
  echo "swift-demo-build: no available iPhone simulator found" >&2
  exit 1
fi

xcodebuild build \
  -project TabPetDemo.xcodeproj \
  -scheme TabPetDemo \
  -destination "id=$DEVICE_ID" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO
